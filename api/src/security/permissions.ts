import { Role } from '../types/enums';
import { PermissionOverrideState } from '@prisma/client';
import { prisma } from '../lib/prisma';

export const Permission = {
  VIEW_TEAM: 'VIEW_TEAM',
  MANAGE_TEAM: 'MANAGE_TEAM',
  MANAGE_ORGANIZATION: 'MANAGE_ORGANIZATION',
  MANAGE_MEMBERS: 'MANAGE_MEMBERS',
  MANAGE_PLAYERS: 'MANAGE_PLAYERS',
  VIEW_SENSITIVE_PLAYER: 'VIEW_SENSITIVE_PLAYER',
  MANAGE_SENSITIVE_PLAYER: 'MANAGE_SENSITIVE_PLAYER',
  MANAGE_DOCUMENTS: 'MANAGE_DOCUMENTS',
  MANAGE_DEVELOPMENT: 'MANAGE_DEVELOPMENT',
  MANAGE_EVENTS: 'MANAGE_EVENTS',
  CONFIGURE_TRAINING_REMINDERS: 'CONFIGURE_TRAINING_REMINDERS',
  CANCEL_TRAINING_OCCURRENCE: 'CANCEL_TRAINING_OCCURRENCE',
  DELETE_CANCELLED_TRAINING: 'DELETE_CANCELLED_TRAINING',
  PUBLISH_LINEUP_INTERNAL: 'PUBLISH_LINEUP_INTERNAL',
  NOMINATE_SQUAD: 'NOMINATE_SQUAD',
  RELEASE_MATCH_FAMILY: 'RELEASE_MATCH_FAMILY',
  SEND_EVENT_NOTIFICATIONS: 'SEND_EVENT_NOTIFICATIONS',
  EVENT_DELETE: 'EVENT_DELETE',
  MATCH_DELETE: 'MATCH_DELETE',
  MATCH_CANCEL: 'MATCH_CANCEL',
  MATCH_RESCHEDULE: 'MATCH_RESCHEDULE',
  LEAGUE_MATCH_DELETE: 'LEAGUE_MATCH_DELETE',
  LEAGUE_MATCH_CANCEL: 'LEAGUE_MATCH_CANCEL',
  LEAGUE_MATCH_RESCHEDULE: 'LEAGUE_MATCH_RESCHEDULE',
  MANAGE_LINEUPS: 'MANAGE_LINEUPS',
  MANAGE_LIVE_TICKER: 'MANAGE_LIVE_TICKER',
  VIEW_PLAYER_STATS: 'VIEW_PLAYER_STATS',
  MANAGE_STATISTICS: 'MANAGE_STATISTICS',
  MANAGE_TRAINING: 'MANAGE_TRAINING',
  SEND_ANNOUNCEMENTS: 'SEND_ANNOUNCEMENTS',
  MANAGE_IMPORTS: 'MANAGE_IMPORTS',
  RESPOND_ATTENDANCE: 'RESPOND_ATTENDANCE',
  VIEW_TEAM_OPERATIONS: 'VIEW_TEAM_OPERATIONS',
  MANAGE_TEAM_OPERATIONS: 'MANAGE_TEAM_OPERATIONS',
} as const;

export type Permission = (typeof Permission)[keyof typeof Permission];

const allPermissions = Object.values(Permission);

