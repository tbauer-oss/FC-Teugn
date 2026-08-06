import 'models/user.dart';

enum PermissionKind { view, edit }

class RolePermission {
  const RolePermission(this.code, this.label, this.kind);

  final String code;
  final String label;
  final PermissionKind kind;
}

const _catalog = <RolePermission>[
  RolePermission('VIEW_TEAM', 'Mannschaft ansehen', PermissionKind.view),
  RolePermission('MANAGE_TEAM', 'Mannschaft verwalten', PermissionKind.edit),
  RolePermission(
    'MANAGE_ORGANIZATION',
    'Verein verwalten',
    PermissionKind.edit,
  ),
  RolePermission('MANAGE_MEMBERS', 'Mitglieder verwalten', PermissionKind.edit),
  RolePermission('MANAGE_PLAYERS', 'Spieler verwalten', PermissionKind.edit),
  RolePermission(
    'VIEW_SENSITIVE_PLAYER',
    'Sensible Spielerdaten ansehen',
    PermissionKind.view,
  ),
  RolePermission(
    'MANAGE_SENSITIVE_PLAYER',
    'Sensible Spielerdaten bearbeiten',
    PermissionKind.edit,
  ),
  RolePermission(
      'MANAGE_DOCUMENTS', 'Dokumente verwalten', PermissionKind.edit),
  RolePermission(
    'MANAGE_DEVELOPMENT',
    'Entwicklung dokumentieren',
    PermissionKind.edit,
  ),
  RolePermission('MANAGE_EVENTS', 'Termine verwalten', PermissionKind.edit),
  RolePermission('EVENT_DELETE', 'Termine löschen', PermissionKind.edit),
  RolePermission('MATCH_CANCEL', 'Spiele absagen', PermissionKind.edit),
  RolePermission('MATCH_DELETE', 'Spiele löschen', PermissionKind.edit),
  RolePermission('MATCH_RESCHEDULE', 'Spiele verlegen', PermissionKind.edit),
  RolePermission(
    'LEAGUE_MATCH_CANCEL',
    'Ligapartien absagen',
    PermissionKind.edit,
  ),
  RolePermission(
    'LEAGUE_MATCH_DELETE',
    'Ligapartien löschen',
    PermissionKind.edit,
  ),
  RolePermission(
    'LEAGUE_MATCH_RESCHEDULE',
    'Ligapartien verlegen',
    PermissionKind.edit,
  ),
  RolePermission(
      'MANAGE_LINEUPS', 'Aufstellungen verwalten', PermissionKind.edit),
  RolePermission(
      'MANAGE_LIVE_TICKER', 'Liveticker führen', PermissionKind.edit),
  RolePermission(
    'VIEW_PLAYER_STATS',
    'Spielerstatistiken ansehen',
    PermissionKind.view,
  ),
  RolePermission(
    'MANAGE_STATISTICS',
    'Statistiken verwalten',
    PermissionKind.edit,
  ),
  RolePermission('MANAGE_TRAINING', 'Training verwalten', PermissionKind.edit),
  RolePermission(
    'SEND_ANNOUNCEMENTS',
    'Nachrichten versenden',
    PermissionKind.edit,
  ),
  RolePermission('MANAGE_IMPORTS', 'Daten importieren', PermissionKind.edit),
  RolePermission(
    'RESPOND_ATTENDANCE',
    'Zu- und Absagen abgeben',
    PermissionKind.edit,
  ),
  RolePermission(
    'VIEW_TEAM_OPERATIONS',
    'Organisation ansehen',
    PermissionKind.view,
  ),
  RolePermission(
    'MANAGE_TEAM_OPERATIONS',
    'Organisation bearbeiten',
    PermissionKind.edit,
  ),
];

List<RolePermission> get allRolePermissions => List.unmodifiable(_catalog);

