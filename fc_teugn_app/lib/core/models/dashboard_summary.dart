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
