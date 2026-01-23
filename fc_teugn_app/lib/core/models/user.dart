enum UserRole { trainerAdmin, trainer, parent }

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

  bool get isTrainer => role == UserRole.trainer || role == UserRole.trainerAdmin;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? 'PARENT';
    final status = json['status'] as String? ?? 'PENDING';
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      teamId: json['teamId'] as String? ?? '',
      role: role == 'TRAINER_ADMIN'
          ? UserRole.trainerAdmin
          : role == 'TRAINER'
              ? UserRole.trainer
              : UserRole.parent,
      status: status == 'APPROVED'
          ? AccountStatus.approved
          : status == 'BLOCKED'
              ? AccountStatus.blocked
              : AccountStatus.pending,
    );
  }
}
