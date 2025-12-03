enum UserRole { parent, coach }

class AppUser {
  final String id;
  final String email;
  final String name;
  final UserRole role;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String;
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      role: role == 'COACH' ? UserRole.coach : UserRole.parent,
    );
  }
}
