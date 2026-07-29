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
}

LiveTickerModel _ticker({
  required int currentPeriod,
  required int elapsedSeconds,
  required List<TickerEventModel> events,
}) =>
    LiveTickerModel(
      status: TickerStatus.live,
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
}) =>
    TickerEventModel(
      id: '$period-${type.name}',
      sequence: period,
      type: type,
      period: period,
      elapsedSeconds: elapsedSeconds,
      ourGoals: 0,
      theirGoals: 0,
    );
