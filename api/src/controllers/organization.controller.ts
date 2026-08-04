import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import {
  AccountStatus,
  EventType,
  PlayerStatus,
  Prisma,
  Role,
  TeamGameFormat,
  TeamGender,
  TeamType,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Permission, permissionsForRole } from '../security/permissions';
import {
  accessibleTeamIds,
  canManageFormation,
  canManageTeam,
  resolveContextTeamId,
} from '../services/team-access';
import { objectStorage } from '../services/object-storage';
import { mediaAssetUrl } from '../services/media-access';
import {
  fieldSizeForGameFormat,
  syncSquadWithTeamDefaultLineup,
} from '../services/default-lineup.service';

const staffRoles: Role[] = [
  Role.SUPER_ADMIN,
  Role.CLUB_ADMIN,
  Role.YOUTH_DIRECTOR,
  Role.TRAINER_ADMIN,
  Role.COACH,
  Role.TRAINER,
  Role.ASSISTANT_COACH,
  Role.TEAM_MANAGER,
];
const imageTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

const hierarchyInclude = {
  ageGroup: {
    include: {
      season: {
        include: { club: true },
      },
    },
  },
  photoAsset: true,
  memberships: {
    where: { status: AccountStatus.APPROVED, role: { in: staffRoles } },
    orderBy: { createdAt: 'asc' as const },
    select: {
      role: true,
      user: { select: { id: true, name: true, email: true } },
    },
  },
  defaultLineupPositions: {
    orderBy: { sortOrder: 'asc' as const },
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          position: true,
          secondaryPosition: true,
          shirtNumber: true,
          status: true,
        },
      },
    },
  },
} as const;

type TeamInput = {
  ageGroupId?: string;
  teamNumber?: unknown;
  name?: string;
  shortName?: string | null;
  level?: string | null;
  teamType?: TeamType;
  gender?: TeamGender;
  gameFormat?: TeamGameFormat;
  periodCount?: unknown;
  periodMinutes?: unknown;
  birthYears?: unknown;
  description?: string | null;
  trainingLocation?: string | null;
  trainingTimes?: unknown;
  seasonStartDate?: unknown;
  seasonEndDate?: unknown;
  indoorSeasonStartDate?: unknown;
  indoorSeasonEndDate?: unknown;
  indoorTrainingLocation?: string | null;
  indoorTrainingTimes?: unknown;
  homeVenue?: string | null;
  bfvTeamId?: string | null;
  dfbnetTeamId?: string | null;
  bfvTeamUrl?: string | null;
  isActive?: boolean;
};

function optionalText(value: unknown, maxLength: number) {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text ? text.slice(0, maxLength) : null;
}

export function baseFormationOf(value: string) {
  const match = /^(\d+(?:-\d+)+)(?:\s*·\s*([^·\r\n]{1,24}))?$/.exec(
    value.trim(),
  );
  return match?.[1] ?? null;
}

export function validFormation(value: string, fieldSize: number) {
  const baseFormation = baseFormationOf(value);
  if (!baseFormation) return false;
  const rows = baseFormation.split('-').map(Number);
  return rows.some((count) => count > 0) &&
    rows.every((count) => Number.isInteger(count) && count >= 0 && count <= 6) &&
    rows.reduce((sum, count) => sum + count, 0) === fieldSize - 1;
}

type FormationTemplate = {
  name: string;
  baseFormation: string;
  positions: Array<{
    positionCode: string;
    x: number;
    y: number;
    isGoalkeeper: boolean;
    sortOrder: number;
  }>;
};

function formationTemplates(
  value: unknown,
  fieldSize: number,
): FormationTemplate[] | null {
  if (!Array.isArray(value) || value.length > 20) return null;
  const result: FormationTemplate[] = [];
  const names = new Set<string>();
  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
    const input = item as Record<string, unknown>;
    const name = optionalText(input.name, 50);
    const baseFormation = optionalText(input.baseFormation, 30);
    const positions = Array.isArray(input.positions) ? input.positions : [];
    if (!name || !baseFormation || names.has(name) ||
        baseFormationOf(name) !== baseFormation ||
        !validFormation(baseFormation, fieldSize) ||
        positions.length !== fieldSize) {
      return null;
    }
    const normalizedPositions: FormationTemplate['positions'] = [];
    for (var index = 0; index < positions.length; index += 1) {
      const position = positions[index];
      if (!position || typeof position !== 'object' || Array.isArray(position)) {
        return null;
      }
      const raw = position as Record<string, unknown>;
      const positionCode = optionalText(raw.positionCode, 30);
      const x = Number(raw.x);
      const y = Number(raw.y);
      if (!positionCode || !Number.isFinite(x) || !Number.isFinite(y) ||
          x < 0 || x > 1 || y < 0 || y > 1) {
        return null;
      }
      normalizedPositions.push({
        positionCode,
        x,
        y,
        isGoalkeeper: raw.isGoalkeeper === true,
        sortOrder: index,
      });
    }
    names.add(name);
    result.push({ name, baseFormation, positions: normalizedPositions });
  }
  return result;
}

