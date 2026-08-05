import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import { LeagueMatchStatus, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds } from '../services/team-access';
import { mediaAssetUrl } from '../services/media-access';
import { objectStorage } from '../services/object-storage';

const imageTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

function text(value: unknown, max = 200) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, max) : null;
}

function normalized(value: string) {
  return value
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('de-DE')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function validScore(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const score = Number(value);
  return Number.isInteger(score) && score >= 0 && score <= 99 ? score : Number.NaN;
}

async function accessibleAgeGroup(req: Request, ageGroupId: string) {
  const teamIds = await accessibleTeamIds(req.user!);
  const teams = await prisma.team.findMany({
    where: { id: { in: teamIds }, ageGroupId, deletedAt: null },
    select: { id: true },
  });
  return { teamIds, ageGroupTeamIds: teams.map((team) => team.id) };
}

const opponentInclude = {
  ageGroup: { select: { id: true, name: true, code: true } },
  logoAsset: { select: { id: true, deletedAt: true } },
} as const;

function serializeOpponent<T extends Prisma.OpponentGetPayload<{ include: typeof opponentInclude }>>(
  opponent: T,
) {
  return {
    ...opponent,
    logoAsset: undefined,
    logoUrl: opponent.logoAsset && opponent.logoAsset.deletedAt === null
      ? mediaAssetUrl(opponent.logoAsset.id, '12h')
      : null,
    displayName: `${opponent.clubName} ${opponent.teamDesignation}`.trim(),
  };
}

export async function listOpponents(req: Request, res: Response) {
  const ageGroupId = text(req.query.ageGroupId, 100);
  if (!ageGroupId) return res.status(400).json({ message: 'Jugend fehlt.' });
  const access = await accessibleAgeGroup(req, ageGroupId);
  if (!access.ageGroupTeamIds.length) {
    return res.status(403).json({ message: 'Kein Zugriff auf diese Jugend.' });
  }
  const opponents = await prisma.opponent.findMany({
    where: { ageGroupId, archivedAt: null },
    include: opponentInclude,
    orderBy: [{ clubName: 'asc' }, { teamDesignation: 'asc' }],
  });
  return res.json(opponents.map(serializeOpponent));
}

export async function saveOpponent(req: Request, res: Response) {
  const ageGroupId = text(req.body?.ageGroupId, 100);
  const clubName = text(req.body?.clubName, 120);
  const teamDesignation = text(req.body?.teamDesignation, 40);
  if (!ageGroupId || !clubName || !teamDesignation) {
    return res.status(400).json({ message: 'Jugend, Verein und Mannschaft sind erforderlich.' });
  }
  const access = await accessibleAgeGroup(req, ageGroupId);
  if (!access.ageGroupTeamIds.length) {
    return res.status(403).json({ message: 'Kein Zugriff auf diese Jugend.' });
  }
  const teamId = text(req.body?.teamId, 100);
  if (teamId && !access.ageGroupTeamIds.includes(teamId)) {
    return res.status(403).json({ message: 'Mannschaft gehört nicht zur ausgewählten Jugend.' });
  }
  const normalizedKey = normalized(`${clubName} ${teamDesignation}`);
  const duplicate = await prisma.opponent.findFirst({
    where: {
      ageGroupId,
      normalizedKey,
      archivedAt: null,
      ...(req.params.id ? { id: { not: req.params.id } } : {}),
    },
    select: { id: true },
  });
  if (duplicate) {
    return res.status(409).json({ message: 'Dieser Gegner ist in der Jugend bereits vorhanden.' });
  }
  const data = {
    ageGroupId,
    teamId,
    clubName,
    teamDesignation,
    normalizedKey,
    shortName: text(req.body?.shortName, 40),
    venue: text(req.body?.venue, 160),
    address: text(req.body?.address, 240),
  };
  const opponent = req.params.id
    ? await prisma.opponent.update({
        where: { id: req.params.id },
        data,
        include: opponentInclude,
      })
    : await prisma.opponent.create({
        data: { ...data, createdById: req.user!.id },
        include: opponentInclude,
      });
  await prisma.auditLog.create({
    data: {
      actorId: req.user!.id,
      teamId: teamId ?? access.ageGroupTeamIds[0],
      action: req.params.id ? 'OPPONENT_UPDATED' : 'OPPONENT_CREATED',
      entityType: 'Opponent',
      entityId: opponent.id,
    },
  });
  return res.status(req.params.id ? 200 : 201).json(serializeOpponent(opponent));
}

export async function archiveOpponent(req: Request, res: Response) {
  const opponent = await prisma.opponent.findUnique({
    where: { id: req.params.id },
    select: { id: true, ageGroupId: true, teamId: true },
  });
  if (!opponent) return res.status(404).json({ message: 'Gegner nicht gefunden.' });
  const access = await accessibleAgeGroup(req, opponent.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  await prisma.opponent.update({
    where: { id: opponent.id },
    data: { archivedAt: new Date() },
  });
  return res.status(204).send();
}

export async function uploadOpponentLogo(req: Request, res: Response) {
  const opponent = await prisma.opponent.findUnique({
    where: { id: req.params.id },
    include: { logoAsset: true },
  });
  if (!opponent) return res.status(404).json({ message: 'Gegner nicht gefunden.' });
  const access = await accessibleAgeGroup(req, opponent.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  if (!req.file || !imageTypes.has(req.file.mimetype)) {
    return res.status(400).json({ message: 'Bitte ein JPEG-, PNG- oder WebP-Bild auswählen.' });
  }
  const extension = req.file.mimetype === 'image/png' ? 'png'
    : req.file.mimetype === 'image/webp' ? 'webp' : 'jpg';
  const stored = await objectStorage.uploadPrivate(
    `opponents/${opponent.id}/${randomUUID()}.${extension}`,
    req.file.buffer,
    req.file.mimetype,
  );
  const previousPath = opponent.logoAsset?.pathname;
  const updated = await prisma.$transaction(async (tx) => {
    const asset = await tx.fileAsset.create({
      data: {
        kind: 'OPPONENT_LOGO',
        pathname: stored.pathname,
        storageUrl: stored.url,
        originalName: req.file!.originalname,
        contentType: req.file!.mimetype,
        size: req.file!.size,
        checksum: createHash('sha256').update(req.file!.buffer).digest('hex'),
        uploadedById: req.user!.id,
        isPrivate: true,
      },
    });
    const saved = await tx.opponent.update({
      where: { id: opponent.id },
      data: { logoAssetId: asset.id },
      include: opponentInclude,
    });
    if (opponent.logoAsset) {
      await tx.fileAsset.update({
        where: { id: opponent.logoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
    return saved;
  });
  if (previousPath) objectStorage.delete(previousPath).catch(() => undefined);
  return res.status(201).json(serializeOpponent(updated));
}

export async function removeOpponentLogo(req: Request, res: Response) {
  const opponent = await prisma.opponent.findUnique({
    where: { id: req.params.id },
    include: { logoAsset: true },
  });
  if (!opponent) return res.status(404).json({ message: 'Gegner nicht gefunden.' });
  const access = await accessibleAgeGroup(req, opponent.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  await prisma.$transaction(async (tx) => {
    await tx.opponent.update({ where: { id: opponent.id }, data: { logoAssetId: null } });
    if (opponent.logoAsset) {
      await tx.fileAsset.update({
        where: { id: opponent.logoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
  });
  if (opponent.logoAsset) {
    objectStorage.delete(opponent.logoAsset.pathname).catch(() => undefined);
  }
  return res.status(204).send();
}

type Standing = {
  entryId: string;
  name: string;
  isOwnTeam: boolean;
  games: number;
  wins: number;
  draws: number;
  losses: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifference: number;
  points: number;
};

export function calculateStandings(league: {
  pointsWin: number;
  pointsDraw: number;
  pointsLoss: number;
  entries: Array<{ id: string; displayName: string; ownTeamId: string | null }>;
  matches: Array<{
    homeEntryId: string;
    awayEntryId: string;
    status: LeagueMatchStatus;
    homeGoals: number | null;
    awayGoals: number | null;
  }>;
}) {
  const rows = new Map<string, Standing>(league.entries.map((entry) => [entry.id, {
    entryId: entry.id,
    name: entry.displayName,
    isOwnTeam: entry.ownTeamId !== null,
    games: 0,
    wins: 0,
    draws: 0,
    losses: 0,
    goalsFor: 0,
    goalsAgainst: 0,
    goalDifference: 0,
    points: 0,
  }]));
  for (const match of league.matches) {
    if (match.status !== LeagueMatchStatus.FINISHED ||
        match.homeGoals === null || match.awayGoals === null) continue;
    const home = rows.get(match.homeEntryId);
    const away = rows.get(match.awayEntryId);
    if (!home || !away) continue;
    home.games += 1;
    away.games += 1;
    home.goalsFor += match.homeGoals;
    home.goalsAgainst += match.awayGoals;
    away.goalsFor += match.awayGoals;
    away.goalsAgainst += match.homeGoals;
    if (match.homeGoals > match.awayGoals) {
      home.wins += 1;
      away.losses += 1;
      home.points += league.pointsWin;
      away.points += league.pointsLoss;
    } else if (match.homeGoals < match.awayGoals) {
      away.wins += 1;
      home.losses += 1;
      away.points += league.pointsWin;
      home.points += league.pointsLoss;
    } else {
      home.draws += 1;
      away.draws += 1;
      home.points += league.pointsDraw;
      away.points += league.pointsDraw;
    }
  }
  return [...rows.values()]
    .map((row) => ({ ...row, goalDifference: row.goalsFor - row.goalsAgainst }))
    .sort((left, right) =>
      right.points - left.points ||
      right.goalDifference - left.goalDifference ||
      right.goalsFor - left.goalsFor ||
      left.name.localeCompare(right.name, 'de'),
    )
    .map((row, index) => ({ rank: index + 1, ...row }));
}

const leagueInclude = {
  season: { include: { club: true } },
  ageGroup: { select: { id: true, name: true, code: true } },
  entries: {
    orderBy: [{ sortOrder: 'asc' as const }, { displayName: 'asc' as const }],
    include: {
      opponent: { include: { logoAsset: { select: { id: true, deletedAt: true } } } },
      ownTeam: { select: { id: true, name: true, shortName: true } },
    },
  },
  matches: {
    orderBy: [{ startsAt: 'asc' as const }, { createdAt: 'asc' as const }],
    include: {
      homeEntry: { select: { id: true, displayName: true } },
      awayEntry: { select: { id: true, displayName: true } },
    },
  },
} satisfies Prisma.LeagueInclude;

function serializeLeague<T extends Prisma.LeagueGetPayload<{ include: typeof leagueInclude }>>(league: T) {
  return {
    ...league,
    entries: league.entries.map((entry) => ({
      ...entry,
      logoUrl: entry.opponent?.logoAsset && entry.opponent.logoAsset.deletedAt === null
        ? mediaAssetUrl(entry.opponent.logoAsset.id, '12h')
        : entry.ownTeamId
          ? league.season.club.logoUrl
          : null,
      isOwnTeam: entry.ownTeamId !== null,
    })),
    standings: calculateStandings(league),
  };
}

export async function listLeagues(req: Request, res: Response) {
  const ageGroupId = text(req.query.ageGroupId, 100);
  if (!ageGroupId) return res.status(400).json({ message: 'Jugend fehlt.' });
  const access = await accessibleAgeGroup(req, ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  const leagues = await prisma.league.findMany({
    where: { ageGroupId, archivedAt: null },
    include: leagueInclude,
    orderBy: { name: 'asc' },
  });
  return res.json(leagues.map(serializeLeague));
}

export async function saveLeague(req: Request, res: Response) {
  const ageGroupId = text(req.body?.ageGroupId, 100);
  const seasonId = text(req.body?.seasonId, 100);
  const name = text(req.body?.name, 120);
  if (!ageGroupId || !seasonId || !name) {
    return res.status(400).json({ message: 'Name, Saison und Jugend sind erforderlich.' });
  }
  const access = await accessibleAgeGroup(req, ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  const teamId = text(req.body?.teamId, 100);
  if (teamId && !access.ageGroupTeamIds.includes(teamId)) {
    return res.status(403).json({ message: 'Mannschaft gehört nicht zur Jugend.' });
  }
  const ageGroup = await prisma.ageGroup.findFirst({ where: { id: ageGroupId, seasonId } });
  if (!ageGroup) return res.status(400).json({ message: 'Jugend und Saison passen nicht zusammen.' });
  const opponentIds: string[] = [...new Set<string>(
    (Array.isArray(req.body?.opponentIds) ? req.body.opponentIds : [])
      .map((value: unknown) => text(value, 100))
      .filter((value: string | null): value is string => Boolean(value)),
  )];
  const ownTeamIds: string[] = [...new Set<string>(
    (Array.isArray(req.body?.ownTeamIds) ? req.body.ownTeamIds : teamId ? [teamId] : [])
      .map((value: unknown) => text(value, 100))
      .filter((value: string | null): value is string => Boolean(value)),
  )];
  if (!ownTeamIds.every((id) => access.ageGroupTeamIds.includes(id))) {
    return res.status(403).json({ message: 'Eigene Mannschaft ist nicht freigegeben.' });
  }
  const opponents = await prisma.opponent.findMany({
    where: { id: { in: opponentIds }, ageGroupId, archivedAt: null },
    select: { id: true, clubName: true, teamDesignation: true },
  });
  if (opponents.length !== opponentIds.length) {
    return res.status(400).json({ message: 'Mindestens ein Gegner ist ungültig.' });
  }
  const ownTeams = await prisma.team.findMany({
    where: { id: { in: ownTeamIds }, ageGroupId, deletedAt: null },
    select: { id: true, name: true },
  });
  const league = await prisma.$transaction(async (tx) => {
    const saved = req.params.id
      ? await tx.league.update({
          where: { id: req.params.id },
          data: { name, normalizedName: normalized(name), teamId },
        })
      : await tx.league.create({
          data: {
            name,
            normalizedName: normalized(name),
            seasonId,
            ageGroupId,
            teamId,
            createdById: req.user!.id,
          },
        });
    if (Object.prototype.hasOwnProperty.call(req.body, 'opponentIds') ||
        Object.prototype.hasOwnProperty.call(req.body, 'ownTeamIds')) {
      const referencedEntryIds = await tx.leagueMatch.findMany({
        where: { leagueId: saved.id },
        select: { homeEntryId: true, awayEntryId: true },
      });
      const protectedIds = new Set(referencedEntryIds.flatMap((match) => [
        match.homeEntryId,
        match.awayEntryId,
      ]));
      await tx.leagueEntry.deleteMany({
        where: { leagueId: saved.id, id: { notIn: [...protectedIds] } },
      });
      for (const [index, team] of ownTeams.entries()) {
        await tx.leagueEntry.upsert({
          where: { leagueId_ownTeamId: { leagueId: saved.id, ownTeamId: team.id } },
          update: { displayName: team.name, sortOrder: index },
          create: {
            leagueId: saved.id,
            ownTeamId: team.id,
            displayName: team.name,
            sortOrder: index,
          },
        });
      }
      for (const [index, opponent] of opponents.entries()) {
        await tx.leagueEntry.upsert({
          where: { leagueId_opponentId: { leagueId: saved.id, opponentId: opponent.id } },
          update: {
            displayName: `${opponent.clubName} ${opponent.teamDesignation}`.trim(),
            sortOrder: ownTeams.length + index,
          },
          create: {
            leagueId: saved.id,
            opponentId: opponent.id,
            displayName: `${opponent.clubName} ${opponent.teamDesignation}`.trim(),
            sortOrder: ownTeams.length + index,
          },
        });
      }
    }
    return tx.league.findUniqueOrThrow({ where: { id: saved.id }, include: leagueInclude });
  });
  return res.status(req.params.id ? 200 : 201).json(serializeLeague(league));
}

export async function saveLeagueMatch(req: Request, res: Response) {
  const league = await prisma.league.findUnique({
    where: { id: req.params.leagueId },
    include: { entries: true },
  });
  if (!league) return res.status(404).json({ message: 'Liga nicht gefunden.' });
  const access = await accessibleAgeGroup(req, league.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  const homeEntryId = text(req.body?.homeEntryId, 100);
  const awayEntryId = text(req.body?.awayEntryId, 100);
  if (!homeEntryId || !awayEntryId || homeEntryId === awayEntryId ||
      !league.entries.some((entry) => entry.id === homeEntryId) ||
      !league.entries.some((entry) => entry.id === awayEntryId)) {
    return res.status(400).json({ message: 'Heim- und Auswärtsmannschaft sind ungültig.' });
  }
  const homeGoals = validScore(req.body?.homeGoals);
  const awayGoals = validScore(req.body?.awayGoals);
  if (Number.isNaN(homeGoals) || Number.isNaN(awayGoals)) {
    return res.status(400).json({ message: 'Ergebnisse müssen zwischen 0 und 99 liegen.' });
  }
  const requestedStatus = String(req.body?.status ?? '').toUpperCase();
  const status = Object.values(LeagueMatchStatus).includes(requestedStatus as LeagueMatchStatus)
    ? requestedStatus as LeagueMatchStatus
    : homeGoals !== null && awayGoals !== null
      ? LeagueMatchStatus.FINISHED
      : LeagueMatchStatus.SCHEDULED;
  if (status === LeagueMatchStatus.FINISHED && (homeGoals === null || awayGoals === null)) {
    return res.status(400).json({ message: 'Für ein beendetes Spiel ist ein Ergebnis erforderlich.' });
  }
  const startsAt = req.body?.startsAt ? new Date(String(req.body.startsAt)) : null;
  if (startsAt && Number.isNaN(startsAt.getTime())) {
    return res.status(400).json({ message: 'Ungültiger Spieltermin.' });
  }
  const data = {
    leagueId: league.id,
    homeEntryId,
    awayEntryId,
    startsAt,
    status,
    homeGoals,
    awayGoals,
    externalUid: text(req.body?.externalUid, 300),
    venue: text(req.body?.venue, 160),
    notes: text(req.body?.notes, 1000),
  };
  const match = req.params.matchId
    ? await prisma.leagueMatch.update({ where: { id: req.params.matchId }, data })
    : await prisma.leagueMatch.create({ data });
  const reloaded = await prisma.league.findUniqueOrThrow({
    where: { id: league.id },
    include: leagueInclude,
  });
  return res.status(req.params.matchId ? 200 : 201).json({
    match,
    standings: calculateStandings(reloaded),
  });
}

export async function archiveLeague(req: Request, res: Response) {
  const league = await prisma.league.findUnique({ where: { id: req.params.id } });
  if (!league) return res.status(404).json({ message: 'Liga nicht gefunden.' });
  const access = await accessibleAgeGroup(req, league.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  await prisma.league.update({ where: { id: league.id }, data: { archivedAt: new Date() } });
  return res.status(204).send();
}
