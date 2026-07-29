import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import { AccountStatus, Role, TeamGender, TeamType } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Permission, permissionsForRole } from '../security/permissions';
import { canManageTeam } from '../services/team-access';
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
  name?: string;
  shortName?: string | null;
  level?: string | null;
  teamType?: TeamType;
  gender?: TeamGender;
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
  return {
    name: optionalText(body.name, 120),
    shortName: optionalText(body.shortName, 40),
    level: optionalText(body.level, 80),
    teamType: Object.values(TeamType).includes(body.teamType as TeamType)
      ? body.teamType!
      : TeamType.COMPETITIVE,
    gender: Object.values(TeamGender).includes(body.gender as TeamGender)
      ? body.gender!
      : TeamGender.MIXED,
    birthYears: birthYears(body.birthYears),
    description: optionalText(body.description, 1500),
    trainingLocation: optionalText(body.trainingLocation, 200),
    trainingTimes: stringList(body.trainingTimes, 7, 100),
    homeVenue: optionalText(body.homeVenue, 200),
    bfvTeamId: optionalText(body.bfvTeamId, 120),
    dfbnetTeamId: optionalText(body.dfbnetTeamId, 120),
    bfvTeamUrl: validUrl(body.bfvTeamUrl),
    isActive: body.isActive !== false,
  };
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
            where: { isActive: true },
            orderBy: { name: 'asc' },
            select: { id: true, name: true, shortName: true, level: true },
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
    ageGroups: season.ageGroups,
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
  const memberships = canViewAllTeams ? [] : await prisma.teamMembership.findMany({
    where: { userId: user.id, status: AccountStatus.APPROVED },
    select: { teamId: true },
  });
  const membershipTeamIds = memberships.map((membership) => membership.teamId);
  const [ageGroups, teams, players, members, upcomingEvents, pendingApprovals] = await Promise.all([
    prisma.ageGroup.findMany({
      where: { season: { clubId, isActive: true } },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
      select: { id: true, name: true, code: true, sortOrder: true },
    }),
    prisma.team.findMany({
      where: {
        ageGroup: { season: { clubId, isActive: true } },
        ...(canViewAllTeams ? {} : {
          id: { in: membershipTeamIds.length > 0 ? membershipTeamIds : [user.teamId] },
        }),
      },
      orderBy: [{ isActive: 'desc' }, { ageGroup: { sortOrder: 'asc' } }, { name: 'asc' }],
      include: hierarchyInclude,
    }),
    prisma.player.count({ where: { teamId: user.teamId } }),
    prisma.user.count({ where: { teamId: user.teamId, status: AccountStatus.APPROVED } }),
    prisma.event.count({ where: { teamId: user.teamId, startAt: { gte: new Date() } } }),
    permissions.includes(Permission.MANAGE_MEMBERS)
      ? prisma.user.count({ where: { teamId: user.teamId, status: AccountStatus.PENDING } })
      : Promise.resolve(0),
  ]);
  const serializedTeams = await Promise.all(
    teams.map((team) => serializeTeam(team, canViewAllTeams || team.id === user.teamId)),
  );
  const serializedCurrent = serializedTeams.find((team) => team.id === currentTeam.id)
    ?? await serializeTeam(currentTeam, true);
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
  if (!body.ageGroupId || !data.name) {
    return res.status(400).json({ message: 'Altersklasse und Mannschaftsname sind erforderlich.' });
  }
  const teamName = data.name;
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
      season: { clubId: currentTeam.ageGroup.season.clubId, isActive: true },
    },
  });
  if (!ageGroup) return res.status(404).json({ message: 'Altersklasse nicht gefunden.' });
  const duplicate = await prisma.team.findFirst({
    where: { ageGroupId: body.ageGroupId, name: { equals: data.name, mode: 'insensitive' } },
  });
  if (duplicate) return res.status(409).json({ message: 'Diese Mannschaft existiert bereits.' });
  const team = await prisma.$transaction(async (tx) => {
    const created = await tx.team.create({
      data: {
        ...data,
        name: teamName,
        ageGroupId: body.ageGroupId!,
        shortName: data.shortName ?? teamName,
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
        metadata: { name: created.name, ageGroupId: body.ageGroupId },
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
  if (!data.name) return res.status(400).json({ message: 'Mannschaftsname ist erforderlich.' });
  const teamName = data.name;
  if (body.bfvTeamUrl && !data.bfvTeamUrl) {
    return res.status(400).json({ message: 'Die BFV-Adresse ist ungültig.' });
  }
  const existing = await prisma.team.findUnique({ where: { id: teamId }, include: hierarchyInclude });
  if (!existing) return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  const duplicate = await prisma.team.findFirst({
    where: {
      ageGroupId: existing.ageGroupId,
      id: { not: teamId },
      name: { equals: teamName, mode: 'insensitive' },
    },
  });
  if (duplicate) return res.status(409).json({ message: 'Diese Mannschaft existiert bereits.' });
  const team = await prisma.$transaction(async (tx) => {
    const updated = await tx.team.update({
      where: { id: teamId },
      data: { ...data, name: teamName },
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
    name: team.name,
    shortName: team.shortName,
    level: team.level,
    teamType: team.teamType,
    gender: team.gender,
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
  name: string;
  shortName: string | null;
  level: string | null;
  teamType: TeamType;
  gender: TeamGender;
  birthYears: number[];
  description: string | null;
  trainingLocation: string | null;
  trainingTimes: string[];
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
}, includePrivate: boolean) {
  return {
    id: team.id,
    name: team.name,
    shortName: team.shortName,
    level: team.level,
    teamType: team.teamType,
    gender: team.gender,
    birthYears: team.birthYears,
    description: team.description,
    trainingLocation: team.trainingLocation,
    trainingTimes: team.trainingTimes,
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