function builtInFormations(gameFormat: TeamGameFormat) {
  switch (gameFormat) {
    case TeamGameFormat.FOOTBALL_3:
      return ['1-1', '2-0', '1-1-0'];
    case TeamGameFormat.FOOTBALL_4:
      return ['1-2', '2-1', '1-1-1'];
    case TeamGameFormat.FOOTBALL_5:
      return ['1-2-1', '2-2', '1-1-2'];
    case TeamGameFormat.FOOTBALL_7:
      return ['2-3-1', '3-2-1', '3-3'];
    case TeamGameFormat.FOOTBALL_9:
      return ['3-3-2', '3-4-1', '4-3-1'];
    case TeamGameFormat.FOOTBALL_11:
      return ['4-4-2', '4-3-3', '3-5-2'];
  }
}

function stringList(value: unknown, maxItems: number, maxLength: number) {
  if (!Array.isArray(value)) return [];
  return [...new Set(
    value
      .map((item) => optionalText(item, maxLength))
      .filter((item): item is string => item !== null),
  )].slice(0, maxItems);
}

function birthYears(value: unknown) {
  const currentYear = new Date().getFullYear();
  if (!Array.isArray(value)) return [];
  return [...new Set(
    value
      .map(Number)
      .filter((year) => Number.isInteger(year) && year >= currentYear - 25 && year <= currentYear),
  )].sort((a, b) => b - a).slice(0, 8);
}

function validUrl(value: unknown) {
  const text = optionalText(value, 500);
  if (!text) return null;
  try {
    const url = new URL(text);
    return ['https:', 'http:'].includes(url.protocol) ? url.toString() : null;
  } catch {
    return null;
  }
}

