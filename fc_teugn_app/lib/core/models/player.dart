class PlayerModel {
  final String id;
  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String? position;
  final int? shirtNumber;

  PlayerModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.birthDate,
    this.position,
    this.shirtNumber,
  });

  String get fullName => '$firstName $lastName';

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    return PlayerModel(
      id: json['id'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      birthDate: json['birthDate'] != null
          ? DateTime.parse(json['birthDate'] as String)
          : null,
      position: json['position'] as String?,
      shirtNumber: json['shirtNumber'] as int?,
    );
  }
}
