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

export async function accessibleTeamIds(user: TeamScopedUser) {
  if (hasPermission(user.role as Role, Permission.MANAGE_ORGANIZATION)) {
    const clubId = await clubIdForTeam(user.teamId);
    if (!clubId) return [user.teamId];
    const teams = await prisma.team.findMany({
      where: { ageGroup: { season: { clubId } } },
      select: { id: true },
    });
    return teams.map((team) => team.id);
  }
  const memberships = await prisma.teamMembership.findMany({
    where: { userId: user.id, status: AccountStatus.APPROVED },
    select: { teamId: true },
  });
  return [...new Set([user.teamId, ...memberships.map((item) => item.teamId)])];
}

export async function canManageTeam(user: TeamScopedUser, teamId: string) {
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