function optionalDate(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizedTeamData(body: TeamInput) {
  const parsedTeamNumber = Number(body.teamNumber);
  const parsedPeriodCount = Number(body.periodCount);
  const parsedPeriodMinutes = Number(body.periodMinutes);
  return {
    teamNumber:
      Number.isInteger(parsedTeamNumber) &&
      parsedTeamNumber >= 1 &&
      parsedTeamNumber <= 5
        ? parsedTeamNumber
        : null,
    name: optionalText(body.name, 120),
    shortName: optionalText(body.shortName, 40),
    level: optionalText(body.level, 80),
    teamType: Object.values(TeamType).includes(body.teamType as TeamType)
      ? body.teamType!
      : TeamType.COMPETITIVE,
    gender: Object.values(TeamGender).includes(body.gender as TeamGender)
      ? body.gender!
      : TeamGender.MIXED,
    gameFormat: Object.values(TeamGameFormat).includes(
      body.gameFormat as TeamGameFormat,
    )
      ? body.gameFormat!
      : TeamGameFormat.FOOTBALL_7,
    periodCount:
      Number.isInteger(parsedPeriodCount) &&
      parsedPeriodCount >= 1 &&
      parsedPeriodCount <= 8
        ? parsedPeriodCount
        : 2,
    periodMinutes:
      Number.isInteger(parsedPeriodMinutes) &&
      parsedPeriodMinutes >= 1 &&
      parsedPeriodMinutes <= 90
        ? parsedPeriodMinutes
        : 30,
    birthYears: birthYears(body.birthYears),
    description: optionalText(body.description, 1500),
    trainingLocation: optionalText(body.trainingLocation, 200),
    trainingTimes: stringList(body.trainingTimes, 14, 100),
    seasonStartDate: optionalDate(body.seasonStartDate),
    seasonEndDate: optionalDate(body.seasonEndDate),
    indoorSeasonStartDate: optionalDate(body.indoorSeasonStartDate),
    indoorSeasonEndDate: optionalDate(body.indoorSeasonEndDate),
    indoorTrainingLocation:
      body.indoorSeasonStartDate ||
      (Array.isArray(body.indoorTrainingTimes) &&
        body.indoorTrainingTimes.length > 0)
        ? 'Sporthalle'
        : null,
    indoorTrainingTimes: stringList(body.indoorTrainingTimes, 14, 100),
    homeVenue: optionalText(body.homeVenue, 200),
    bfvTeamId: optionalText(body.bfvTeamId, 120),
    dfbnetTeamId: optionalText(body.dfbnetTeamId, 120),
    bfvTeamUrl: validUrl(body.bfvTeamUrl),
    isActive: body.isActive !== false,
  };
}

function scheduleDateError(data: ReturnType<typeof normalizedTeamData>) {
  if (data.periodCount * data.periodMinutes > 180) {
    return 'Die gesamte Spielzeit darf 180 Minuten nicht überschreiten.';
  }
  if (data.seasonStartDate && data.seasonEndDate &&
      data.seasonStartDate > data.seasonEndDate) {
    return 'Der Saisonanfang muss vor dem Saisonende liegen.';
  }
  if ((data.indoorSeasonStartDate === null) !==
      (data.indoorSeasonEndDate === null)) {
    return 'Für die Hallensaison müssen Anfang und Ende angegeben werden.';
  }
  if (data.indoorSeasonStartDate && data.indoorSeasonEndDate &&
      data.indoorSeasonStartDate > data.indoorSeasonEndDate) {
    return 'Der Anfang der Hallensaison muss vor ihrem Ende liegen.';
  }
  return null;
}

function teamTimingError(body: TeamInput) {
  const periodCount = Number(body.periodCount ?? 2);
  const periodMinutes = Number(body.periodMinutes ?? 30);
  if (
    !Number.isInteger(periodCount) ||
    periodCount < 1 ||
    periodCount > 8 ||
    !Number.isInteger(periodMinutes) ||
    periodMinutes < 1 ||
    periodMinutes > 90 ||
    periodCount * periodMinutes > 180
  ) {
    return 'Bitte 1–8 Spielabschnitte und 1–90 Minuten je Abschnitt angeben (maximal 180 Minuten insgesamt).';
  }
  return null;
}

export function teamDisplayName(
  ageGroupCode: string,
  teamNumber: number,
  teamCount: number,
) {
  const code = ageGroupCode.trim().toUpperCase();
  return teamCount <= 1 && teamNumber === 1
    ? `${code}-Jugend`
    : `${code}${teamNumber}-Jugend`;
}

function compactTeamName(ageGroupCode: string, teamNumber: number) {
  return `${ageGroupCode.trim().toUpperCase()}${teamNumber}`;
}

export async function publicOrganization(_req: Request, res: Response) {
  const seasons = await prisma.season.findMany({
    where: { isActive: true },
    orderBy: { startDate: 'desc' },
    include: {
      club: true,
      ageGroups: {
        orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
        include: {
          teams: {
            where: { isActive: true, deletedAt: null },
            orderBy: { teamNumber: 'asc' },
            select: {
              id: true,
              name: true,
              shortName: true,
              level: true,
              teamNumber: true,
            },
          },
        },
      },
    },
  });
  return res.json(seasons.map((season) => ({
    club: {
      id: season.club.id,
      name: season.club.name,
      shortName: season.club.shortName,
      primaryColor: season.club.primaryColor,
      accentColor: season.club.accentColor,
    },
    season: {
      id: season.id,
      name: season.name,
      startDate: season.startDate,
      endDate: season.endDate,
    },
    ageGroups: season.ageGroups.map((ageGroup) => ({
      ...ageGroup,
      teams: ageGroup.teams.map((team) => ({
        ...team,
        displayName: teamDisplayName(
          ageGroup.code,
          team.teamNumber,
          ageGroup.teams.length,
        ),
      })),
    })),
  })));
}

export async function organizationContext(req: Request, res: Response) {
  const user = req.user!;
  const contextTeamId = await resolveContextTeamId(user);
  if (!contextTeamId) {
    return res.status(404).json({ message: 'Keine aktive Mannschaft gefunden.' });
  }
  const currentTeam = await prisma.team.findUnique({
    where: { id: contextTeamId },
    include: hierarchyInclude,
  });
  if (!currentTeam) return res.status(404).json({ message: 'Aktive Mannschaft nicht gefunden.' });

  const clubId = currentTeam.ageGroup.season.clubId;
  const permissions = permissionsForRole(user.role);
  const canViewAllTeams = permissions.includes(Permission.MANAGE_ORGANIZATION);
  const visibleTeamIds = await accessibleTeamIds(user);
  const seasonScope =
    user.role === Role.SUPER_ADMIN
      ? { isActive: true }
      : { clubId, isActive: true };
  const memberships = canViewAllTeams ? [] : await prisma.teamMembership.findMany({
    where: { userId: user.id, status: AccountStatus.APPROVED },
    select: { teamId: true },
  });
  const membershipTeamIds = memberships.map((membership) => membership.teamId);
  const [ageGroups, teams, players, members, upcomingEvents, pendingApprovals] = await Promise.all([
    prisma.ageGroup.findMany({
      where: { season: seasonScope },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
      select: { id: true, name: true, code: true, sortOrder: true },
    }),
    prisma.team.findMany({
      where: {
        ageGroup: { season: seasonScope },
        deletedAt: null,
        ...(canViewAllTeams ? {} : {
          id: { in: membershipTeamIds.length > 0 ? membershipTeamIds : [contextTeamId] },
        }),
      },
      orderBy: [
        { isActive: 'desc' },
        { ageGroup: { sortOrder: 'asc' } },
        { teamNumber: 'asc' },
      ],
      include: hierarchyInclude,
    }),
    prisma.player.count({
      where: user.role === Role.SUPER_ADMIN ? {} : { clubId },
    }),
    prisma.user.count({
      where: {
        status: AccountStatus.APPROVED,
        ...(user.role === Role.SUPER_ADMIN
          ? {}
          : { OR: [
              { teamId: { in: visibleTeamIds } },
              { memberships: { some: { teamId: { in: visibleTeamIds } } } },
            ] }),
      },
    }),
    prisma.event.count({
      where: {
        startAt: { gte: new Date() },
        OR: [
          { teamId: { in: visibleTeamIds } },
          { targetTeams: { some: { teamId: { in: visibleTeamIds } } } },
        ],
      },
    }),
    permissions.includes(Permission.MANAGE_MEMBERS)
      ? prisma.user.count({
          where: {
            status: AccountStatus.PENDING,
            ...(user.role === Role.SUPER_ADMIN
              ? {}
              : { OR: [
                  { teamId: { in: visibleTeamIds } },
                  { memberships: { some: { teamId: { in: visibleTeamIds } } } },
                ] }),
          },
        })
      : Promise.resolve(0),
  ]);
  const groupedTeamCounts = await prisma.team.groupBy({
    by: ['ageGroupId'],
    where: { ageGroup: { season: seasonScope }, deletedAt: null },
    _count: { _all: true },
  });
  const teamCountByAgeGroup = new Map(
    groupedTeamCounts.map((item) => [item.ageGroupId, item._count._all]),
  );
  const serializedTeams = await Promise.all(
    teams.map((team) => serializeTeam(
      team,
      canViewAllTeams || team.id === contextTeamId,
      teamCountByAgeGroup.get(team.ageGroupId),
    )),
  );
  const serializedCurrent = serializedTeams.find((team) => team.id === currentTeam.id)
    ?? await serializeTeam(
      currentTeam,
      true,
      teamCountByAgeGroup.get(currentTeam.ageGroupId),
    );
  return res.json({
    club: currentTeam.ageGroup.season.club,
    season: {
      id: currentTeam.ageGroup.season.id,
      name: currentTeam.ageGroup.season.name,
      startDate: currentTeam.ageGroup.season.startDate,
      endDate: currentTeam.ageGroup.season.endDate,
      isActive: currentTeam.ageGroup.season.isActive,
    },
    currentTeam: serializedCurrent,
    ageGroups,
    teams: serializedTeams,
    permissions,
    metrics: { players, members, upcomingEvents, pendingApprovals },
  });
}

export async function createTeam(req: Request, res: Response) {
  const user = req.user!;
  const body = req.body as TeamInput;
  const data = normalizedTeamData(body);
  const timingError = teamTimingError(body);
  if (timingError) return res.status(400).json({ message: timingError });
  const dateError = scheduleDateError(data);
  if (dateError) return res.status(400).json({ message: dateError });
  if (!body.ageGroupId) {
    return res.status(400).json({ message: 'Eine Jugend muss ausgewählt werden.' });
  }
  if (body.teamNumber !== undefined && data.teamNumber === null) {
    return res.status(400).json({
      message: 'Die Mannschaftsnummer muss zwischen 1 und 5 liegen.',
    });
  }
  if (body.bfvTeamUrl && !data.bfvTeamUrl) {
    return res.status(400).json({ message: 'Die BFV-Adresse ist ungültig.' });
  }
  const contextTeamId = await resolveContextTeamId(user);
  if (!contextTeamId) {
    return res.status(404).json({ message: 'Keine aktive Mannschaft gefunden.' });
  }
  const currentTeam = await prisma.team.findUnique({
    where: { id: contextTeamId },
    include: hierarchyInclude,
  });
  if (!currentTeam) return res.status(404).json({ message: 'Aktive Mannschaft nicht gefunden.' });
  const ageGroup = await prisma.ageGroup.findFirst({
    where: {
      id: body.ageGroupId,
      season: user.role === Role.SUPER_ADMIN
        ? { isActive: true }
        : { clubId: currentTeam.ageGroup.season.clubId, isActive: true },
    },
  });
  if (!ageGroup) return res.status(404).json({ message: 'Altersklasse nicht gefunden.' });
  const existingNumbers = await prisma.team.findMany({
    where: { ageGroupId: body.ageGroupId, deletedAt: null },
    select: { teamNumber: true },
  });
  const usedNumbers = new Set(existingNumbers.map((team) => team.teamNumber));
  const teamNumber = data.teamNumber
    ?? Array.from({ length: 5 }, (_, index) => index + 1)
      .find((number) => !usedNumbers.has(number));
  if (!teamNumber) {
    return res.status(409).json({
      message: 'Für diese Jugend sind bereits fünf Mannschaften angelegt.',
    });
  }
  const teamName = compactTeamName(ageGroup.code, teamNumber);
  const duplicate = await prisma.team.findFirst({
    where: { ageGroupId: body.ageGroupId, teamNumber, deletedAt: null },
  });
  if (duplicate) {
    return res.status(409).json({
      message: `${ageGroup.code}${teamNumber}-Jugend existiert bereits.`,
    });
  }
  const {
    teamNumber: _requestedTeamNumber,
    name: _name,
    shortName: _shortName,
    ...profileData
  } = data;
  const team = await prisma.$transaction(async (tx) => {
    const created = await tx.team.create({
      data: {
        ...profileData,
        name: teamName,
        ageGroupId: body.ageGroupId!,
        teamNumber,
        shortName: teamName,
      },
      include: hierarchyInclude,
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: created.id,
        action: 'TEAM_CREATED',
        entityType: 'Team',
        entityId: created.id,
        metadata: {
          name: created.name,
          teamNumber,
          ageGroupId: body.ageGroupId,
        },
      },
    });
    return created;
  });
  return res.status(201).json(await serializeTeam(team, true));
}

