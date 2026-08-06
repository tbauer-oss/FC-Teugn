import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/matchday.dart';
import 'team_game_format.dart';

abstract class TickerOfflineStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTickerOfflineStore implements TickerOfflineStore {
  SecureTickerOfflineStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class QueuedTickerAction {
  const QueuedTickerAction({
    required this.userId,
    required this.eventId,
    required this.clientEventId,
    required this.type,
    required this.createdAt,
    this.scorerId,
    this.assistId,
    this.comment,
    this.period,
    this.elapsedSeconds,
  });

  final String userId;
  final String eventId;
  final String clientEventId;
  final TickerEventType type;
  final DateTime createdAt;
  final String? scorerId;
  final String? assistId;
  final String? comment;
  final int? period;
  final int? elapsedSeconds;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'eventId': eventId,
        'clientEventId': clientEventId,
        'type': type.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'scorerId': scorerId,
        'assistId': assistId,
        'comment': comment,
        'period': period,
        'elapsedSeconds': elapsedSeconds,
      };

  factory QueuedTickerAction.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String? ?? 'comment';
    final type = TickerEventType.values.firstWhere(
      (item) => item.name == rawType,
      orElse: () => TickerEventType.comment,
    );
    return QueuedTickerAction(
      userId: json['userId'] as String,
      eventId: json['eventId'] as String,
      clientEventId: json['clientEventId'] as String,
      type: type,
      createdAt: DateTime.parse(json['createdAt'] as String),
      scorerId: json['scorerId'] as String?,
      assistId: json['assistId'] as String?,
      comment: json['comment'] as String?,
      period: json['period'] as int?,
      elapsedSeconds: json['elapsedSeconds'] as int?,
    );
  }
}

class TickerQueueSyncResult {
  const TickerQueueSyncResult({
    required this.sent,
    required this.rejected,
    required this.remaining,
    required this.online,
  });

  final int sent;
  final int rejected;
  final int remaining;
  final bool online;
}

class PermanentTickerActionError implements Exception {
  const PermanentTickerActionError(this.message);

  final String message;
}

class TickerOfflineQueue {
  TickerOfflineQueue({TickerOfflineStore? store})
      : _store = store ?? SecureTickerOfflineStore();

  static const _maximumActions = 100;
  static const _maximumAge = Duration(hours: 48);
  static const _cacheAge = Duration(days: 7);

  final TickerOfflineStore _store;

  String _queueKey(String userId) => 'fc_teugn_ticker_queue_v1_$userId';
  String _cacheKey(String userId, String eventId) =>
      'fc_teugn_match_cache_v1_${userId}_$eventId';

  Future<List<QueuedTickerAction>> pending({
    required String userId,
    String? eventId,
  }) async {
    final actions = await _readQueue(userId);
    final cutoff = DateTime.now().subtract(_maximumAge);
    final current = actions
        .where((item) => item.createdAt.isAfter(cutoff))
        .toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    if (current.length != actions.length) {
      await _writeQueue(userId, current);
    }
    return eventId == null
        ? current
        : current.where((item) => item.eventId == eventId).toList();
  }

  Future<void> enqueue(QueuedTickerAction action) async {
    final actions = await pending(userId: action.userId);
    if (actions.any(
      (item) => item.clientEventId == action.clientEventId,
    )) {
      return;
    }
    if (actions.length >= _maximumActions) {
      throw StateError(
        'Die Offline-Warteschlange ist voll. Bitte zuerst synchronisieren.',
      );
    }
    await _writeQueue(action.userId, [...actions, action]);
  }

  Future<TickerQueueSyncResult> synchronize({
    required String userId,
    required String eventId,
    required Future<void> Function(QueuedTickerAction action) send,
  }) async {
    var sent = 0;
    var rejected = 0;
    final scoped = await pending(userId: userId, eventId: eventId);
    for (final action in scoped) {
      try {
        await send(action);
      } on PermanentTickerActionError {
        await _remove(userId, action.clientEventId);
        rejected += 1;
        continue;
      } catch (_) {
        return TickerQueueSyncResult(
          sent: sent,
          rejected: rejected,
          remaining: (await pending(userId: userId, eventId: eventId)).length,
          online: false,
        );
      }
      await _remove(userId, action.clientEventId);
      sent += 1;
    }
    return TickerQueueSyncResult(
      sent: sent,
      rejected: rejected,
      remaining: (await pending(userId: userId, eventId: eventId)).length,
      online: true,
    );
  }

  Future<void> _remove(String userId, String clientEventId) async {
    final latest = await pending(userId: userId);
    latest.removeWhere((item) => item.clientEventId == clientEventId);
    await _writeQueue(userId, latest);
  }

