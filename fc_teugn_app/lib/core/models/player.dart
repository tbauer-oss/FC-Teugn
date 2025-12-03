class PlayerStats {
  final int games;
  final int goals;

  PlayerStats({required this.games, required this.goals});
}

class PlayerModel {
  final String id;
  final String firstName;
  final String lastName;
  final DateTime birthDate;
  final String gender;
  final String? position;
  final int? shirtNumber;
  final String? photoUrl;
  final String? team;
  final PlayerStats? stats;

  PlayerModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.gender,
    this.position,
    this.shirtNumber,
    this.photoUrl,
    this.team,
    this.stats,
  });

  String get fullName => '$firstName $lastName';

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    final statsJson = json['stats'] as Map<String, dynamic>?;
    return PlayerModel(
      id: json['id'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      birthDate: DateTime.parse(json['birthDate'] as String),
      gender: json['gender'] as String,
      position: json['position'] as String?,
      shirtNumber: json['shirtNumber'] as int?,
      photoUrl: json['photoUrl'] as String?,
      team: json['team'] as String?,
      stats: statsJson != null
          ? PlayerStats(
              games: statsJson['gamesPlayed'] as int? ?? 0,
              goals: statsJson['goals'] as int? ?? 0,
            )
          : null,
    );
  }
}
