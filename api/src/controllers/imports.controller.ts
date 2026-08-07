import crypto from 'node:crypto';
import {
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
  const parsed = parseCompetitionSource(format as ImportFormat, content);
  const externalIds = parsed
    .map((row) => row.match?.externalId)
    .filter((id): id is string => Boolean(id));
  const references = await prisma.externalReference.findMany({
    where: {
      provider,
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
  const applied = await prisma.$transaction(async (tx) => {
    for (const row of job.rows) {
      if (
        !row.normalized ||
        row.action === ImportRowAction.INVALID ||
        row.action === ImportRowAction.SKIP ||
        (row.action === ImportRowAction.CONFLICT && !sourceWins)
      ) {
        continue;
      }
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
    return tx.importJob.update({
      where: { id: job.id },
      data: { status: ImportJobStatus.APPLIED, appliedAt: new Date() },
      include: { rows: { orderBy: { rowNumber: 'asc' } } },
    });
  });
  await prisma.auditLog.create({
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
      },
    },
  });
  const affectedIds = applied.rows
    .filter(
      (row) =>
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