const permissionsByRole: Record<Role, readonly Permission[]> = {
  [Role.SUPER_ADMIN]: allPermissions,
  [Role.CLUB_ADMIN]: allPermissions,
  [Role.TRAINER_ADMIN]: allPermissions,
  [Role.YOUTH_DIRECTOR]: allPermissions,
  [Role.COACH]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_TEAM,
    Permission.MANAGE_MEMBERS,
    Permission.MANAGE_PLAYERS,
    Permission.VIEW_SENSITIVE_PLAYER,
    Permission.MANAGE_SENSITIVE_PLAYER,
    Permission.MANAGE_DOCUMENTS,
    Permission.MANAGE_DEVELOPMENT,
    Permission.MANAGE_EVENTS,
    Permission.CONFIGURE_TRAINING_REMINDERS,
    Permission.CANCEL_TRAINING_OCCURRENCE,
    Permission.DELETE_CANCELLED_TRAINING,
    Permission.PUBLISH_LINEUP_INTERNAL,
    Permission.NOMINATE_SQUAD,
    Permission.RELEASE_MATCH_FAMILY,
    Permission.SEND_EVENT_NOTIFICATIONS,
    Permission.EVENT_DELETE,
    Permission.MATCH_DELETE,
    Permission.MATCH_CANCEL,
    Permission.MATCH_RESCHEDULE,
    Permission.LEAGUE_MATCH_DELETE,
    Permission.LEAGUE_MATCH_CANCEL,
    Permission.LEAGUE_MATCH_RESCHEDULE,
    Permission.MANAGE_LINEUPS,
    Permission.MANAGE_LIVE_TICKER,
    Permission.VIEW_PLAYER_STATS,
    Permission.MANAGE_STATISTICS,
    Permission.MANAGE_TRAINING,
    Permission.SEND_ANNOUNCEMENTS,
    Permission.MANAGE_IMPORTS,
    Permission.RESPOND_ATTENDANCE,
    Permission.VIEW_TEAM_OPERATIONS,
    Permission.MANAGE_TEAM_OPERATIONS,
  ],
  [Role.TRAINER]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_TEAM,
    Permission.MANAGE_MEMBERS,
    Permission.MANAGE_PLAYERS,
    Permission.VIEW_SENSITIVE_PLAYER,
    Permission.MANAGE_SENSITIVE_PLAYER,
    Permission.MANAGE_DOCUMENTS,
    Permission.MANAGE_DEVELOPMENT,
    Permission.MANAGE_EVENTS,
    Permission.CONFIGURE_TRAINING_REMINDERS,
    Permission.CANCEL_TRAINING_OCCURRENCE,
    Permission.DELETE_CANCELLED_TRAINING,
    Permission.PUBLISH_LINEUP_INTERNAL,
    Permission.NOMINATE_SQUAD,
    Permission.RELEASE_MATCH_FAMILY,
    Permission.SEND_EVENT_NOTIFICATIONS,
    Permission.EVENT_DELETE,
    Permission.MATCH_DELETE,
    Permission.MATCH_CANCEL,
    Permission.MATCH_RESCHEDULE,
    Permission.LEAGUE_MATCH_DELETE,
    Permission.LEAGUE_MATCH_CANCEL,
    Permission.LEAGUE_MATCH_RESCHEDULE,
    Permission.MANAGE_LINEUPS,
    Permission.MANAGE_LIVE_TICKER,
    Permission.VIEW_PLAYER_STATS,
    Permission.MANAGE_STATISTICS,
    Permission.MANAGE_TRAINING,
    Permission.SEND_ANNOUNCEMENTS,
    Permission.MANAGE_IMPORTS,
    Permission.RESPOND_ATTENDANCE,
    Permission.VIEW_TEAM_OPERATIONS,
    Permission.MANAGE_TEAM_OPERATIONS,
  ],
  [Role.ASSISTANT_COACH]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_MEMBERS,
    Permission.MANAGE_PLAYERS,
    Permission.VIEW_SENSITIVE_PLAYER,
    Permission.MANAGE_DOCUMENTS,
    Permission.MANAGE_DEVELOPMENT,
    Permission.MANAGE_EVENTS,
    Permission.CONFIGURE_TRAINING_REMINDERS,
    Permission.CANCEL_TRAINING_OCCURRENCE,
    Permission.DELETE_CANCELLED_TRAINING,
    Permission.PUBLISH_LINEUP_INTERNAL,
    Permission.NOMINATE_SQUAD,
    Permission.RELEASE_MATCH_FAMILY,
    Permission.SEND_EVENT_NOTIFICATIONS,
    Permission.EVENT_DELETE,
    Permission.MATCH_DELETE,
    Permission.MATCH_CANCEL,
    Permission.MATCH_RESCHEDULE,
    Permission.LEAGUE_MATCH_DELETE,
    Permission.LEAGUE_MATCH_CANCEL,
    Permission.LEAGUE_MATCH_RESCHEDULE,
    Permission.MANAGE_LINEUPS,
    Permission.MANAGE_LIVE_TICKER,
    Permission.VIEW_PLAYER_STATS,
    Permission.MANAGE_STATISTICS,
    Permission.MANAGE_TRAINING,
    Permission.SEND_ANNOUNCEMENTS,
    Permission.MANAGE_IMPORTS,
    Permission.RESPOND_ATTENDANCE,
    Permission.VIEW_TEAM_OPERATIONS,
    Permission.MANAGE_TEAM_OPERATIONS,
  ],
  [Role.TEAM_MANAGER]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_MEMBERS,
    Permission.MANAGE_PLAYERS,
    Permission.VIEW_SENSITIVE_PLAYER,
    Permission.MANAGE_EVENTS,
    Permission.CONFIGURE_TRAINING_REMINDERS,
    Permission.CANCEL_TRAINING_OCCURRENCE,
    Permission.DELETE_CANCELLED_TRAINING,
    Permission.PUBLISH_LINEUP_INTERNAL,
    Permission.NOMINATE_SQUAD,
    Permission.RELEASE_MATCH_FAMILY,
    Permission.SEND_EVENT_NOTIFICATIONS,
    Permission.EVENT_DELETE,
    Permission.MATCH_DELETE,
    Permission.MATCH_CANCEL,
    Permission.MATCH_RESCHEDULE,
    Permission.LEAGUE_MATCH_DELETE,
    Permission.LEAGUE_MATCH_CANCEL,
    Permission.LEAGUE_MATCH_RESCHEDULE,
    Permission.MANAGE_LINEUPS,
    Permission.MANAGE_LIVE_TICKER,
    Permission.VIEW_PLAYER_STATS,
    Permission.MANAGE_STATISTICS,
    Permission.MANAGE_TRAINING,
    Permission.SEND_ANNOUNCEMENTS,
    Permission.MANAGE_IMPORTS,
    Permission.RESPOND_ATTENDANCE,
    Permission.VIEW_TEAM_OPERATIONS,
    Permission.MANAGE_TEAM_OPERATIONS,
  ],
  [Role.PARENT]: [
    Permission.VIEW_TEAM,
    Permission.VIEW_PLAYER_STATS,
    Permission.RESPOND_ATTENDANCE,
    Permission.VIEW_TEAM_OPERATIONS,
  ],
  [Role.PLAYER]: [
    Permission.VIEW_TEAM,
    Permission.VIEW_PLAYER_STATS,
    Permission.RESPOND_ATTENDANCE,
    Permission.VIEW_TEAM_OPERATIONS,
  ],
  [Role.READ_ONLY]: [Permission.VIEW_TEAM, Permission.VIEW_TEAM_OPERATIONS],
};

