enum UserRole {
  superAdmin,
  clubAdmin,
  youthDirector,
  coach,
  assistantCoach,
  teamManager,
  trainerAdmin,
  trainer,
  parent,
  player,
  readOnly,
}

enum AccountStatus { pending, approved, blocked }

class AppUser {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final UserRole role;
  final AccountStatus status;
  final String teamId;
  final DateTime? createdAt;
  final List<UserTeamMembership> memberships;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.role,
    required this.status,
    required this.teamId,
    this.createdAt,
    this.memberships = const [],
  });

  bool get isTrainer => switch (role) {
        UserRole.superAdmin ||
        UserRole.clubAdmin ||
        UserRole.youthDirector ||
        UserRole.coach ||
        UserRole.assistantCoach ||
        UserRole.teamManager ||
        UserRole.trainerAdmin ||
        UserRole.trainer =>
          true,
        _ => false,
      };

  String get roleLabel => switch (role) {
        UserRole.superAdmin => 'Systemadministration',
        UserRole.clubAdmin => 'Vereinsadministration',
        UserRole.youthDirector => 'Jugendleitung',
        UserRole.coach || UserRole.trainer => 'Trainerteam',
        UserRole.assistantCoach => 'Co-Trainerteam',
        UserRole.teamManager => 'Teamorganisation',
        UserRole.trainerAdmin => 'Trainer-Administration',
        UserRole.parent => 'Elternteil',
        UserRole.player => 'Spieler',
        UserRole.readOnly => 'Lesender Zugriff',
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? 'PARENT';
    final status = json['status'] as String? ?? 'PENDING';
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      teamId: json['teamId'] as String? ?? '',
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      memberships: (json['memberships'] as List<dynamic>? ?? [])
          .map((item) =>
              UserTeamMembership.fromJson(item as Map<String, dynamic>))
          .toList(),
      role: switch (role) {
        'SUPER_ADMIN' => UserRole.superAdmin,
        'CLUB_ADMIN' => UserRole.clubAdmin,
        'YOUTH_DIRECTOR' => UserRole.youthDirector,
        'COACH' => UserRole.coach,
        'ASSISTANT_COACH' => UserRole.assistantCoach,
        'TEAM_MANAGER' => UserRole.teamManager,
        'TRAINER_ADMIN' => UserRole.trainerAdmin,
        'TRAINER' => UserRole.trainer,
        'PLAYER' => UserRole.player,
        'READ_ONLY' => UserRole.readOnly,
        _ => UserRole.parent,
      },
      status: status == 'APPROVED'
          ? AccountStatus.approved
          : status == 'BLOCKED'
              ? AccountStatus.blocked
              : AccountStatus.pending,
    );
  }
}

class UserTeamMembership {
  const UserTeamMembership({
    required this.teamId,
    required this.teamName,
    required this.ageGroupCode,
    required this.role,
    required this.status,
  });

  final String teamId;
  final String teamName;
  final String ageGroupCode;
  final UserRole role;
  final AccountStatus status;

  factory UserTeamMembership.fromJson(Map<String, dynamic> json) {
    final team = json['team'] as Map<String, dynamic>;
    final ageGroup = team['ageGroup'] as Map<String, dynamic>;
    return UserTeamMembership(
      teamId: team['id'] as String,
      teamName: team['name'] as String,
      ageGroupCode: ageGroup['code'] as String? ?? '',
      role: userRoleFromApi(json['role'] as String?),
      status: accountStatusFromApi(json['status'] as String?),
    );
  }
}

UserRole userRoleFromApi(String? role) => switch (role) {
      'SUPER_ADMIN' => UserRole.superAdmin,
      'CLUB_ADMIN' => UserRole.clubAdmin,
      'YOUTH_DIRECTOR' => UserRole.youthDirector,
      'COACH' => UserRole.coach,
      'ASSISTANT_COACH' => UserRole.assistantCoach,
      'TEAM_MANAGER' => UserRole.teamManager,
      'TRAINER_ADMIN' => UserRole.trainerAdmin,
      'TRAINER' => UserRole.trainer,
      'PLAYER' => UserRole.player,
      'READ_ONLY' => UserRole.readOnly,
      _ => UserRole.parent,
    };

AccountStatus accountStatusFromApi(String? status) => switch (status) {
      'APPROVED' => AccountStatus.approved,
      'BLOCKED' => AccountStatus.blocked,
      _ => AccountStatus.pending,
    };

String userRoleApi(UserRole role) => switch (role) {
      UserRole.superAdmin => 'SUPER_ADMIN',
      UserRole.clubAdmin => 'CLUB_ADMIN',
      UserRole.youthDirector => 'YOUTH_DIRECTOR',
      UserRole.coach || UserRole.trainer => 'COACH',
      UserRole.assistantCoach => 'ASSISTANT_COACH',
      UserRole.teamManager => 'TEAM_MANAGER',
      UserRole.trainerAdmin => 'TRAINER_ADMIN',
      UserRole.parent => 'PARENT',
      UserRole.player => 'PLAYER',
      UserRole.readOnly => 'READ_ONLY',
    };