  Future<void> cacheMatch({
    required String userId,
    required MatchdayModel match,
  }) {
    final snapshot = CachedMatchdaySnapshot.fromMatch(match);
    return _store.write(
      _cacheKey(userId, match.id),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<MatchdayModel?> cachedMatch({
    required String userId,
    required String eventId,
  }) async {
    final raw = await _store.read(_cacheKey(userId, eventId));
    if (raw == null) return null;
    try {
      final snapshot = CachedMatchdaySnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (snapshot.cachedAt.isBefore(DateTime.now().subtract(_cacheAge))) {
        await _store.delete(_cacheKey(userId, eventId));
        return null;
      }
      return snapshot.toMatch();
    } catch (_) {
      await _store.delete(_cacheKey(userId, eventId));
      return null;
    }
  }

  Future<List<QueuedTickerAction>> _readQueue(String userId) async {
    final raw = await _store.read(_queueKey(userId));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map(
            (item) => QueuedTickerAction.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .where((item) => item.userId == userId)
          .toList();
    } catch (_) {
      await _store.delete(_queueKey(userId));
      return [];
    }
  }

  Future<void> _writeQueue(
    String userId,
    List<QueuedTickerAction> actions,
  ) async {
    if (actions.isEmpty) {
      await _store.delete(_queueKey(userId));
      return;
    }
    await _store.write(
      _queueKey(userId),
      jsonEncode(actions.map((item) => item.toJson()).toList()),
    );
  }
}

class CachedMatchdaySnapshot {
  const CachedMatchdaySnapshot({
    required this.id,
    required this.title,
    required this.startAt,
    required this.location,
    required this.teamId,
    required this.opponent,
    required this.isHome,
    required this.cachedAt,
    this.gameFormat = TeamGameFormat.football7,
    this.meetingAt,
    this.meetingLocation,
    this.ticker,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime? meetingAt;
  final String? meetingLocation;
  final String location;
  final String teamId;
  final String opponent;
  final bool isHome;
  final DateTime cachedAt;
  final LiveTickerModel? ticker;
  final TeamGameFormat gameFormat;

  factory CachedMatchdaySnapshot.fromMatch(MatchdayModel match) {
    return CachedMatchdaySnapshot(
      id: match.id,
      title: match.title,
      startAt: match.startAt,
      meetingAt: match.meetingAt,
      meetingLocation: match.meetingLocation,
      location: match.location,
      teamId: match.teamId,
      opponent: match.details?.opponent ?? 'Gegner',
      isHome: match.details?.isHome ?? true,
      ticker: match.ticker,
      gameFormat: match.gameFormat,
      cachedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startAt': startAt.toUtc().toIso8601String(),
        'meetingAt': meetingAt?.toUtc().toIso8601String(),
        'meetingLocation': meetingLocation,
        'location': location,
        'teamId': teamId,
        'opponent': opponent,
        'isHome': isHome,
        'cachedAt': cachedAt.toUtc().toIso8601String(),
        'ticker': ticker == null ? null : _tickerToJson(ticker!),
        'teamGameFormat': gameFormat.apiValue,
      };

  factory CachedMatchdaySnapshot.fromJson(Map<String, dynamic> json) {
    return CachedMatchdaySnapshot(
      id: json['id'] as String,
      title: json['title'] as String,
      startAt: DateTime.parse(json['startAt'] as String),
      meetingAt: json['meetingAt'] == null
          ? null
          : DateTime.parse(json['meetingAt'] as String),
      meetingLocation: json['meetingLocation'] as String?,
      location: json['location'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      opponent: json['opponent'] as String? ?? 'Gegner',
      isHome: json['isHome'] as bool? ?? true,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      ticker: json['ticker'] == null
          ? null
          : LiveTickerModel.fromJson(
              json['ticker'] as Map<String, dynamic>,
            ),
      gameFormat: TeamGameFormat.fromApi(json['teamGameFormat']),
    );
  }

  MatchdayModel toMatch() => MatchdayModel(
        id: id,
        title: title,
        startAt: startAt,
        meetingAt: meetingAt,
        meetingLocation: meetingLocation,
        location: location,
        teamId: teamId,
        details: MatchDetailsModel(
          opponent: opponent,
          isHome: isHome,
          status: MatchStatus.planned,
          durationMinutes: 60,
          periodMinutes: 30,
          periodCount: 2,
          ourGoals: ticker?.ourGoals,
          theirGoals: ticker?.theirGoals,
        ),
        ticker: ticker,
        gameFormat: gameFormat,
      );
}

Map<String, dynamic> _tickerToJson(LiveTickerModel ticker) => {
      'status': _apiEnum(ticker.status),
      'currentPeriod': ticker.currentPeriod,
      'elapsedSeconds': ticker.elapsedSeconds,
      'ourGoals': ticker.ourGoals,
      'theirGoals': ticker.theirGoals,
      'lastSequence': ticker.lastSequence,
      'events': ticker.events
          .map(
            (event) => {
              'id': event.id,
              'sequence': event.sequence,
              'type': _apiEnum(event.type),
              'elapsedSeconds': event.elapsedSeconds,
              'ourGoals': event.ourGoals,
              'theirGoals': event.theirGoals,
              'comment': event.comment,
              'clientEventId': event.clientEventId,
              'correctsId': event.correctsId,
              'scorer': _playerToJson(event.scorer),
              'assist': _playerToJson(event.assist),
            },
          )
          .toList(),
    };

Map<String, dynamic>? _playerToJson(MatchPlayer? player) => player == null
    ? null
    : {
        'id': player.id,
        'firstName': player.name,
        'lastName': '',
        'shirtNumber': player.shirtNumber,
        'position': player.position,
      };

String _apiEnum(Enum value) {
  return value.name
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toUpperCase();
}
