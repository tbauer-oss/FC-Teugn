import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import {
  AccountStatus,
  LeagueMatchStatus,
  MatchStatus,
  NotificationCategory,
  Prisma,
  Role,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, clubIdForTeam } from '../services/team-access';
import { mediaAssetUrl } from '../services/media-access';
import { objectStorage } from '../services/object-storage';
import { hasEffectivePermission, Permission } from '../security/permissions';
import { reminderRecipientsForEvent } from '../services/reminder.service';
import { notifyUsers } from '../services/notification.service';

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

export function canonicalTeamDesignation(value: string, ageCode: string) {
  const prefix = ageCode
    .toLocaleUpperCase('de-DE')
    .replace(/[^A-ZÄÖÜ]/g, '')
    .slice(0, 1);
  const raw = value.toLocaleUpperCase('de-DE').trim();
  const legacyNumber = raw.match(/^[A-ZÄÖÜ]+\d+\s+(\d{1,2})$/)?.[1];
  if (prefix && legacyNumber) return `${prefix}${legacyNumber}`;
  const compact = raw.replace(/\s+/g, '');
  if (['E7', 'D9', 'C11', 'B11', 'A11', 'F5', 'F7', 'G3', 'G5']
      .includes(compact)) {
    return `${prefix || compact.slice(0, 1)}1`;
  }
  return compact;
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
  opponentClub: {
    include: { logoAsset: { select: { id: true, deletedAt: true } } },
  },
} as const;

const opponentClubInclude = {
  logoAsset: { select: { id: true, deletedAt: true } },
  teams: {
    where: { archivedAt: null },
    select: {
      id: true,
      ageGroupId: true,
      teamId: true,
      teamDesignation: true,
      shortName: true,
    },
    orderBy: { teamDesignation: 'asc' },
  },
} satisfies Prisma.OpponentClubInclude;

async function organizationClubId(req: Request) {
  return clubIdForTeam(req.user!.teamId);
}

function serializeOpponentClub<
  T extends Prisma.OpponentClubGetPayload<{ include: typeof opponentClubInclude }>,
>(club: T) {
  return {
    ...club,
    logoAsset: undefined,
    logoUrl: club.logoAsset && club.logoAsset.deletedAt === null
      ? mediaAssetUrl(club.logoAsset.id, '12h')
      : null,
  };
}

function serializeOpponent<T extends Prisma.OpponentGetPayload<{ include: typeof opponentInclude }>>(
  opponent: T,
) {
  const teamDesignation = canonicalTeamDesignation(
    opponent.teamDesignation,
    opponent.ageGroup.code,
  );
  return {
    ...opponent,
    logoAsset: undefined,
    opponentClub: undefined,
    clubName: opponent.opponentClub.name,
    shortName: opponent.opponentClub.shortName ?? opponent.shortName,
    venue: opponent.opponentClub.venue,
    address: opponent.opponentClub.address,
    teamDesignation,
    logoUrl: opponent.opponentClub.logoAsset &&
      opponent.opponentClub.logoAsset.deletedAt === null
      ? mediaAssetUrl(opponent.opponentClub.logoAsset.id, '12h')
      : opponent.logoAsset && opponent.logoAsset.deletedAt === null
        ? mediaAssetUrl(opponent.logoAsset.id, '12h')
      : null,
    displayName: `${opponent.opponentClub.name} ${teamDesignation}`.trim(),
  };
}

export async function listOpponentClubs(req: Request, res: Response) {
  const clubId = await organizationClubId(req);
  if (!clubId) return res.status(403).json({ message: 'Vereinskontext fehlt.' });
  const clubs = await prisma.opponentClub.findMany({
    where: { organizationClubId: clubId, archivedAt: null },
    include: opponentClubInclude,
    orderBy: { name: 'asc' },
  });
  return res.json(clubs.map(serializeOpponentClub));
}

