import { AccountStatus, Prisma, Role as PrismaRole } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { hasEffectivePermission, Permission } from '../security/permissions';
import { Role } from '../types/enums';

export type TeamScopedUser = {
  id: string;
  teamId: string;
  role: Role | PrismaRole;
  permissions?: string[];
};

function permitted(user: TeamScopedUser, permission: Permission) {
  return hasEffectivePermission(
    user.role as Role,
    permission,
    user.permissions,
  );
}

/**
 * Roles whose responsibilities inherently span the complete youth club.
 *
 * A trainer administrator may have additional editing permissions, but still
 * works inside the youth selected in the app-wide context switcher. View scope
 * and edit permissions must therefore remain separate concerns.
 */
export function hasOrganizationWideTeamScope(role: Role | PrismaRole) {
  const organizationWideRoles: ReadonlySet<string> = new Set([
    Role.SUPER_ADMIN,
    Role.CLUB_ADMIN,
    Role.YOUTH_DIRECTOR,
  ]);
  return organizationWideRoles.has(String(role));
}

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
  if (permitted(user, Permission.MANAGE_ORGANIZATION)) {
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
  // Family assignments are independent from the user's primary club role. A
  // trainer can therefore answer for their own child without losing trainer
  // permissions or having to switch accounts.
  const linkedPlayerTeams = await prisma.parentPlayerLink.findMany({
    where: { parentId: user.id, player: { teamId: { not: null } } },
    select: { player: { select: { teamId: true } } },
  });
  return [
    ...new Set([
      ...(currentTeam ? [currentTeam.id] : []),
      ...memberships.map((item) => item.teamId),
      ...linkedPlayerTeams
        .map((item) => item.player.teamId)
        .filter((id): id is string => Boolean(id)),
    ]),
  ];
}

/**
 * Returns the app-wide selected working context. It can only narrow the set of
 * accessible teams and therefore never acts as an authorization grant.
 */
export async function selectedContextTeamIds(user: TeamScopedUser) {
  const accessibleIds = await accessibleTeamIds(user);
  if (!accessibleIds.length) return [];
  const preference = await prisma.userContextPreference.findUnique({
    where: { userId: user.id },
    select: { ageGroupId: true, activeTeamId: true, includeAllTeams: true },
  });
  if (!preference) return accessibleIds.includes(user.teamId)
    ? [user.teamId]
    : [accessibleIds[0]];
  const teams = await prisma.team.findMany({
    where: {
      id: { in: accessibleIds },
      ageGroupId: preference.ageGroupId,
      deletedAt: null,
      isActive: true,
      ...(!preference.includeAllTeams && preference.activeTeamId
        ? { id: preference.activeTeamId }
        : {}),
    },
    orderBy: { teamNumber: 'asc' },
    select: { id: true },
  });
  return teams.length ? teams.map((team) => team.id) : [accessibleIds[0]];
}

/**
 * Teams whose members the current staff account may administer.
 *
 * Member administration deliberately ignores family links: being a parent in
 * another youth must never grant staff access there. Staff memberships are
 * then narrowed to the youth selected in the working-context switcher. The
 * complete selected youth remains manageable, even when its UI context shows
 * only one of several squads.
 */
export async function memberManagementTeamIds(user: TeamScopedUser) {
  if (hasOrganizationWideTeamScope(user.role)) {
    return accessibleTeamIds(user);
  }
  if (!permitted(user, Permission.MANAGE_MEMBERS)) return [];

  const [memberships, currentTeam, preference] = await Promise.all([
    prisma.teamMembership.findMany({
      where: {
        userId: user.id,
        status: AccountStatus.APPROVED,
        team: { deletedAt: null, isActive: true },
      },
      select: { teamId: true, role: true },
    }),
    prisma.team.findFirst({
      where: { id: user.teamId, deletedAt: null, isActive: true },
      select: { id: true, ageGroupId: true },
    }),
    prisma.userContextPreference.findUnique({
      where: { userId: user.id },
      select: { ageGroupId: true },
    }),
  ]);
  const manageableIds = new Set<string>();
  if (currentTeam) manageableIds.add(currentTeam.id);
  for (const membership of memberships) {
    if (hasPermissionForMembership(membership.role, Permission.MANAGE_MEMBERS)) {
      manageableIds.add(membership.teamId);
    }
  }
  if (!manageableIds.size) return [];

  const selectedAgeGroupId = preference?.ageGroupId ?? currentTeam?.ageGroupId;
  if (!selectedAgeGroupId) return [];
  const teams = await prisma.team.findMany({
    where: {
      id: { in: [...manageableIds] },
      ageGroupId: selectedAgeGroupId,
      deletedAt: null,
      isActive: true,
    },
    orderBy: { teamNumber: 'asc' },
    select: { id: true },
  });
  return teams.map((team) => team.id);
}

function hasPermissionForMembership(
  role: PrismaRole,
  permission: Permission,
) {
  return hasEffectivePermission(role as Role, permission);
}

export async function contextualTeamIds(user: TeamScopedUser) {
  const contextRoles = new Set<string>([
    Role.SUPER_ADMIN,
    Role.CLUB_ADMIN,
    Role.YOUTH_DIRECTOR,
    Role.TRAINER_ADMIN,
    Role.COACH,
    Role.TRAINER,
    Role.ASSISTANT_COACH,
    Role.TEAM_MANAGER,
  ]);
  return contextRoles.has(String(user.role))
    ? selectedContextTeamIds(user)
    : accessibleTeamIds(user);
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
  if (permitted(user, Permission.MANAGE_ORGANIZATION)) {
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
    return permitted({ ...user, role: membership.role }, Permission.MANAGE_TEAM);
  }
  return teamId === user.teamId && permitted(user, Permission.MANAGE_TEAM);
}

const formationManagerRoles = new Set<string>([
  Role.SUPER_ADMIN,
  Role.CLUB_ADMIN,
  Role.COACH,
  Role.TRAINER,
  Role.ASSISTANT_COACH,
]);

export function canManageFormationRole(role: Role | PrismaRole) {
  return formationManagerRoles.has(String(role));
}

export async function canManageFormation(
  user: TeamScopedUser,
  teamId: string,
) {
  const role = String(user.role);
  if (!canManageFormationRole(user.role)) return false;
  if (role === Role.SUPER_ADMIN) {
    return Boolean(await prisma.team.findFirst({
      where: { id: teamId, deletedAt: null },
      select: { id: true },
    }));
  }
  if (role === Role.CLUB_ADMIN) {
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
    return canManageFormationRole(membership.role);
  }
  return teamId === user.teamId;
}

export function eventTeamScope(teamIds: string[]): Prisma.EventWhereInput {
  return {
    OR: [{ teamId: { in: teamIds } }, { targetTeams: { some: { teamId: { in: teamIds } } } }],
  };
}

export async function ownPlayerIds(user: TeamScopedUser) {
  const [links, player] = await Promise.all([
    prisma.parentPlayerLink.findMany({
      where: { parentId: user.id },
      select: { playerId: true },
    }),
    prisma.player.findUnique({
      where: { userId: user.id },
      select: { id: true },
    }),
  ]);
  return [...new Set([
    ...links.map((link) => link.playerId),
    ...(player ? [player.id] : []),
  ])];
}
