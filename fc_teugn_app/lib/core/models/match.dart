import 'player.dart';
import 'event.dart';

enum MatchType { league, friendly }

MatchType matchTypeFromString(String value) {
  return value == 'FRIENDLY' ? MatchType.friendly : MatchType.league;
}

class MatchRSVP {
  final String id;
  final String playerId;
  final RSVPStatus status;

  MatchRSVP({required this.id, required this.playerId, required this.status});

  factory MatchRSVP.fromJson(Map<String, dynamic> json) {
    return MatchRSVP(
      id: json['id'] as String,
      playerId: json['playerId'] as String,
      status: rsvpFromString(json['status'] as String),
    );
  }
}

class LineupPosition {
  final String id;
  final String playerId;
  final double posX;
  final double posY;
  final bool isSubstitute;

  LineupPosition({
    required this.id,
    required this.playerId,
    required this.posX,
    required this.posY,
    required this.isSubstitute,
  });

  factory LineupPosition.fromJson(Map<String, dynamic> json) {
    return LineupPosition(
      id: json['id'] as String,
      playerId: json['playerId'] as String,
      posX: (json['posX'] as num).toDouble(),
      posY: (json['posY'] as num).toDouble(),
      isSubstitute: json['isSubstitute'] as bool? ?? false,
    );
  }
}

class MatchLineup {
  final String id;
  final String? name;
  final String? formation;
  final List<LineupPosition> positions;

  MatchLineup({this.name, this.formation, required this.positions, required this.id});

  factory MatchLineup.fromJson(Map<String, dynamic> json) {
    return MatchLineup(
      id: json['id'] as String,
      name: json['name'] as String?,
      formation: json['formation'] as String?,
      positions: (json['positions'] as List<dynamic>? ?? [])
          .map((e) => LineupPosition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MatchGoal {
  final String id;
  final String playerId;

  MatchGoal({required this.id, required this.playerId});

  factory MatchGoal.fromJson(Map<String, dynamic> json) {
    return MatchGoal(id: json['id'] as String, playerId: json['playerId'] as String);
  }
}

class MatchModel {
  final String id;
  final MatchType type;
  final DateTime date;
  final DateTime kickOff;
  final String location;
  final String opponent;
  final bool isHome;
  final String? competition;
  final int? ourGoals;
  final int? theirGoals;
  final String? notes;
  final bool rsvpEnabled;
  final List<MatchRSVP> rsvps;
  final List<MatchLineup> lineups;
  final List<MatchGoal> goals;

  MatchModel({
    required this.id,
    required this.type,
    required this.date,
    required this.kickOff,
    required this.location,
    required this.opponent,
    required this.isHome,
    this.competition,
    this.ourGoals,
    this.theirGoals,
    this.notes,
    required this.rsvpEnabled,
    required this.rsvps,
    required this.lineups,
    required this.goals,
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    return MatchModel(
      id: json['id'] as String,
      type: matchTypeFromString(json['type'] as String),
      date: DateTime.parse(json['date'] as String),
      kickOff: DateTime.parse(json['kickOff'] as String),
      location: json['location'] as String,
      opponent: json['opponent'] as String,
      isHome: json['isHome'] as bool,
      competition: json['competition'] as String?,
      ourGoals: json['ourGoals'] as int?,
      theirGoals: json['theirGoals'] as int?,
      notes: json['notes'] as String?,
      rsvpEnabled: json['rsvpEnabled'] as bool? ?? true,
      rsvps: (json['rsvps'] as List<dynamic>? ?? [])
          .map((e) => MatchRSVP.fromJson(e as Map<String, dynamic>))
          .toList(),
      lineups: (json['lineups'] as List<dynamic>? ?? [])
          .map((e) => MatchLineup.fromJson(e as Map<String, dynamic>))
          .toList(),
      goals: (json['goals'] as List<dynamic>? ?? [])
          .map((e) => MatchGoal.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
