import crypto from 'node:crypto';
import {
  EventType,
  ImportFormat,
  ImportJobStatus,
  ImportRowAction,
  Prisma,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds } from '../services/team-access';
import {
  competitionMatchChecksum,
  NormalizedCompetitionMatch,
  parseCompetitionSource,
} from '../services/competition-provider';
import { recalculateMatchStatistics } from '../services/statistics.service';
import { writeCompetitionMatch } from '../services/competition-import-write.service';
import { teamPlayingIdentity } from '../services/team-playing-identity.service';

export const competitionImportTransactionOptions = {
  // A seven-match BfV plan already performs several related writes per row.
  // Prisma's short interactive-transaction defaults are too tight for a
  // temporarily busy serverless database connection, even though the import
  // itself is valid and small.
  maxWait: 10_000,
  timeout: 20_000,
} as const;
import {
  matchCompetitionOpponents,
  normalizedCompetitionName,
} from '../services/competition-opponent-match.service';

const supportedProviders = new Set([
  'BFV_CSV',
  'DFBNET_CSV',
  'GENERIC_CSV',
  'ICS',
  'BFV_ICS',
]);

function text(value: unknown, max = 1000) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, max) : null;
}

function counts(rows: { action: ImportRowAction }[]) {
  const count = (action: ImportRowAction) =>
    rows.filter((row) => row.action === action).length;
  return {
    totalRows: rows.length,
    createCount: count(ImportRowAction.CREATE),
    updateCount: count(ImportRowAction.UPDATE),
    skipCount: count(ImportRowAction.SKIP),
    conflictCount: count(ImportRowAction.CONFLICT),
    invalidCount: count(ImportRowAction.INVALID),
  };
}

function eventImportKey(startAt: string | Date, opponent: string) {
  return `${new Date(startAt).getTime()}|${normalizedCompetitionName(opponent)}`;
}