const _coachPermissions = <String>{
  'VIEW_TEAM',
  'MANAGE_TEAM',
  'MANAGE_MEMBERS',
  'MANAGE_PLAYERS',
  'VIEW_SENSITIVE_PLAYER',
  'MANAGE_SENSITIVE_PLAYER',
  'MANAGE_DOCUMENTS',
  'MANAGE_DEVELOPMENT',
  'MANAGE_EVENTS',
  'EVENT_DELETE',
  'MATCH_CANCEL',
  'MATCH_DELETE',
  'MATCH_RESCHEDULE',
  'LEAGUE_MATCH_CANCEL',
  'LEAGUE_MATCH_DELETE',
  'LEAGUE_MATCH_RESCHEDULE',
  'MANAGE_LINEUPS',
  'MANAGE_LIVE_TICKER',
  'VIEW_PLAYER_STATS',
  'MANAGE_STATISTICS',
  'MANAGE_TRAINING',
  'SEND_ANNOUNCEMENTS',
  'MANAGE_IMPORTS',
  'RESPOND_ATTENDANCE',
  'VIEW_TEAM_OPERATIONS',
  'MANAGE_TEAM_OPERATIONS',
};

const _assistantPermissions = <String>{
  'VIEW_TEAM',
  'MANAGE_PLAYERS',
  'VIEW_SENSITIVE_PLAYER',
  'MANAGE_DOCUMENTS',
  'MANAGE_DEVELOPMENT',
  'MANAGE_EVENTS',
  'EVENT_DELETE',
  'MATCH_CANCEL',
  'MATCH_DELETE',
  'MATCH_RESCHEDULE',
  'LEAGUE_MATCH_CANCEL',
  'LEAGUE_MATCH_DELETE',
  'LEAGUE_MATCH_RESCHEDULE',
  'MANAGE_LINEUPS',
  'MANAGE_LIVE_TICKER',
  'VIEW_PLAYER_STATS',
  'MANAGE_STATISTICS',
  'MANAGE_TRAINING',
  'SEND_ANNOUNCEMENTS',
  'MANAGE_IMPORTS',
  'RESPOND_ATTENDANCE',
  'VIEW_TEAM_OPERATIONS',
  'MANAGE_TEAM_OPERATIONS',
};

const _managerPermissions = <String>{
  'VIEW_TEAM',
  'MANAGE_MEMBERS',
  'MANAGE_PLAYERS',
  'VIEW_SENSITIVE_PLAYER',
  'MANAGE_EVENTS',
  'EVENT_DELETE',
  'MATCH_CANCEL',
  'MATCH_DELETE',
  'MATCH_RESCHEDULE',
  'LEAGUE_MATCH_CANCEL',
  'LEAGUE_MATCH_DELETE',
  'LEAGUE_MATCH_RESCHEDULE',
  'MANAGE_LINEUPS',
  'MANAGE_LIVE_TICKER',
  'VIEW_PLAYER_STATS',
  'MANAGE_STATISTICS',
  'MANAGE_TRAINING',
  'SEND_ANNOUNCEMENTS',
  'MANAGE_IMPORTS',
  'RESPOND_ATTENDANCE',
  'VIEW_TEAM_OPERATIONS',
  'MANAGE_TEAM_OPERATIONS',
};

bool canSelectStatisticsTeam(UserRole role) => switch (role) {
      UserRole.superAdmin ||
      UserRole.clubAdmin ||
      UserRole.trainerAdmin ||
      UserRole.youthDirector =>
        true,
      _ => false,
    };

List<RolePermission> permissionsForUserRole(UserRole role) {
  final codes = switch (role) {
    UserRole.superAdmin ||
    UserRole.clubAdmin ||
    UserRole.trainerAdmin ||
    UserRole.youthDirector =>
      _catalog.map((permission) => permission.code).toSet(),
    UserRole.coach || UserRole.trainer => _coachPermissions,
    UserRole.assistantCoach => _assistantPermissions,
    UserRole.teamManager => _managerPermissions,
    UserRole.parent || UserRole.player => const {
        'VIEW_TEAM',
        'VIEW_PLAYER_STATS',
        'RESPOND_ATTENDANCE',
        'VIEW_TEAM_OPERATIONS',
      },
    UserRole.readOnly => const {'VIEW_TEAM', 'VIEW_TEAM_OPERATIONS'},
  };
  return _catalog
      .where((permission) => codes.contains(permission.code))
      .toList();
}
