import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import {
  AccountStatus,
  Role,
  TeamGameFormat,
  TeamGender,
  TeamType,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Permission, permissionsForRole } from '../security/permissions';
import { accessibleTeamIds, canManageTeam } from '../services/team-access';
import { objectStorage } from '../services/object-storage';
import { mediaAssetUrl } from '../services/media-access';

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
  birthYears?: unknown;
  description?: string | null;
  trainingLocation?: string | null;
  trainingTimes?: unknown;
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

function normalizedTeamData(body: TeamInput) {
  const parsedTeamNumber = Number(body.teamNumber);
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
    birthYears: birthYears(body.birthYears),
    description: optionalText(body.description, 1500),
    trainingLocation: optionalText(body.trainingLocation, 200),
    trainingTimes: stringList(body.trainingTimes, 14, 100),
    homeVenue: optionalText(body.homeVenue, 200),
    bfvTeamId: optionalText(body.bfvTeamId, 120),
    dfbnetTeamId: optionalText(body.dfbnetTeamId, 120),
    bfvTeamUrl: validUrl(body.bfvTeamUrl),
    isActive: body.isActive !== false,
  };
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
  const currentTeam = await prisma.team.findUnique({
    where: { id: user.teamId },
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
          id: { in: membershipTeamIds.length > 0 ? membershipTeamIds : [user.teamId] },
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
      canViewAllTeams || team.id === user.teamId,
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
  const currentTeam = await prisma.team.findUnique({
    where: { id: user.teamId },
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
    birthYears: team.birthYears,
    trainingLocation: team.trainingLocation,
    trainingTimes: team.trainingTimes,
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
  birthYears: number[];
  description: string | null;
  trainingLocation: string | null;
  trainingTimes: string[];
  trainingPartnerIds: string[];
  matchdayTimes: string[];
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
    birthYears: team.birthYears,
    description: team.description,
    trainingLocation: team.trainingLocation,
    trainingTimes: team.trainingTimes,
    trainingPartnerIds: team.trainingPartnerIds,
    matchdayTimes: team.matchdayTimes,
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