export async function previewCompetitionImport(req: Request, res: Response) {
  const user = req.user!;
  const teamId = text(req.body?.teamId, 100);
  const format = String(req.body?.format ?? '').toUpperCase();
  const content = text(req.body?.content, 2_000_000);
  const provider =
    text(req.body?.provider, 80)?.toUpperCase() ??
    (format === ImportFormat.ICS ? 'ICS' : 'CSV');
  if (!teamId || !content || !Object.values(ImportFormat).includes(format as ImportFormat)) {
    return res.status(400).json({
      message: 'Mannschaft, Format und Dateiinhalt sind erforderlich.',
    });
  }
  if (!supportedProviders.has(provider)) {
    return res.status(400).json({
      message: 'Diese Importquelle wird nicht unterstützt.',
    });
  }
  if (!(await accessibleTeamIds(user)).includes(teamId)) {
    return res.status(403).json({ message: 'Kein Zugriff auf diese Mannschaft.' });
  }
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: {
      isPlayingCommunity: true,
      playingCommunityName: true,
      playingCommunityShortName: true,
      playingCommunityLogoUrl: true,
      ageGroup: {
        select: {
          season: {
            select: {
              club: {
                select: { name: true, shortName: true, logoUrl: true },
              },
            },
          },
        },
      },
    },
  });
  if (!team) {
    return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  }
  const ownTeam = teamPlayingIdentity(team);
  const parsed = await matchCompetitionOpponents(
    teamId,
    parseCompetitionSource(format as ImportFormat, content, {
      ownTeamNames: [ownTeam.name, ownTeam.shortName],
      displayOwnTeamName: ownTeam.name,
    }),
  );
  const externalIds = parsed
    .map((row) => row.match?.externalId)
    .filter((id): id is string => Boolean(id));
  const references = await prisma.externalReference.findMany({
    where: {
      provider: format === ImportFormat.ICS
        ? { in: ['ICS', 'BFV_ICS'] }
        : provider,
      entityType: 'Event',
      externalId: { in: externalIds },
    },
  });
  const referenceById = new Map(
    references.map((reference) => [reference.externalId, reference]),
  );
  const entityIds = references.map((reference) => reference.entityId);
  const events = await prisma.event.findMany({
    where: { id: { in: entityIds } },
    select: {
      id: true,
      teamId: true,
      updatedAt: true,
      matchDetails: { select: { updatedAt: true } },
    },
  });
  const eventById = new Map(events.map((event) => [event.id, event]));
  const validMatches = parsed.flatMap((row) => row.match ? [row.match] : []);
  const startTimes = validMatches.map((match) => new Date(match.startAt).getTime());
  const possibleExistingEvents = startTimes.length
    ? await prisma.event.findMany({
        where: {
          teamId,
          type: EventType.MATCH,
          startAt: {
            gte: new Date(Math.min(...startTimes) - 5 * 60_000),
            lte: new Date(Math.max(...startTimes) + 5 * 60_000),
          },
        },
        select: {
          id: true,
          startAt: true,
          opponent: true,
          matchDetails: { select: { opponent: true } },
        },
      })
    : [];
  const existingByKey = new Map<string, { id: string } | null>();
  for (const event of possibleExistingEvents) {
    const opponent = event.matchDetails?.opponent || event.opponent;
    if (!opponent) continue;
    const key = eventImportKey(event.startAt, opponent);
    existingByKey.set(key, existingByKey.has(key) ? null : { id: event.id });
  }
  const rows = parsed.map((row) => {
    if (!row.match) {
      return {
        rowNumber: row.rowNumber,
        externalId: null,
        action: ImportRowAction.INVALID,
        normalized: Prisma.JsonNull,
        messages: row.messages,
        entityId: null,
      };
    }
    const checksum = competitionMatchChecksum(row.match);
    const reference = referenceById.get(row.match.externalId);
    if (!reference) {
      const existing = existingByKey.get(
        eventImportKey(row.match.startAt, row.match.opponent),
      );
      if (existing) {
        return {
          rowNumber: row.rowNumber,
          externalId: row.match.externalId,
          action: ImportRowAction.UPDATE,
          normalized: row.match as unknown as Prisma.InputJsonValue,
          messages: [
            ...row.messages,
            'Bereits vorhandenes Spiel erkannt; es wird mit der ICS-UID verknüpft.',
          ],
          entityId: existing.id,
        };
      }
      return {
        rowNumber: row.rowNumber,
        externalId: row.match.externalId,
        action: ImportRowAction.CREATE,
        normalized: row.match as unknown as Prisma.InputJsonValue,
        messages: row.messages,
        entityId: null,
      };
    }
    const event = eventById.get(reference.entityId);
    if (!event) {
      return {
        rowNumber: row.rowNumber,
        externalId: row.match.externalId,
        action: ImportRowAction.CONFLICT,
        normalized: row.match as unknown as Prisma.InputJsonValue,
        messages: [
          ...row.messages,
          'Dieses importierte Spiel wurde zuvor bewusst gelöscht. '
            + 'Es wird nur nach ausdrücklicher Auswahl „Import übernehmen“ neu angelegt.',
        ],
        entityId: null,
      };
    }
    if (event.teamId !== teamId) {
      return {
        rowNumber: row.rowNumber,
        externalId: row.match.externalId,
        action: ImportRowAction.CONFLICT,
        normalized: row.match as unknown as Prisma.InputJsonValue,
        messages: [...row.messages, 'Externe Kennung gehört zu einem anderen Datensatz.'],
        entityId: reference.entityId,
      };
    }
    if (reference.sourceChecksum === checksum) {
      return {
        rowNumber: row.rowNumber,
        externalId: row.match.externalId,
        action: ImportRowAction.SKIP,
        normalized: row.match as unknown as Prisma.InputJsonValue,
        messages: [...row.messages, 'Unverändert seit dem letzten Import.'],
        entityId: event.id,
      };
    }
    const locallyChanged =
      Math.max(
        event.updatedAt.getTime(),
        event.matchDetails?.updatedAt.getTime() ?? 0,
      ) > reference.lastSyncedAt.getTime() + 1000;
    return {
      rowNumber: row.rowNumber,
      externalId: row.match.externalId,
      action: locallyChanged
        ? ImportRowAction.CONFLICT
        : ImportRowAction.UPDATE,
      normalized: row.match as unknown as Prisma.InputJsonValue,
      messages: locallyChanged
        ? [...row.messages, 'Lokale Änderungen seit dem letzten Abgleich erkannt.']
        : row.messages,
      entityId: event.id,
    };
  });
  const summary = counts(rows);
  const job = await prisma.importJob.create({
    data: {
      actorId: user.id,
      teamId,
      format: format as ImportFormat,
      provider,
      fileName: text(req.body?.fileName, 180),
      sourceHash: crypto.createHash('sha256').update(content).digest('hex'),
      ...summary,
      rows: { create: rows },
    },
    include: { rows: { orderBy: { rowNumber: 'asc' } } },
  });
  return res.status(201).json(job);
}

