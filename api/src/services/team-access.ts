import { AccountStatus, Prisma, Role as PrismaRole } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { Role } from '../types/enums';

export type TeamScopedUser = {
  id: string;
  teamId: string;
  role: Role | PrismaRole;
};

export async function clubIdForTeam(teamId: string) {
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: { ageGroup: { select: { season: { select: { clubId: true } } } } },
  });
  return team?.ageGroup.season.clubId ?? null;
}

/**
 * Resolves a usable team for pages that need season and club context.
 *
 * A user's historic primary team can disappear when teams are reorganised.
 * That must not lock a system administrator (or a user with another approved
 * membership) out of otherwise global pages such as organisation and pitch
 * occupancy.
 */
export async function resolveContextTeamId(user: TeamScopedUser) {
  const currentTeam = await prisma.team.findFirst({
    where: { id: user.teamId, deletedAt: null, isActive: true },
    select: { id: true },
  });
  if (currentTeam) return currentTeam.id;

  const membership = await prisma.teamMembership.findFirst({
    where: {
      userId: user.id,
      status: AccountStatus.APPROVED,
      team: { deletedAt: null, isActive: true },
    },
    orderBy: { createdAt: 'asc' },
    select: { teamId: true },
  });
  if (membership) return membership.teamId;

  if (String(user.role) !== Role.SUPER_ADMIN) return null;

  const fallback = await prisma.team.findFirst({
    where: {
      deletedAt: null,
      isActive: true,
      ageGroup: { season: { isActive: true } },
    },
    orderBy: { name: 'asc' },
    select: { id: true },
  });
  return fallback?.id ?? null;
}

export async function accessibleTeamIds(user: TeamScopedUser) {
  if (String(user.role) === Role.SUPER_ADMIN) {
    const teams = await prisma.team.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });
    return teams.map((team) => team.id);
  }
  if (hasPermission(user.role as Role, Permission.MANAGE_ORGANIZATION)) {
    const clubId = await clubIdForTeam(user.teamId);
    if (!clubId) return [user.teamId];
    const teams = await prisma.team.findMany({
      where: {
        ageGroup: { season: { clubId } },
        deletedAt: null,
      },
      select: { id: true },
    });
    return teams.map((team) => team.id);
  }
  const memberships = await prisma.teamMembership.findMany({
    where: {
      userId: user.id,
      status: AccountStatus.APPROVED,
      team: { deletedAt: null },
    },
    select: { teamId: true },
  });
  const currentTeam = await prisma.team.findFirst({
    where: { id: user.teamId, deletedAt: null },
    select: { id: true },
  });
  return [
    ...new Set([
      ...(currentTeam ? [currentTeam.id] : []),
      ...memberships.map((item) => item.teamId),
    ]),
  ];
}

export async function youthPlayerPoolTeamIds(user: TeamScopedUser) {
  const accessibleIds = await accessibleTeamIds(user);
  if (!accessibleIds.length) return [];
  const ageGroups = await prisma.team.findMany({
    where: { id: { in: accessibleIds }, deletedAt: null },
    distinct: ['ageGroupId'],
    select: { ageGroupId: true },
  });
  if (!ageGroups.length) return [];
  const teams = await prisma.team.findMany({
    where: {
      ageGroupId: { in: ageGroups.map((item) => item.ageGroupId) },
      deletedAt: null,
    },
    select: { id: true },
  });
  return teams.map((team) => team.id);
}

export async function youthPlayerPoolTeamIdsForTeam(teamId: string) {
  const team = await prisma.team.findFirst({
    where: { id: teamId, deletedAt: null },
    select: { ageGroupId: true },
  });
  if (!team) return [];
  const teams = await prisma.team.findMany({
    where: { ageGroupId: team.ageGroupId, deletedAt: null },
    orderBy: { teamNumber: 'asc' },
    select: { id: true },
  });
  return teams.map((item) => item.id);
}

export async function canManageTeam(user: TeamScopedUser, teamId: string) {
  if (String(user.role) === Role.SUPER_ADMIN) {
    return Boolean(await prisma.team.findUnique({
      where: { id: teamId },
      select: { id: true, deletedAt: true },
    }).then((team) => team && team.deletedAt === null));
  }
  if (hasPermission(user.role as Role, Permission.MANAGE_ORGANIZATION)) {
    const [currentClubId, targetClubId] = await Promise.all([
      clubIdForTeam(user.teamId),
      clubIdForTeam(teamId),
    ]);
    return currentClubId !== null && currentClubId === targetClubId;
  }
  const membership = await prisma.teamMembership.findUnique({
    where: { userId_teamId: { userId: user.id, teamId } },
    select: { role: true, status: true },
  });
  if (membership?.status === AccountStatus.APPROVED) {
    return hasPermission(membership.role as Role, Permission.MANAGE_TEAM);
  }
  return teamId === user.teamId && hasPermission(user.role as Role, Permission.MANAGE_TEAM);
}

export function eventTeamScope(teamIds: string[]): Prisma.EventWhereInput {
  return {
    OR: [{ teamId: { in: teamIds } }, { targetTeams: { some: { teamId: { in: teamIds } } } }],
  };
}

export async function ownPlayerIds(user: TeamScopedUser) {
  if (String(user.role) === Role.PARENT) {
    const links = await prisma.parentPlayerLink.findMany({
      where: { parentId: user.id },
      select: { playerId: true },
    });
    return links.map((link) => link.playerId);
  }
  if (String(user.role) === Role.PLAYER) {
    const player = await prisma.player.findUnique({
      where: { userId: user.id },
      select: { id: true },
    });
    return player ? [player.id] : [];
  }
  return [];
}
