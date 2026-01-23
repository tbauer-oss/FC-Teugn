enum EventType { training, match, event }

enum AttendanceStatus { yes, no, maybe, unknown }

EventType eventTypeFromString(String value) {
  switch (value) {
    case 'MATCH':
      return EventType.match;
    case 'EVENT':
      return EventType.event;
    default:
      return EventType.training;
  }
}

AttendanceStatus attendanceFromString(String value) {
  switch (value) {
    case 'YES':
      return AttendanceStatus.yes;
    case 'NO':
      return AttendanceStatus.no;
    case 'MAYBE':
      return AttendanceStatus.maybe;
    default:
      return AttendanceStatus.unknown;
  }
}

class MatchDetails {
  final String opponent;
  final bool isHome;
  final String? competition;
  final String? notes;
  final int? ourGoals;
  final int? theirGoals;

  MatchDetails({
    required this.opponent,
    required this.isHome,
    this.competition,
    this.notes,
    this.ourGoals,
    this.theirGoals,
  });

  factory MatchDetails.fromJson(Map<String, dynamic> json) {
    return MatchDetails(
      opponent: json['opponent'] as String? ?? 'Unbekannt',
      isHome: json['isHome'] as bool? ?? true,
      competition: json['competition'] as String?,
      notes: json['notes'] as String?,
      ourGoals: json['ourGoals'] as int?,
      theirGoals: json['theirGoals'] as int?,
    );
  }
}

class EventAttendance {
  final String id;
  final String playerId;
  final AttendanceStatus status;

  EventAttendance({
    required this.id,
    required this.playerId,
    required this.status,
  });

  factory EventAttendance.fromJson(Map<String, dynamic> json) {
    return EventAttendance(
      id: json['id'] as String,
      playerId: json['playerId'] as String,
      status: attendanceFromString(json['status'] as String? ?? 'UNKNOWN'),
    );
  }
}

class EventModel {
  final String id;
  final EventType type;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final String location;
  final String? description;
  final bool attendanceFinalized;
  final MatchDetails? matchDetails;
  final List<EventAttendance> attendance;

  EventModel({
    required this.id,
    required this.type,
    required this.title,
    required this.startAt,
    this.endAt,
    required this.location,
    this.description,
    required this.attendanceFinalized,
    this.matchDetails,
    required this.attendance,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      type: eventTypeFromString(json['type'] as String? ?? 'TRAINING'),
      title: json['title'] as String,
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: json['endAt'] != null ? DateTime.parse(json['endAt'] as String) : null,
      location: json['location'] as String,
      description: json['description'] as String?,
      attendanceFinalized: json['attendanceFinalized'] as bool? ?? false,
      matchDetails: json['matchDetails'] != null
          ? MatchDetails.fromJson(json['matchDetails'] as Map<String, dynamic>)
          : null,
      attendance: (json['attendance'] as List<dynamic>? ?? [])
          .map((e) => EventAttendance.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