export async function applyCompetitionImport(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const job = await prisma.importJob.findFirst({
    where: { id: req.params.id, teamId: { in: teamIds } },
    include: { rows: { orderBy: { rowNumber: 'asc' } } },
  });
  if (!job) return res.status(404).json({ message: 'Importvorschau nicht gefunden.' });
  if (job.status === ImportJobStatus.APPLIED) return res.json(job);
  const sourceWins = req.body?.conflictPolicy === 'SOURCE_WINS';
  const selectedRowIdsInput = req.body?.selectedRowIds;
  if (selectedRowIdsInput != null && !Array.isArray(selectedRowIdsInput)) {
    return res.status(400).json({ message: 'Die Terminauswahl ist ungültig.' });
  }
  const selectedRowIds = selectedRowIdsInput == null
    ? null
    : new Set<string>(
        selectedRowIdsInput
          .map((value: unknown) => text(value, 100))
          .filter((value: string | null): value is string => Boolean(value)),
      );
  if (selectedRowIds && selectedRowIds.size === 0) {
    return res.status(400).json({
      message: 'Wähle mindestens einen Termin für den Import aus.',
    });
  }
  if (selectedRowIds) {
    const knownRowIds = new Set(job.rows.map((row) => row.id));
    if ([...selectedRowIds].some((rowId) => !knownRowIds.has(rowId))) {
      return res.status(400).json({
        message: 'Die Terminauswahl passt nicht mehr zu dieser Importvorschau.',
      });
    }
  }
  const requestedRows = selectedRowIds
    ? job.rows.filter((row) => selectedRowIds.has(row.id))
    : job.rows;
  const actionableRows = requestedRows.filter(
    (row) =>
      row.normalized &&
      row.action !== ImportRowAction.INVALID &&
      row.action !== ImportRowAction.SKIP &&
      (row.action !== ImportRowAction.CONFLICT || sourceWins),
  );
  const actionableRowIds = new Set(actionableRows.map((row) => row.id));
  const applied = await prisma.$transaction(async (tx) => {
    for (const row of actionableRows) {
      if (row.action === ImportRowAction.CONFLICT && row.entityId) {
        const ownedEntity = await tx.event.findFirst({
          where: { id: row.entityId, teamId: job.teamId },
          select: { id: true },
        });
        if (!ownedEntity) continue;
      }
      const entityId = await writeCompetitionMatch(
        tx,
        job.teamId,
        job.provider,
        row.normalized as unknown as NormalizedCompetitionMatch,
        row.entityId,
      );
      await tx.importRow.update({
        where: { id: row.id },
        data: { entityId },
      });
    }
    const savedJob = await tx.importJob.update({
      where: { id: job.id },
      data: { status: ImportJobStatus.APPLIED, appliedAt: new Date() },
      include: { rows: { orderBy: { rowNumber: 'asc' } } },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: job.teamId,
        action: 'COMPETITION_IMPORT_APPLIED',
        entityType: 'ImportJob',
        entityId: job.id,
        metadata: {
          provider: job.provider,
          format: job.format,
          sourceHash: job.sourceHash,
          createCount: job.createCount,
          updateCount: job.updateCount,
          conflictPolicy: sourceWins ? 'SOURCE_WINS' : 'SKIP',
          selectedRowCount: selectedRowIds?.size ?? requestedRows.length,
          appliedRowCount: actionableRows.length,
        },
      },
    });
    return savedJob;
  }, competitionImportTransactionOptions);
  const affectedIds = applied.rows
    .filter(
      (row) =>
        actionableRowIds.has(row.id) &&
        row.entityId &&
        row.action !== ImportRowAction.SKIP &&
        row.action !== ImportRowAction.INVALID,
    )
    .map((row) => row.entityId!);
  await Promise.all(
    affectedIds.map((eventId) =>
      recalculateMatchStatistics(eventId).catch(() => undefined),
    ),
  );
  return res.json(applied);
}

export async function listCompetitionImports(req: Request, res: Response) {
  const jobs = await prisma.importJob.findMany({
    where: { teamId: { in: await accessibleTeamIds(req.user!) } },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });
  return res.json(jobs);
}
