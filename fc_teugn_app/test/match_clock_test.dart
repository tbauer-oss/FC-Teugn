import 'package:fc_teugn_app/core/match_clock.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts the configured period duration backwards', () {
    final ticker = _ticker(
      currentPeriod: 2,
      elapsedSeconds: 1020,
      events: [
        _event(
          type: TickerEventType.periodStart,
          period: 2,
          elapsedSeconds: 900,
        ),
      ],
    );

    final clock = calculateMatchClock(
      ticker: ticker,
      periodMinutes: 15,
      effectiveElapsedSeconds: 1020,
    );

    expect(clock.periodElapsedSeconds, 120);
    expect(clock.remainingSeconds, 780);
    expect(clock.countdown, '13:00');
    expect(clock.expired, isFalse);
  });

  test('stops at zero when a period has expired', () {
    final ticker = _ticker(
      currentPeriod: 1,
      elapsedSeconds: 910,
      events: [
        _event(
          type: TickerEventType.matchStart,
          period: 1,
          elapsedSeconds: 0,
        ),
      ],
    );

    final clock = calculateMatchClock(
      ticker: ticker,
      periodMinutes: 15,
      effectiveElapsedSeconds: 910,
    );

    expect(clock.remainingSeconds, 0);
    expect(clock.countdown, '00:00');
    expect(clock.expired, isTrue);
  });

  test('uses familiar labels for halves and quarters', () {
    expect(matchPeriodLabel(1, 2), '1. Halbzeit');
    expect(matchPeriodLabel(3, 4), '3. Viertel');
    expect(matchPeriodLabel(2, 3), 'Abschnitt 2 von 3');
  });

  test('routine server polls do not reset or rewind the running clock', () {
    var nowMilliseconds = 0;
    final clock = StableElapsedClock(
      monotonicMilliseconds: () => nowMilliseconds,
    );
    clock.synchronize(
        _ticker(currentPeriod: 1, elapsedSeconds: 100, events: []));

    nowMilliseconds = 1900;
    expect(clock.elapsedSeconds, 101);

    clock.synchronize(
        _ticker(currentPeriod: 1, elapsedSeconds: 100, events: []));
    nowMilliseconds = 2100;

    expect(clock.elapsedSeconds, 102);
  });

  test('next UI tick remains aligned to the monotonic second boundary', () {
    var nowMilliseconds = 0;
    final clock = StableElapsedClock(
      monotonicMilliseconds: () => nowMilliseconds,
    );
    clock.synchronize(
        _ticker(currentPeriod: 1, elapsedSeconds: 100, events: []));

    nowMilliseconds = 275;
    expect(clock.millisecondsUntilNextSecond, 725);

    nowMilliseconds = 1000;
    expect(clock.elapsedSeconds, 101);
    expect(clock.millisecondsUntilNextSecond, 1000);

    // A delayed callback catches up and aligns the following callback again;
    // it never accumulates the delay like a periodic timer would.
    nowMilliseconds = 2340;
    expect(clock.elapsedSeconds, 102);
    expect(clock.millisecondsUntilNextSecond, 660);
  });

  test('pausing a clock never makes the displayed time jump backwards', () {
    var nowMilliseconds = 0;
    final clock = StableElapsedClock(
      monotonicMilliseconds: () => nowMilliseconds,
    );
    clock.synchronize(
        _ticker(currentPeriod: 1, elapsedSeconds: 100, events: []));

    nowMilliseconds = 2900;
    clock.synchronize(
      _ticker(
        currentPeriod: 1,
        elapsedSeconds: 101,
        status: TickerStatus.paused,
        events: [],
      ),
    );
    nowMilliseconds = 8000;

    expect(clock.elapsedSeconds, 102);
  });

  test('a new period deliberately starts from the server baseline', () {
    var nowMilliseconds = 0;
    final clock = StableElapsedClock(
      monotonicMilliseconds: () => nowMilliseconds,
    );
    clock.synchronize(
        _ticker(currentPeriod: 1, elapsedSeconds: 895, events: []));

    nowMilliseconds = 7000;
    clock.synchronize(
        _ticker(currentPeriod: 2, elapsedSeconds: 900, events: []));

    expect(clock.elapsedSeconds, 900);
  });

  test('an authoritative match reset rewinds the clock immediately', () {
    var nowMilliseconds = 0;
    final clock = StableElapsedClock(
      monotonicMilliseconds: () => nowMilliseconds,
    );
    clock.synchronize(
      _ticker(
        currentPeriod: 1,
        elapsedSeconds: 120,
        status: TickerStatus.live,
        events: [
          _event(
            type: TickerEventType.matchStart,
            period: 1,
            elapsedSeconds: 0,
          ),
        ],
      ),
    );

    nowMilliseconds = 2500;
    expect(clock.elapsedSeconds, 122);

    clock.synchronize(
      _ticker(
        currentPeriod: 1,
        elapsedSeconds: 0,
        status: TickerStatus.notStarted,
        events: const [],
      ),
    );

    expect(clock.elapsedSeconds, 0);
    expect(clock.millisecondsUntilNextSecond, 1000);
  });

  test('incremental ticker snapshots retain the known event history', () {
    final current = LiveTickerModel(
      status: TickerStatus.live,
      currentPeriod: 1,
      elapsedSeconds: 40,
      ourGoals: 1,
      theirGoals: 0,
      lastSequence: 1,
      events: [
        _event(
          type: TickerEventType.homeGoal,
          period: 1,
          elapsedSeconds: 40,
          sequence: 1,
          clientEventId: 'goal-1',
        ),
      ],
    );
    final incoming = LiveTickerModel(
      status: TickerStatus.live,
      currentPeriod: 1,
      elapsedSeconds: 72,
      ourGoals: 1,
      theirGoals: 1,
      lastSequence: 2,
      events: [
        _event(
          type: TickerEventType.awayGoal,
          period: 1,
          elapsedSeconds: 72,
          sequence: 2,
          clientEventId: 'goal-2',
        ),
      ],
    );

    final merged = mergeLiveTickerSnapshot(current, incoming);

    expect(merged.events.map((event) => event.sequence), [1, 2]);
    expect(merged.theirGoals, 1);
    expect(merged.elapsedSeconds, 72);
  });

  test('incremental correction removes the corrected event', () {
    final goal = _event(
      type: TickerEventType.homeGoal,
      period: 1,
      elapsedSeconds: 40,
      sequence: 1,
      clientEventId: 'goal-1',
    );
    final current = LiveTickerModel(
      status: TickerStatus.live,
      currentPeriod: 1,
      elapsedSeconds: 40,
      ourGoals: 1,
      theirGoals: 0,
      lastSequence: 1,
      events: [goal],
    );
    final incoming = LiveTickerModel(
      status: TickerStatus.live,
      currentPeriod: 1,
      elapsedSeconds: 42,
      ourGoals: 0,
      theirGoals: 0,
      lastSequence: 2,
      events: [
        TickerEventModel(
          id: 'revoke-1',
          sequence: 2,
          type: TickerEventType.eventRevoked,
          elapsedSeconds: 42,
          ourGoals: 0,
          theirGoals: 0,
          correctsId: goal.id,
        ),
      ],
    );

    final merged = mergeLiveTickerSnapshot(current, incoming);

    expect(merged.events.map((event) => event.id), ['revoke-1']);
    expect(merged.ourGoals, 0);
  });
}

LiveTickerModel _ticker({
  required int currentPeriod,
  required int elapsedSeconds,
  required List<TickerEventModel> events,
  TickerStatus status = TickerStatus.live,
}) =>
    LiveTickerModel(
      status: status,
      currentPeriod: currentPeriod,
      elapsedSeconds: elapsedSeconds,
      ourGoals: 0,
      theirGoals: 0,
      lastSequence: events.length,
      events: events,
    );

TickerEventModel _event({
  required TickerEventType type,
  required int period,
  required int elapsedSeconds,
  int? sequence,
  String? clientEventId,
}) =>
    TickerEventModel(
      id: '${sequence ?? period}-${type.name}',
      sequence: sequence ?? period,
      type: type,
      period: period,
      elapsedSeconds: elapsedSeconds,
      ourGoals: 0,
      theirGoals: 0,
      clientEventId: clientEventId,
    );