export async function updateTeam(req: Request, res: Response) {
  const user = req.user!;
  const teamId = req.params.id;
  if (!(await canManageTeam(user, teamId))) {
    return res.status(403).json({ message: 'Diese Mannschaft darf nicht bearbeitet werden.' });
  }
  const body = req.body as TeamInput;
  const data = normalizedTeamData(body);
  const timingError = teamTimingError(body);
  if (timingError) return res.status(400).json({ message: timingError });
  const dateError = scheduleDateError(data);
  if (dateError) return res.status(400).json({ message: dateError });
  if (body.teamNumber !== undefined && data.teamNumber === null) {
    return res.status(400).json({
      message: 'Die Mannschaftsnummer muss zwischen 1 und 5 liegen.',
    });
  }
  if (body.bfvTeamUrl && !data.bfvTeamUrl) {
    return res.status(400).json({ message: 'Die BFV-Adresse ist ungültig.' });
  }
  const existing = await prisma.team.findUnique({ where: { id: teamId }, include: hierarchyInclude });
  if (!existing || existing.deletedAt) {
    return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  }
  const teamNumber = data.teamNumber ?? existing.teamNumber;
  const teamName = compactTeamName(existing.ageGroup.code, teamNumber);
  const duplicate = await prisma.team.findFirst({
    where: {
      ageGroupId: existing.ageGroupId,
      id: { not: teamId },
      teamNumber,
      deletedAt: null,
    },
  });
  if (duplicate) {
    return res.status(409).json({
      message: `${existing.ageGroup.code}${teamNumber}-Jugend existiert bereits.`,
    });
  }
  const {
    teamNumber: _requestedTeamNumber,
    name: _name,
    shortName: _shortName,
    ...profileData
  } = data;
  const team = await prisma.$transaction(async (tx) => {
    const updated = await tx.team.update({
      where: { id: teamId },
      data: {
        ...profileData,
        teamNumber,
        name: teamName,
        shortName: teamName,
      },
      include: hierarchyInclude,
    });
    if (data.seasonEndDate) {
      const inclusiveSeasonEnd = new Date(data.seasonEndDate);
      inclusiveSeasonEnd.setUTCHours(23, 59, 59, 999);
      await tx.eventSeries.updateMany({
        where: {
          teamId,
          until: { gt: inclusiveSeasonEnd },
        },
        data: { until: inclusiveSeasonEnd },
      });
      await tx.event.deleteMany({
        where: {
          teamId,
          type: EventType.TRAINING,
          seriesId: { not: null },
          startAt: { gt: inclusiveSeasonEnd },
        },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'TEAM_UPDATED',
        entityType: 'Team',
        entityId: teamId,
        metadata: { before: teamSnapshot(existing), after: teamSnapshot(updated) },
      },
    });
    return updated;
  });
  return res.json(await serializeTeam(team, true));
}