export function hasPermission(role: Role, permission: Permission) {
  return permissionsByRole[role]?.includes(permission) ?? false;
}

export function permissionsForRole(role: Role) {
  return [...(permissionsByRole[role] ?? [])];
}

export type PermissionOverride = {
  permission: string;
  state: PermissionOverrideState | 'ALLOW' | 'DENY';
};

/** Pure effective-right calculation, shared by middleware and unit tests. */
export function resolveEffectivePermissions(
  role: Role,
  overrides: readonly PermissionOverride[],
) {
  // A system administrator must never be able to lock themselves out.
  if (role === Role.SUPER_ADMIN) return [...allPermissions];
  const effective = new Set<Permission>(permissionsForRole(role));
  for (const override of overrides) {
    if (!allPermissions.includes(override.permission as Permission)) continue;
    if (override.state === PermissionOverrideState.DENY) {
      effective.delete(override.permission as Permission);
    } else {
      effective.add(override.permission as Permission);
    }
  }
  return allPermissions.filter((permission) => effective.has(permission));
}

export async function effectivePermissionsForUser(userId: string, role: Role) {
  if (role === Role.SUPER_ADMIN) return [...allPermissions];
  const overrides = await prisma.userPermissionOverride.findMany({
    where: { userId },
    select: { permission: true, state: true },
  });
  return resolveEffectivePermissions(role, overrides);
}

export function hasEffectivePermission(
  role: Role,
  permission: Permission,
  effectivePermissions?: readonly string[],
) {
  return role === Role.SUPER_ADMIN ||
    (effectivePermissions
      ? effectivePermissions.includes(permission)
      : hasPermission(role, permission));
}
