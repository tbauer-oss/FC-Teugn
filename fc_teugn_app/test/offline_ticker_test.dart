import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/offline_ticker.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements TickerOfflineStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('offline ticker queue preserves order and stable idempotency ids',
      () async {
    final queue = TickerOfflineQueue(store: _MemoryStore());
    final first = QueuedTickerAction(
      userId: 'user-1',
      eventId: 'event-1',
      clientEventId: 'action-1',
      type: TickerEventType.matchStart,
      createdAt: DateTime.now().subtract(const Duration(seconds: 2)),
    );
    final second = QueuedTickerAction(
      userId: 'user-1',
      eventId: 'event-1',
      clientEventId: 'action-2',
      type: TickerEventType.homeGoal,
      scorerId: 'player-9',
      assistId: 'player-10',
      createdAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    await queue.enqueue(first);
    await queue.enqueue(second);
    await queue.enqueue(second);

    final attempted = <String>[];
    final interrupted = await queue.synchronize(
      userId: 'user-1',
      eventId: 'event-1',
      send: (action) async {
        attempted.add(action.clientEventId);
        if (action.clientEventId == 'action-2') {
          throw Exception('offline');
        }
      },
    );

    expect(attempted, ['action-1', 'action-2']);
    expect(interrupted.sent, 1);
    expect(interrupted.rejected, 0);
    expect(interrupted.remaining, 1);
    expect(interrupted.online, isFalse);
    expect(
      (await queue.pending(userId: 'user-1')).single.clientEventId,
      'action-2',
    );
    expect(
      (await queue.pending(userId: 'user-1')).single.scorerId,
      'player-9',
    );
    expect(
      (await queue.pending(userId: 'user-1')).single.assistId,
      'player-10',
    );

    final retried = <String>[];
    final completed = await queue.synchronize(
      userId: 'user-1',
      eventId: 'event-1',
      send: (action) async {
        retried.add(action.clientEventId);
      },
    );
    expect(retried, ['action-2']);
    expect(completed.sent, 1);
    expect(completed.rejected, 0);
    expect(completed.remaining, 0);
    expect(completed.online, isTrue);
  });

  test('permanently rejected actions are reported instead of retried forever',
      () async {
    final queue = TickerOfflineQueue(store: _MemoryStore());
    await queue.enqueue(
      QueuedTickerAction(
        userId: 'coach-1',
        eventId: 'event-1',
        clientEventId: 'invalid-action',
        type: TickerEventType.matchEnd,
        createdAt: DateTime.now(),
      ),
    );

    final result = await queue.synchronize(
      userId: 'coach-1',
      eventId: 'event-1',
      send: (_) async {
        throw const PermanentTickerActionError('Spiel bereits beendet');
      },
    );

    expect(result.sent, 0);
    expect(result.rejected, 1);
    expect(result.remaining, 0);
    expect(result.online, isTrue);
  });

  test('offline queue is separated by authenticated user', () async {
    final queue = TickerOfflineQueue(store: _MemoryStore());
    await queue.enqueue(
      QueuedTickerAction(
        userId: 'coach-1',
        eventId: 'event-1',
        clientEventId: 'coach-1-action',
        type: TickerEventType.comment,
        createdAt: DateTime.now(),
      ),
    );
    await queue.enqueue(
      QueuedTickerAction(
        userId: 'coach-2',
        eventId: 'event-1',
        clientEventId: 'coach-2-action',
        type: TickerEventType.comment,
        createdAt: DateTime.now(),
      ),
    );

    expect(
      (await queue.pending(userId: 'coach-1')).single.clientEventId,
      'coach-1-action',
    );
    expect(
      (await queue.pending(userId: 'coach-2')).single.clientEventId,
      'coach-2-action',
    );
  });

  test('last loaded matchday remains available from the offline cache',
      () async {
    final queue = TickerOfflineQueue(store: _MemoryStore());
    final match = MatchdayModel(
      id: 'event-1',
      title: 'FC Teugn gegen SV Muster',
      startAt: DateTime.parse('2026-08-15T09:00:00Z'),
      location: 'Waldstadion',
      teamId: 'team-1',
      details: const MatchDetailsModel(
        opponent: 'SV Muster',
        isHome: true,
        status: MatchStatus.live,
        durationMinutes: 60,
        periodMinutes: 30,
        periodCount: 2,
      ),
      ticker: const LiveTickerModel(
        status: TickerStatus.live,
        currentPeriod: 1,
        elapsedSeconds: 720,
        ourGoals: 2,
        theirGoals: 1,
        lastSequence: 4,
        events: [],
      ),
    );

    await queue.cacheMatch(userId: 'coach-1', match: match);
    final cached = await queue.cachedMatch(
      userId: 'coach-1',
      eventId: 'event-1',
    );

    expect(cached?.title, match.title);
    expect(cached?.details?.opponent, 'SV Muster');
    expect(cached?.ticker?.ourGoals, 2);
    expect(cached?.ticker?.lastSequence, 4);
  });
}
