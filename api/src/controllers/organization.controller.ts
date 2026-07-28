import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { Permission, permissionsForRole } from '../security/permissions';

const hierarchyInclude = {
  ageGroup: {
    include: {
      season: {
        include: { club: true },
      },
    },
  },
} as const;

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

  return res.json(
    seasons.map((season) => ({
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
    })),
  );
}

export async function organizationContext(req: Request, res: Response) {
  const user = req.user!;
  const currentTeam = await prisma.team.findUnique({
    where: { id: user.teamId },
    include: hierarchyInclude,
  });

  if (!currentTeam) {
    return res.status(404).json({ message: 'Aktive Mannschaft nicht gefunden.' });
  }

  const clubId = currentTeam.ageGroup.season.clubId;
  const permissions = permissionsForRole(user.role);
  const canViewAllTeams = permissions.includes(Permission.MANAGE_ORGANIZATION);
  const memberships = canViewAllTeams
    ? []
    : await prisma.teamMembership.findMany({
        where: { userId: user.id, status: 'APPROVED' },
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
        isActive: true,
        ageGroup: { season: { clubId, isActive: true } },
        ...(canViewAllTeams
          ? {}
          : { id: { in: membershipTeamIds.length > 0 ? membershipTeamIds : [user.teamId] } }),
      },
      orderBy: [{ ageGroup: { sortOrder: 'asc' } }, { name: 'asc' }],
      include: hierarchyInclude,
    }),
    prisma.player.count({ where: { teamId: user.teamId } }),
    prisma.user.count({ where: { teamId: user.teamId, status: 'APPROVED' } }),
    prisma.event.count({
      where: { teamId: user.teamId, startAt: { gte: new Date() } },
    }),
    permissions.includes(Permission.MANAGE_MEMBERS)
      ? prisma.user.count({ where: { teamId: user.teamId, status: 'PENDING' } })
      : Promise.resolve(0),
  ]);

  return res.json({
    club: currentTeam.ageGroup.season.club,
    season: {
      id: currentTeam.ageGroup.season.id,
      name: currentTeam.ageGroup.season.name,
      startDate: currentTeam.ageGroup.season.startDate,
      endDate: currentTeam.ageGroup.season.endDate,
      isActive: currentTeam.ageGroup.season.isActive,
    },
    currentTeam: serializeTeam(currentTeam),
    ageGroups,
    teams: teams.map(serializeTeam),
    permissions,
    metrics: {
      players,
      members,
      upcomingEvents,
      pendingApprovals,
    },
  });
}

export async function createTeam(req: Request, res: Response) {
  const user = req.user!;
  const { ageGroupId, name, shortName, level } = req.body as {
    ageGroupId?: string;
    name?: string;
    shortName?: string;
    level?: string;
  };

  if (!ageGroupId || !name?.trim()) {
    return res.status(400).json({ message: 'Altersklasse und Mannschaftsname sind erforderlich.' });
  }

  const currentTeam = await prisma.team.findUnique({
    where: { id: user.teamId },
    include: hierarchyInclude,
  });
  if (!currentTeam) {
    return res.status(404).json({ message: 'Aktive Mannschaft nicht gefunden.' });
  }

  const ageGroup = await prisma.ageGroup.findFirst({
    where: {
      id: ageGroupId,
      season: {
        clubId: currentTeam.ageGroup.season.clubId,
        isActive: true,
      },
    },
  });
  if (!ageGroup) {
    return res.status(404).json({ message: 'Altersklasse nicht gefunden.' });
  }

  const duplicate = await prisma.team.findFirst({
    where: { ageGroupId, name: { equals: name.trim(), mode: 'insensitive' } },
  });
  if (duplicate) {
    return res.status(409).json({ message: 'Diese Mannschaft existiert bereits.' });
  }

  const team = await prisma.$transaction(async (tx) => {
    const created = await tx.team.create({
      data: {
        ageGroupId,
        name: name.trim(),
        shortName: shortName?.trim() || name.trim(),
        level: level?.trim() || null,
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
        metadata: { name: created.name, ageGroupId },
      },
    });
    return created;
  });

  return res.status(201).json(serializeTeam(team));
}

function serializeTeam(team: {
  id: string;
  name: string;
  shortName: string | null;
  level: string | null;
  isActive: boolean;
  ageGroup: {
    id: string;
    name: string;
    code: string;
    season: { id: string; name: string };
  };
}) {
  return {
    id: team.id,
    name: team.name,
    shortName: team.shortName,
    level: team.level,
    isActive: team.isActive,
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