export async function updateTeamDefaultLineup(req: Request, res: Response) {
  const user = req.user!;
  const teamId = req.params.id;
  if (!(await canManageFormation(user, teamId))) {
    return res.status(403).json({
      message: 'Die Stammformation dieser Mannschaft darf nicht bearbeitet werden.',
    });
  }
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: {
      id: true,
      gameFormat: true,
      customFormations: true,
      formationTemplates: true,
      deletedAt: true,
    },
  });
  if (!team || team.deletedAt) {
    return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  }

  const formation = optionalText(req.body?.formation, 50);
  const positions = Array.isArray(req.body?.positions)
    ? req.body.positions as Record<string, unknown>[]
    : [];
  const fieldSize = fieldSizeForGameFormat(team.gameFormat);
  if (positions.length > fieldSize) {
    return res.status(400).json({
      message: `Für diese Mannschaft sind höchstens ${fieldSize} Startspieler vorgesehen.`,
    });
  }
  if (positions.length > 0 && !formation) {
    return res.status(400).json({ message: 'Bitte eine Formation auswählen.' });
  }
  if (formation && !validFormation(formation, fieldSize)) {
    return res.status(400).json({
      message: `Die Formation muss ${fieldSize - 1} Feldspieler enthalten.`,
    });
  }
  const standardFormations = new Set(builtInFormations(team.gameFormat));
  const requestedCustomFormations: string[] = Array.isArray(
    req.body?.customFormations,
  )
    ? req.body.customFormations
      .map((value: unknown) => optionalText(value, 30))
      .filter((value: string | null): value is string => value !== null)
    : team.customFormations;
  const customFormations = [...new Set([
    ...requestedCustomFormations.filter(
      (value) => !standardFormations.has(value),
    ),
    ...(formation && !standardFormations.has(formation) ? [formation] : []),
  ])];
  if (customFormations.length > 12 ||
      customFormations.some((value) => !validFormation(value, fieldSize))) {
    return res.status(400).json({
      message: 'Bitte höchstens 12 gültige eigene Formationen speichern.',
    });
  }
  const normalizedFormationTemplates = formationTemplates(
    req.body?.formationTemplates === undefined
      ? team.formationTemplates
      : req.body.formationTemplates,
    fieldSize,
  );
  const allowedFormationNames = new Set([
    ...standardFormations,
    ...customFormations,
  ]);
  if (!normalizedFormationTemplates ||
      normalizedFormationTemplates.some(
        (template) => !allowedFormationNames.has(template.name),
      )) {
    return res.status(400).json({
      message: 'Die dauerhaft gespeicherten Formationsvarianten sind ungültig.',
    });
  }
  const playerIds = positions.map((position) => String(position.playerId ?? ''));
  if (playerIds.some((id) => !id) || new Set(playerIds).size !== playerIds.length) {
    return res.status(400).json({
      message: 'Jeder Spieler darf nur einmal in der Stammformation vorkommen.',
    });
  }
  if (positions.filter((position) => position.isCaptain === true).length > 1) {
    return res.status(400).json({ message: 'Es kann nur einen Kapitän geben.' });
  }
  for (const position of positions) {
    const x = Number(position.x);
    const y = Number(position.y);
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
      return res.status(400).json({ message: 'Ungültige Spielfeldposition.' });
    }
  }
  const validPlayers = await prisma.player.findMany({
    where: {
      id: { in: playerIds },
      teamId,
      status: { in: [PlayerStatus.ACTIVE, PlayerStatus.INJURED] },
    },
    select: { id: true },
  });
  if (validPlayers.length !== playerIds.length) {
    return res.status(400).json({
      message: 'Die Stammformation darf nur Spieler dieser Mannschaft enthalten.',
    });
  }

  const saved = await prisma.$transaction(async (tx) => {
    await tx.team.update({
      where: { id: teamId },
      data: {
        defaultFormation: positions.length > 0 ? formation : null,
        customFormations,
        formationTemplates: normalizedFormationTemplates,
      },
    });
    await tx.teamDefaultLineupPosition.deleteMany({ where: { teamId } });
    if (positions.length > 0) {
      await tx.teamDefaultLineupPosition.createMany({
        data: positions.map((position, index) => ({
          teamId,
          playerId: String(position.playerId),
          positionCode: optionalText(position.positionCode, 30) ?? 'FELD',
          x: Number(position.x),
          y: Number(position.y),
          isGoalkeeper: position.isGoalkeeper === true,
          isCaptain: position.isCaptain === true,
          sortOrder: index,
        })),
      });
    }

    const futureSquads = await tx.squad.findMany({
      where: {
        event: {
          type: EventType.MATCH,
          startAt: { gte: new Date() },
          OR: [
            { teamId },
            { targetTeams: { some: { teamId } } },
          ],
        },
      },
      select: { id: true },
    });
    for (const squad of futureSquads) {
      await syncSquadWithTeamDefaultLineup(tx, {
        teamId,
        squadId: squad.id,
        fieldSize,
        force: true,
      });
    }

    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'TEAM_DEFAULT_LINEUP_UPDATED',
        entityType: 'Team',
        entityId: teamId,
        metadata: {
          formation,
          playerCount: positions.length,
          synchronizedMatches: futureSquads.length,
        },
      },
    });
    return tx.team.findUnique({
      where: { id: teamId },
      select: {
        defaultFormation: true,
        customFormations: true,
        formationTemplates: true,
        defaultLineupPositions: {
          orderBy: { sortOrder: 'asc' },
          include: {
            player: {
              select: {
                id: true,
                firstName: true,
                lastName: true,
                preferredName: true,
                position: true,
                secondaryPosition: true,
                shirtNumber: true,
                status: true,
              },
            },
          },
        },
      },
    });
  });

  return res.json(saved && saved.defaultLineupPositions.length > 0
    ? {
        formation: saved.defaultFormation ?? 'Individuell',
        customFormations: saved.customFormations,
        formationTemplates: saved.formationTemplates,
        positions: saved.defaultLineupPositions,
      }
    : null);
}

