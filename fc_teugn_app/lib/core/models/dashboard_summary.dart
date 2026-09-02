import 'communication.dart';
import 'event.dart';
import 'player.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.players,
    required this.events,
    required this.notifications,
  });

  final List<PlayerModel> players;
  final List<EventModel> events;
  final List<AppNotificationModel> notifications;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        players: (json['players'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlayerModel.fromJson)
            .toList(growable: false),
        events: (json['events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EventModel.fromJson)
            .toList(growable: false),
        notifications: (json['notifications'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AppNotificationModel.fromJson)
            .toList(growable: false),
      );
}

class MatchRouteEstimate {
  const MatchRouteEstimate({
    required this.distanceKm,
    required this.durationMinutes,
    required this.attribution,
  });

  final double distanceKm;
  final int durationMinutes;
  final String attribution;

  static MatchRouteEstimate? fromJson(Map<String, dynamic> json) {
    if (json['available'] != true) return null;
    final distance = (json['distanceKm'] as num?)?.toDouble();
    final duration = (json['durationMinutes'] as num?)?.toInt();
    if (distance == null || duration == null) return null;
    return MatchRouteEstimate(
      distanceKm: distance,
      durationMinutes: duration,
      attribution: json['attribution'] as String? ?? '© OpenStreetMap',
    );
  }
}

class ParentConsentAttention {
  const ParentConsentAttention({
    required this.playerId,
    required this.playerName,
    required this.openCount,
  });

  final String playerId;
  final String playerName;
  final int openCount;

  factory ParentConsentAttention.fromJson(Map<String, dynamic> json) =>
      ParentConsentAttention(
        playerId: json['playerId'] as String,
        playerName: json['playerName'] as String? ?? 'Spieler',
        openCount: json['openCount'] as int? ?? 0,
      );
}