export async function saveOpponentClub(req: Request, res: Response) {
  const organizationId = await organizationClubId(req);
  if (!organizationId) {
    return res.status(403).json({ message: 'Vereinskontext fehlt.' });
  }
  const name = text(req.body?.name ?? req.body?.clubName, 120);
  if (!name) return res.status(400).json({ message: 'Vereinsname fehlt.' });
  const normalizedName = normalized(name);
  const duplicate = await prisma.opponentClub.findFirst({
    where: {
      organizationClubId: organizationId,
      normalizedName,
      archivedAt: null,
      ...(req.params.id ? { id: { not: req.params.id } } : {}),
    },
    select: { id: true },
  });
  if (duplicate) {
    return res.status(409).json({ message: 'Dieser Verein ist bereits vorhanden.' });
  }
  const data = {
    name,
    normalizedName,
    shortName: text(req.body?.shortName, 40),
    venue: text(req.body?.venue, 160),
    address: text(req.body?.address, 240),
  };
  const club = req.params.id
    ? await prisma.opponentClub.update({
        where: { id: req.params.id, organizationClubId: organizationId },
        data,
        include: opponentClubInclude,
      })
    : await prisma.opponentClub.create({
        data: {
          ...data,
          organizationClubId: organizationId,
          createdById: req.user!.id,
        },
        include: opponentClubInclude,
      });
  // Legacy-Spalten bleiben synchron, damit ältere App-Versionen und bereits
  // gespeicherte Spiele während der Umstellung weiterhin korrekt arbeiten.
  await prisma.opponent.updateMany({
    where: { opponentClubId: club.id },
    data: {
      clubName: club.name,
      venue: club.venue,
      address: club.address,
    },
  });
  return res.status(req.params.id ? 200 : 201).json(serializeOpponentClub(club));
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
  const teamDesignation = text(req.body?.teamDesignation, 40);
  if (!ageGroupId || !teamDesignation) {
    return res.status(400).json({ message: 'Jugend und Mannschaft sind erforderlich.' });
  }
  const access = await accessibleAgeGroup(req, ageGroupId);
  if (!access.ageGroupTeamIds.length) {
    return res.status(403).json({ message: 'Kein Zugriff auf diese Jugend.' });
  }
  const teamId = text(req.body?.teamId, 100);
  if (teamId && !access.ageGroupTeamIds.includes(teamId)) {
    return res.status(403).json({ message: 'Mannschaft gehört nicht zur ausgewählten Jugend.' });
  }
  const ageGroup = await prisma.ageGroup.findUnique({
    where: { id: ageGroupId },
    select: { code: true, season: { select: { clubId: true } } },
  });
  if (!ageGroup) return res.status(404).json({ message: 'Jugend nicht gefunden.' });
  const designation = canonicalTeamDesignation(teamDesignation, ageGroup.code);
  const ageCode = ageGroup.code
    .toLocaleUpperCase('de-DE')
    .replace(/[^A-ZÄÖÜ]/g, '')
    .slice(0, 1);
  if (ageCode && !new RegExp(`^${ageCode}\\d{1,2}$`).test(designation)) {
    return res.status(400).json({
      message: `Bitte eine Mannschaft der ${ageGroup.code}-Jugend wählen, z. B. ${ageGroup.code}1.`,
    });
  }
  let opponentClubId = text(req.body?.opponentClubId, 100);
  let club = opponentClubId
    ? await prisma.opponentClub.findFirst({
        where: {
          id: opponentClubId,
          organizationClubId: ageGroup.season.clubId,
          archivedAt: null,
        },
      })
    : null;
  // Übergangskompatibilität für ältere Clients: Ein übermittelter Vereinsname
  // wird einmalig in den zentralen Vereins-Pool übernommen.
  if (!club) {
    const legacyClubName = text(req.body?.clubName, 120);
    if (!legacyClubName) {
      return res.status(400).json({ message: 'Bitte einen Verein auswählen.' });
    }
    const normalizedName = normalized(legacyClubName);
    club = await prisma.opponentClub.upsert({
      where: {
        organizationClubId_normalizedName: {
          organizationClubId: ageGroup.season.clubId,
          normalizedName,
        },
      },
      update: {},
      create: {
        organizationClubId: ageGroup.season.clubId,
        name: legacyClubName,
        normalizedName,
        venue: text(req.body?.venue, 160),
        address: text(req.body?.address, 240),
        createdById: req.user!.id,
      },
    });
    opponentClubId = club.id;
  }
  const normalizedKey = normalized(`${club.id} ${designation}`);
  const existingTeams = await prisma.opponent.findMany({
    where: {
      ageGroupId,
      opponentClubId: club.id,
      archivedAt: null,
      ...(req.params.id ? { id: { not: req.params.id } } : {}),
    },
    select: { id: true, teamDesignation: true },
  });
  const duplicate = existingTeams.find(
    (item) => canonicalTeamDesignation(item.teamDesignation, ageGroup.code) === designation,
  );
  if (duplicate) {
    return res.status(409).json({ message: 'Dieser Gegner ist in der Jugend bereits vorhanden.' });
  }
  const data = {
    ageGroupId,
    teamId,
    opponentClubId: club.id,
    clubName: club.name,
    teamDesignation: designation,
    normalizedKey,
    shortName: text(req.body?.shortName, 40) ?? club.shortName,
    venue: club.venue,
    address: club.address,
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
    include: { opponentClub: { include: { logoAsset: true } } },
  });
  if (!opponent) return res.status(404).json({ message: 'Gegner nicht gefunden.' });
  const access = await accessibleAgeGroup(req, opponent.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  return storeOpponentClubLogo(req, res, opponent.opponentClub, opponent.id);
}