export function canDeleteTeamRole(role: Role) {
  return role === Role.SUPER_ADMIN;
}

export async function deleteTeam(req: Request, res: Response) {
  const user = req.user!;
  if (!canDeleteTeamRole(user.role)) {
    return res.status(403).json({
      message: 'Nur die Systemadministration darf Mannschaften löschen.',
    });
  }

  const team = await prisma.team.findFirst({
    where: { id: req.params.id, deletedAt: null },
    include: {
      ageGroup: {
        include: { season: true },
      },
      _count: {
        select: { players: true, users: true },
      },
    },
  });
  if (!team) {
    return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  }

  const fallbackTeam = await prisma.team.findFirst({
    where: {
      id: { not: team.id },
      isActive: true,
      deletedAt: null,
      ageGroup: { season: { clubId: team.ageGroup.season.clubId } },
    },
    orderBy: [
      { ageGroup: { sortOrder: 'asc' } },
      { teamNumber: 'asc' },
    ],
    select: { id: true, name: true },
  });
  const deletedAt = new Date();

  await prisma.$transaction(async (tx) => {
    await tx.player.updateMany({
      where: { teamId: team.id },
      data: { teamId: null },
    });
    if (fallbackTeam) {
      await tx.user.updateMany({
        where: { teamId: team.id },
        data: { teamId: fallbackTeam.id },
      });
    }
    await tx.team.update({
      where: { id: team.id },
      data: { isActive: false, deletedAt },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: team.id,
        action: 'TEAM_DELETED',
        entityType: 'Team',
        entityId: team.id,
        metadata: {
          name: team.name,
          ageGroupId: team.ageGroupId,
          unassignedPlayerCount: team._count.players,
          reassignedUserCount: fallbackTeam ? team._count.users : 0,
          fallbackTeamId: fallbackTeam?.id ?? null,
          deletedAt: deletedAt.toISOString(),
        },
      },
    });
  });

  return res.json({
    deleted: true,
    unassignedPlayerCount: team._count.players,
    reassignedUserCount: fallbackTeam ? team._count.users : 0,
    fallbackTeam,
  });
}

