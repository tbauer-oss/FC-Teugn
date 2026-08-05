enum TrainingPhase { warmUp, mainPart, gameForm, coolDown }

enum TrainingAttendanceStatus {
  present,
  excused,
  unexcused,
  injured,
  late,
  leftEarly,
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final normalized = raw?.toString().toLowerCase().replaceAll('_', '');
  return values
          .where((item) => item.name.toLowerCase() == normalized)
          .firstOrNull ??
      fallback;
}

String trainingApiEnum(Enum value) => value.name
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toUpperCase();

class TrainingModel {
  const TrainingModel({
    required this.id,
    required this.title,
    required this.startAt,
    required this.location,
    required this.teamId,
    required this.attendance,
    required this.roster,
    this.plan,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final String location;
  final String teamId;
  final TrainingPlanModel? plan;
  final List<TrainingAttendanceEntry> attendance;
  final List<TrainingRosterPlayer> roster;

  factory TrainingModel.fromJson(Map<String, dynamic> json) => TrainingModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Training',
        startAt: DateTime.parse(json['startAt'] as String),
        location: json['location'] as String? ?? '',
        teamId: json['teamId'] as String? ?? '',
        plan: json['trainingPlan'] == null
            ? null
            : TrainingPlanModel.fromJson(
                json['trainingPlan'] as Map<String, dynamic>,
              ),
        attendance: (json['attendance'] as List<dynamic>? ?? const [])
            .map(
              (item) => TrainingAttendanceEntry.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        roster: (json['roster'] as List<dynamic>? ?? const [])
            .map(
              (item) => TrainingRosterPlayer.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class TrainingRosterPlayer {
  const TrainingRosterPlayer({
    required this.id,
    required this.name,
    this.shirtNumber,
  });
  final String id;
  final String name;
  final int? shirtNumber;

  factory TrainingRosterPlayer.fromJson(Map<String, dynamic> json) =>
      TrainingRosterPlayer(
        id: json['id'] as String,
        name: (json['preferredName'] as String?)?.trim().isNotEmpty == true
            ? json['preferredName'] as String
            : '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'.trim(),
        shirtNumber: json['shirtNumber'] as int?,
      );
}

class TrainingPlanModel {
  const TrainingPlanModel({
    required this.focusAreas,
    required this.durationMinutes,
    required this.items,
    this.coaches = const [],
    this.learningGoals,
    this.participantNotes,
    this.legacyCoaches,
    this.materials,
    this.pitchSetup,
    this.feedback,
  });

  final List<String> focusAreas;
  final String? learningGoals;
  final int durationMinutes;
  final String? participantNotes;
  final List<TrainingCoachModel> coaches;
  final String? legacyCoaches;
  final String? materials;
  final String? pitchSetup;
  final String? feedback;
  final List<TrainingPlanItemModel> items;

  factory TrainingPlanModel.fromJson(Map<String, dynamic> json) =>
      TrainingPlanModel(
        focusAreas: (json['focusAreas'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        learningGoals: json['learningGoals'] as String?,
        durationMinutes: json['durationMinutes'] as int? ?? 90,
        participantNotes: json['participantNotes'] as String?,
        coaches: (json['coachAssignments'] as List<dynamic>? ?? const [])
            .map(
              (item) => TrainingCoachModel.fromJson(
                (item as Map<String, dynamic>)['user'] as Map<String, dynamic>,
              ),
            )
            .toList(),
        legacyCoaches: json['coaches'] as String?,
        materials: json['materials'] as String?,
        pitchSetup: json['pitchSetup'] as String?,
        feedback: json['feedback'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .map(
              (item) => TrainingPlanItemModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class TrainingCoachModel {
  const TrainingCoachModel({
    required this.id,
    required this.name,
    required this.role,
    this.teamIds = const [],
  });

  final String id;
  final String name;
  final String role;
  final List<String> teamIds;

  factory TrainingCoachModel.fromJson(Map<String, dynamic> json) =>
      TrainingCoachModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Trainer/in',
        role: json['role'] as String? ?? 'COACH',
        teamIds: (json['teamIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );
}

class TrainingPlanItemModel {
  const TrainingPlanItemModel({
    required this.title,
    required this.phase,
    required this.durationMinutes,
    this.exerciseId,
    this.notes,
  });

  final String title;
  final TrainingPhase phase;
  final int durationMinutes;
  final String? exerciseId;
  final String? notes;

  factory TrainingPlanItemModel.fromJson(Map<String, dynamic> json) =>
      TrainingPlanItemModel(
        title: json['title'] as String? ?? 'Trainingsbaustein',
        phase: _enum(
          TrainingPhase.values,
          json['phase'],
          TrainingPhase.mainPart,
        ),
        durationMinutes: json['durationMinutes'] as int? ?? 10,
        exerciseId: json['exerciseId'] as String?,
        notes: json['notes'] as String?,
      );
}

class TrainingExerciseModel {
  const TrainingExerciseModel({
    required this.id,
    required this.teamId,
    required this.title,
    required this.category,
    required this.durationMinutes,
    required this.setup,
    required this.instructions,
    required this.isFavorite,
    this.materials,
    this.coachingPoints,
    this.variations,
    this.minPlayers,
    this.maxPlayers,
  });

  final String id;
  final String teamId;
  final String title;
  final String category;
  final int durationMinutes;
  final String setup;
  final String instructions;
  final String? materials;
  final String? coachingPoints;
  final String? variations;
  final int? minPlayers;
  final int? maxPlayers;
  final bool isFavorite;

  factory TrainingExerciseModel.fromJson(Map<String, dynamic> json) =>
      TrainingExerciseModel(
        id: json['id'] as String,
        teamId: json['teamId'] as String,
        title: json['title'] as String? ?? 'Übung',
        category: json['category'] as String? ?? 'Allgemein',
        durationMinutes: json['durationMinutes'] as int? ?? 15,
        setup: json['setup'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        materials: json['materials'] as String?,
        coachingPoints: json['coachingPoints'] as String?,
        variations: json['variations'] as String?,
        minPlayers: json['minPlayers'] as int?,
        maxPlayers: json['maxPlayers'] as int?,
        isFavorite: json['isFavorite'] as bool? ?? false,
      );
}

class TrainingAttendanceEntry {
  const TrainingAttendanceEntry({
    required this.playerId,
    required this.playerName,
    this.status,
    this.note,
  });

  final String playerId;
  final String playerName;
  final TrainingAttendanceStatus? status;
  final String? note;

  factory TrainingAttendanceEntry.fromJson(Map<String, dynamic> json) {
    final player = json['player'] as Map<String, dynamic>;
    return TrainingAttendanceEntry(
      playerId: player['id'] as String,
      playerName: (player['preferredName'] as String?)?.trim().isNotEmpty ==
              true
          ? player['preferredName'] as String
          : '${player['firstName'] ?? ''} ${player['lastName'] ?? ''}'.trim(),
      status: json['trainingStatus'] == null
          ? null
          : _enum(
              TrainingAttendanceStatus.values,
              json['trainingStatus'],
              TrainingAttendanceStatus.present,
            ),
      note: json['actualAttendanceNote'] as String?,
    );
  }
}