export async function uploadOpponentClubLogo(req: Request, res: Response) {
  const organizationId = await organizationClubId(req);
  if (!organizationId) return res.status(403).json({ message: 'Vereinskontext fehlt.' });
  const club = await prisma.opponentClub.findFirst({
    where: {
      id: req.params.id,
      organizationClubId: organizationId,
      archivedAt: null,
    },
    include: { logoAsset: true },
  });
  if (!club) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  return storeOpponentClubLogo(req, res, club);
}

async function storeOpponentClubLogo(
  req: Request,
  res: Response,
  club: Prisma.OpponentClubGetPayload<{ include: { logoAsset: true } }>,
  legacyOpponentId?: string,
) {
  if (!req.file || !imageTypes.has(req.file.mimetype)) {
    return res.status(400).json({ message: 'Bitte ein JPEG-, PNG- oder WebP-Bild auswählen.' });
  }
  const extension = req.file.mimetype === 'image/png' ? 'png'
    : req.file.mimetype === 'image/webp' ? 'webp' : 'jpg';
  const stored = await objectStorage.uploadPrivate(
    `opponent-clubs/${club.id}/${randomUUID()}.${extension}`,
    req.file.buffer,
    req.file.mimetype,
  );
  const previousPath = club.logoAsset?.pathname;
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
    const saved = await tx.opponentClub.update({
      where: { id: club.id },
      data: { logoAssetId: asset.id },
      include: opponentClubInclude,
    });
    if (club.logoAsset) {
      await tx.fileAsset.update({
        where: { id: club.logoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
    return saved;
  });
  if (previousPath) objectStorage.delete(previousPath).catch(() => undefined);
  if (legacyOpponentId) {
    const refreshed = await prisma.opponent.findUnique({
      where: { id: legacyOpponentId },
      include: opponentInclude,
    });
    if (refreshed) return res.status(201).json(serializeOpponent(refreshed));
  }
  return res.status(201).json(serializeOpponentClub(updated));
}

export async function removeOpponentLogo(req: Request, res: Response) {
  const opponent = await prisma.opponent.findUnique({
    where: { id: req.params.id },
    include: { opponentClub: { include: { logoAsset: true } } },
  });
  if (!opponent) return res.status(404).json({ message: 'Gegner nicht gefunden.' });
  const access = await accessibleAgeGroup(req, opponent.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  return removeClubLogo(res, opponent.opponentClub);
}

export async function removeOpponentClubLogo(req: Request, res: Response) {
  const organizationId = await organizationClubId(req);
  if (!organizationId) return res.status(403).json({ message: 'Vereinskontext fehlt.' });
  const club = await prisma.opponentClub.findFirst({
    where: {
      id: req.params.id,
      organizationClubId: organizationId,
      archivedAt: null,
    },
    include: { logoAsset: true },
  });
  if (!club) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  return removeClubLogo(res, club);
}

async function removeClubLogo(
  res: Response,
  club: Prisma.OpponentClubGetPayload<{ include: { logoAsset: true } }>,
) {
  await prisma.$transaction(async (tx) => {
    await tx.opponentClub.update({ where: { id: club.id }, data: { logoAssetId: null } });
    if (club.logoAsset) {
      await tx.fileAsset.update({
        where: { id: club.logoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
  });
  if (club.logoAsset) {
    objectStorage.delete(club.logoAsset.pathname).catch(() => undefined);
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
      opponent: {
        include: {
          logoAsset: { select: { id: true, deletedAt: true } },
          opponentClub: {
            include: { logoAsset: { select: { id: true, deletedAt: true } } },
          },
        },
      },
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
      logoUrl: entry.opponent?.opponentClub.logoAsset &&
        entry.opponent.opponentClub.logoAsset.deletedAt === null
        ? mediaAssetUrl(entry.opponent.opponentClub.logoAsset.id, '12h')
        : entry.opponent?.logoAsset && entry.opponent.logoAsset.deletedAt === null
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

export async function deleteLeagueMatch(req: Request, res: Response) {
  const user = req.user!;
  const match = await prisma.leagueMatch.findFirst({
    where: { id: req.params.matchId, leagueId: req.params.leagueId },
    include: {
      league: true,
      homeEntry: true,
      awayEntry: true,
      event: { include: { targetTeams: true } },
    },
  });
  if (!match) return res.status(404).json({ message: 'Ligapartie nicht gefunden.' });
  const access = await accessibleAgeGroup(req, match.league.ageGroupId);
  if (!access.ageGroupTeamIds.length) {
    return res.status(403).json({ message: 'Kein Zugriff auf diese Liga.' });
  }
  const deleteLinkedEvent = req.query.deleteLinkedEvent === 'true';
  if (
    deleteLinkedEvent &&
    !hasEffectivePermission(user.role, Permission.MATCH_DELETE, user.permissions)
  ) {
    return res.status(403).json({
      message: 'Zum Löschen des verknüpften Spieltags fehlt die Berechtigung.',
      permission: Permission.MATCH_DELETE,
    });
  }
  await prisma.$transaction(async (tx) => {
    if (deleteLinkedEvent && match.eventId) {
      await tx.notification.deleteMany({ where: { entityId: match.eventId } });
      await tx.event.delete({ where: { id: match.eventId } });
    } else if (match.eventId) {
      await tx.matchDetails.updateMany({
        where: { eventId: match.eventId, leagueId: match.leagueId },
        data: { leagueId: null },
      });
    }
    await tx.leagueMatch.delete({ where: { id: match.id } });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.league.teamId ?? access.ageGroupTeamIds[0],
        action: 'LEAGUE_MATCH_PERMANENTLY_DELETED',
        entityType: 'LeagueMatch',
        entityId: match.id,
        metadata: {
          leagueId: match.leagueId,
          league: match.league.name,
          home: match.homeEntry.displayName,
          away: match.awayEntry.displayName,
          startsAt: match.startsAt,
          eventId: match.eventId,
          deleteLinkedEvent,
          externalUid: match.externalUid,
        },
      },
    });
  });
  return res.json({ status: 'DELETED', standingsRecalculated: true });
}

export async function cancelLeagueMatch(req: Request, res: Response) {
  const user = req.user!;
  const match = await prisma.leagueMatch.findFirst({
    where: { id: req.params.matchId, leagueId: req.params.leagueId },
    include: {
      league: true,
      homeEntry: true,
      awayEntry: true,
      event: { include: { targetTeams: true } },
    },
  });
  if (!match) return res.status(404).json({ message: 'Ligapartie nicht gefunden.' });
  const access = await accessibleAgeGroup(req, match.league.ageGroupId);
  if (!access.ageGroupTeamIds.length) {
    return res.status(403).json({ message: 'Kein Zugriff auf diese Liga.' });
  }
  const reason = text(req.body.reason, 1000);
  if (!reason) return res.status(400).json({ message: 'Bitte einen Absagegrund angeben.' });
  const now = new Date();
  const audience = match.eventId
    ? await reminderRecipientsForEvent(match.eventId)
    : { recipientIds: [] as string[] };
  const teamIds = match.event
    ? match.event.targetTeams.length
      ? match.event.targetTeams.map((target) => target.teamId)
      : [match.event.teamId]
    : access.ageGroupTeamIds;
  const staff = await prisma.teamMembership.findMany({
    where: {
      teamId: { in: teamIds },
      status: AccountStatus.APPROVED,
      role: {
        in: [
          Role.SUPER_ADMIN,
          Role.CLUB_ADMIN,
          Role.YOUTH_DIRECTOR,
          Role.TRAINER_ADMIN,
          Role.COACH,
          Role.TRAINER,
          Role.ASSISTANT_COACH,
          Role.TEAM_MANAGER,
        ],
      },
    },
    select: { userId: true },
  });
  await prisma.$transaction(async (tx) => {
    await tx.leagueMatch.update({
      where: { id: match.id },
      data: { status: LeagueMatchStatus.CANCELLED, notes: reason },
    });
    if (match.eventId) {
      await tx.event.update({
        where: { id: match.eventId },
        data: {
          status: 'CANCELLED',
          cancellationReason: reason,
          cancelledAt: now,
          attendanceFinalized: true,
        },
      });
      await tx.matchDetails.updateMany({
        where: { eventId: match.eventId },
        data: { status: MatchStatus.CANCELLED },
      });
      await tx.scheduledReminder.updateMany({
        where: {
          eventId: match.eventId,
          status: { in: ['SCHEDULED', 'FAILED', 'PROCESSING'] },
        },
        data: { status: 'CANCELLED', cancelledAt: now },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.league.teamId ?? access.ageGroupTeamIds[0],
        action: 'LEAGUE_MATCH_CANCELLED',
        entityType: 'LeagueMatch',
        entityId: match.id,
        metadata: {
          leagueId: match.leagueId,
          eventId: match.eventId,
          home: match.homeEntry.displayName,
          away: match.awayEntry.displayName,
          reason,
        },
      },
    });
  });
  const delivery = await notifyUsers(
    [...audience.recipientIds, ...staff.map((item) => item.userId)]
      .filter((id) => id !== user.id),
    {
      category: NotificationCategory.MATCH,
      title: 'Ligaspiel abgesagt',
      body: `${match.homeEntry.displayName} – ${match.awayEntry.displayName} wurde abgesagt. Grund: ${reason}`,
      actionUrl: match.eventId ? `/matches/${match.eventId}` : '/matches',
      entityType: 'LeagueMatchCancellation',
      entityId: match.eventId ?? match.id,
      dedupeKey: `league-match-cancelled:${match.id}`,
      forceInApp: true,
      forcePush: true,
    },
  );
  return res.json({ status: LeagueMatchStatus.CANCELLED, reason, delivery });
}

export async function archiveLeague(req: Request, res: Response) {
  const league = await prisma.league.findUnique({ where: { id: req.params.id } });
  if (!league) return res.status(404).json({ message: 'Liga nicht gefunden.' });
  const access = await accessibleAgeGroup(req, league.ageGroupId);
  if (!access.ageGroupTeamIds.length) return res.status(403).json({ message: 'Kein Zugriff.' });
  await prisma.league.update({ where: { id: league.id }, data: { archivedAt: new Date() } });
  return res.status(204).send();
}