export async function updateTrainingSchedule(req: Request, res: Response) {
  const user = req.user!;
  const teamId = req.params.id;
  if (!(await canManageTeam(user, teamId))) {
    return res.status(403).json({
      message: 'Die Trainingszeiten dieser Mannschaft dürfen nicht bearbeitet werden.',
    });
  }
  const trainingLocation = optionalText(req.body.trainingLocation, 200);
  const trainingTimes = stringList(req.body.trainingTimes, 14, 100);
  const matchdayTimes = stringList(req.body.matchdayTimes, 14, 100);
  const requestedPartnerIds = stringList(req.body.trainingPartnerIds, 12, 100)
    .filter((id) => id !== teamId);
  const team = await prisma.$transaction(async (tx) => {
    const existing = await tx.team.findUnique({
      where: { id: teamId },
      include: hierarchyInclude,
    });
    if (!existing) return null;
    const validPartners = requestedPartnerIds.length === 0
      ? []
      : await tx.team.findMany({
          where: {
            id: { in: requestedPartnerIds },
            ageGroup: { seasonId: existing.ageGroup.season.id },
            isActive: true,
            deletedAt: null,
          },
          select: { id: true },
        });
    const trainingPartnerIds = validPartners.map((partner) => partner.id);
    const partnerTeams = await tx.team.findMany({
      where: {
        id: {
          in: [
            ...new Set([
              ...existing.trainingPartnerIds,
              ...trainingPartnerIds,
            ]),
          ],
        },
        ageGroup: { seasonId: existing.ageGroup.season.id },
        deletedAt: null,
      },
      select: { id: true, trainingPartnerIds: true },
    });
    for (const partner of partnerTeams) {
      const reciprocalIds = new Set(partner.trainingPartnerIds);
      if (trainingPartnerIds.includes(partner.id)) reciprocalIds.add(teamId);
      else reciprocalIds.delete(teamId);
      await tx.team.update({
        where: { id: partner.id },
        data: { trainingPartnerIds: [...reciprocalIds] },
      });
    }
    const updated = await tx.team.update({
      where: { id: teamId },
      data: {
        trainingLocation,
        trainingTimes,
        trainingPartnerIds,
        matchdayTimes,
      },
      include: hierarchyInclude,
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'TEAM_TRAINING_SCHEDULE_UPDATED',
        entityType: 'Team',
        entityId: teamId,
        metadata: {
          before: {
            trainingLocation: existing.trainingLocation,
            trainingTimes: existing.trainingTimes,
            trainingPartnerIds: existing.trainingPartnerIds,
            matchdayTimes: existing.matchdayTimes,
          },
          after: {
            trainingLocation,
            trainingTimes,
            trainingPartnerIds,
            matchdayTimes,
          },
        },
      },
    });
    return updated;
  });
  if (!team) return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  return res.json(await serializeTeam(team, true));
}

export async function uploadTeamPhoto(req: Request, res: Response) {
  const user = req.user!;
  const teamId = req.params.id;
  if (!(await canManageTeam(user, teamId))) {
    return res.status(403).json({ message: 'Das Mannschaftsfoto darf nicht geändert werden.' });
  }
  if (!req.file || !imageTypes.has(req.file.mimetype)) {
    return res.status(400).json({ message: 'Bitte ein JPEG-, PNG- oder WebP-Bild auswählen.' });
  }
  const extension = req.file.mimetype === 'image/png' ? 'png'
    : req.file.mimetype === 'image/webp' ? 'webp' : 'jpg';
  const stored = await objectStorage.uploadPrivate(
    `teams/${teamId}/photos/${randomUUID()}.${extension}`,
    req.file.buffer,
    req.file.mimetype,
  );
  let previousPathname: string | null = null;
  const team = await prisma.$transaction(async (tx) => {
    const existing = await tx.team.findUnique({ where: { id: teamId }, include: { photoAsset: true } });
    if (!existing) throw new Error('Mannschaft nicht gefunden.');
    previousPathname = existing.photoAsset?.pathname ?? null;
    const asset = await tx.fileAsset.create({
      data: {
        kind: 'TEAM_PHOTO',
        pathname: stored.pathname,
        storageUrl: stored.url,
        originalName: req.file!.originalname,
        contentType: req.file!.mimetype,
        size: req.file!.size,
        checksum: createHash('sha256').update(req.file!.buffer).digest('hex'),
        uploadedById: user.id,
        ownerTeamId: teamId,
      },
    });
    const updated = await tx.team.update({
      where: { id: teamId },
      data: { photoAssetId: asset.id },
      include: hierarchyInclude,
    });
    if (existing.photoAsset) {
      await tx.fileAsset.update({
        where: { id: existing.photoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'TEAM_PHOTO_REPLACED',
        entityType: 'FileAsset',
        entityId: asset.id,
        metadata: { previousAssetId: existing.photoAssetId, size: asset.size },
      },
    });
    return updated;
  });
  if (previousPathname) objectStorage.delete(previousPathname).catch(() => undefined);
  return res.status(201).json(await serializeTeam(team, true));
}

export async function removeTeamPhoto(req: Request, res: Response) {
  const user = req.user!;
  const teamId = req.params.id;
  if (!(await canManageTeam(user, teamId))) {
    return res.status(403).json({ message: 'Das Mannschaftsfoto darf nicht entfernt werden.' });
  }
  const pathname = await prisma.$transaction(async (tx) => {
    const team = await tx.team.findUnique({ where: { id: teamId }, include: { photoAsset: true } });
    if (!team) return null;
    await tx.team.update({ where: { id: teamId }, data: { photoAssetId: null } });
    if (team.photoAsset) {
      await tx.fileAsset.update({ where: { id: team.photoAsset.id }, data: { deletedAt: new Date() } });
    }
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'TEAM_PHOTO_REMOVED',
        entityType: 'Team',
        entityId: teamId,
      },
    });
    return team.photoAsset?.pathname ?? null;
  });
  if (pathname) objectStorage.delete(pathname).catch(() => undefined);
  return res.status(204).send();
}

