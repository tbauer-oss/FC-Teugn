import { Role } from '../types/enums';

export const Permission = {
  VIEW_TEAM: 'VIEW_TEAM',
  MANAGE_TEAM: 'MANAGE_TEAM',
  MANAGE_ORGANIZATION: 'MANAGE_ORGANIZATION',
  MANAGE_MEMBERS: 'MANAGE_MEMBERS',
  MANAGE_PLAYERS: 'MANAGE_PLAYERS',
  MANAGE_EVENTS: 'MANAGE_EVENTS',
  RESPOND_ATTENDANCE: 'RESPOND_ATTENDANCE',
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
    Permission.MANAGE_EVENTS,
    Permission.RESPOND_ATTENDANCE,
  ],
  [Role.TRAINER]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_TEAM,
    Permission.MANAGE_MEMBERS,
    Permission.MANAGE_PLAYERS,
    Permission.MANAGE_EVENTS,
    Permission.RESPOND_ATTENDANCE,
  ],
  [Role.ASSISTANT_COACH]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_PLAYERS,
    Permission.MANAGE_EVENTS,
    Permission.RESPOND_ATTENDANCE,
  ],
  [Role.TEAM_MANAGER]: [
    Permission.VIEW_TEAM,
    Permission.MANAGE_MEMBERS,
    Permission.MANAGE_PLAYERS,
    Permission.MANAGE_EVENTS,
    Permission.RESPOND_ATTENDANCE,
  ],
  [Role.PARENT]: [Permission.VIEW_TEAM, Permission.RESPOND_ATTENDANCE],
  [Role.PLAYER]: [Permission.VIEW_TEAM, Permission.RESPOND_ATTENDANCE],
  [Role.READ_ONLY]: [Permission.VIEW_TEAM],
};

export function hasPermission(role: Role, permission: Permission) {
  return permissionsByRole[role]?.includes(permission) ?? false;
}

export function permissionsForRole(role: Role) {
  return [...(permissionsByRole[role] ?? [])];
}
