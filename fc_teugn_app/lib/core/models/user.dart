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

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.role,
    required this.status,
    required this.teamId,
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