function teamSnapshot(team: ReturnType<typeof normalizedTeamData> & { ageGroupId?: string }) {
  return {
    teamNumber: team.teamNumber,
    name: team.name,
    shortName: team.shortName,
    level: team.level,
    teamType: team.teamType,
    gender: team.gender,
    gameFormat: team.gameFormat,
    periodCount: team.periodCount,
    periodMinutes: team.periodMinutes,
    birthYears: team.birthYears,
    trainingLocation: team.trainingLocation,
    trainingTimes: team.trainingTimes,
    seasonStartDate: team.seasonStartDate,
    seasonEndDate: team.seasonEndDate,
    indoorSeasonStartDate: team.indoorSeasonStartDate,
    indoorSeasonEndDate: team.indoorSeasonEndDate,
    indoorTrainingLocation: team.indoorTrainingLocation,
    indoorTrainingTimes: team.indoorTrainingTimes,
    homeVenue: team.homeVenue,
    bfvTeamId: team.bfvTeamId,
    dfbnetTeamId: team.dfbnetTeamId,
    bfvTeamUrl: team.bfvTeamUrl,
    isActive: team.isActive,
  };
}

async function serializeTeam(team: {
  id: string;
  ageGroupId: string;
  teamNumber: number;
  name: string;
  shortName: string | null;
  level: string | null;
  teamType: TeamType;
  gender: TeamGender;
  gameFormat: TeamGameFormat;
  periodCount: number;
  periodMinutes: number;
  defaultFormation: string | null;
  customFormations: string[];
  formationTemplates: Prisma.JsonValue;
  birthYears: number[];
  description: string | null;
  trainingLocation: string | null;
  trainingTimes: string[];
  trainingPartnerIds: string[];
  matchdayTimes: string[];
  seasonStartDate: Date | null;
  seasonEndDate: Date | null;
  indoorSeasonStartDate: Date | null;
  indoorSeasonEndDate: Date | null;
  indoorTrainingLocation: string | null;
  indoorTrainingTimes: string[];
  indoorTrainingPartnerIds: string[];
  homeVenue: string | null;
  bfvTeamId: string | null;
  dfbnetTeamId: string | null;
  bfvTeamUrl: string | null;
  isActive: boolean;
  photoAsset: { id: string; pathname: string } | null;
  memberships: Array<{
    role: Role;
    user: { id: string; name: string; email: string };
  }>;
  defaultLineupPositions: Array<{
    playerId: string;
    positionCode: string;
    x: number;
    y: number;
    isGoalkeeper: boolean;
    isCaptain: boolean;
    sortOrder: number;
    player: {
      id: string;
      firstName: string;
      lastName: string;
      preferredName: string | null;
      position: string | null;
      secondaryPosition: string | null;
      shirtNumber: number | null;
      status: PlayerStatus;
    };
  }>;
  ageGroup: {
    id: string;
    name: string;
    code: string;
    season: { id: string; name: string };
  };
}, includePrivate: boolean, ageGroupTeamCount?: number) {
  const teamCount = ageGroupTeamCount ?? await prisma.team.count({
    where: { ageGroupId: team.ageGroupId, deletedAt: null },
  });
  return {
    id: team.id,
    teamNumber: team.teamNumber,
    name: team.name,
    shortName: team.shortName,
    displayName: teamDisplayName(
      team.ageGroup.code,
      team.teamNumber,
      teamCount,
    ),
    level: team.level,
    teamType: team.teamType,
    gender: team.gender,
    gameFormat: team.gameFormat,
    periodCount: team.periodCount,
    periodMinutes: team.periodMinutes,
    defaultLineup: team.defaultLineupPositions.length > 0
      ? {
          formation: team.defaultFormation ?? 'Individuell',
          positions: team.defaultLineupPositions,
        }
      : null,
    customFormations: team.customFormations,
    formationTemplates: team.formationTemplates,
    birthYears: team.birthYears,
    description: team.description,
    trainingLocation: team.trainingLocation,
    trainingTimes: team.trainingTimes,
    trainingPartnerIds: team.trainingPartnerIds,
    matchdayTimes: team.matchdayTimes,
    seasonStartDate: team.seasonStartDate,
    seasonEndDate: team.seasonEndDate,
    indoorSeasonStartDate: team.indoorSeasonStartDate,
    indoorSeasonEndDate: team.indoorSeasonEndDate,
    indoorTrainingLocation: team.indoorTrainingLocation,
    indoorTrainingTimes: team.indoorTrainingTimes,
    indoorTrainingPartnerIds: team.indoorTrainingPartnerIds,
    homeVenue: team.homeVenue,
    bfvTeamId: team.bfvTeamId,
    dfbnetTeamId: team.dfbnetTeamId,
    bfvTeamUrl: team.bfvTeamUrl,
    isActive: team.isActive,
    photoUrl: includePrivate && team.photoAsset
      ? mediaAssetUrl(team.photoAsset.id)
      : null,
    staff: team.memberships.map((membership) => ({
      id: membership.user.id,
      name: membership.user.name,
      email: includePrivate ? membership.user.email : null,
      role: membership.role,
    })),
    ageGroup: {
      id: team.ageGroup.id,
      name: team.ageGroup.name,
      code: team.ageGroup.code,
    },
    season: {
      id: team.ageGroup.season.id,
      name: team.ageGroup.season.name,
    },
  };
}
