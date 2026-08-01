import 'dart:math';

import 'models/matchday.dart';

class StableElapsedClock {
  StableElapsedClock({int Function()? monotonicMilliseconds})
      : _monotonicMilliseconds =
            monotonicMilliseconds ?? _systemStopwatchMilliseconds;

  static final Stopwatch _systemStopwatch = Stopwatch()..start();

  static int _systemStopwatchMilliseconds() =>
      _systemStopwatch.elapsedMilliseconds;

  final int Function() _monotonicMilliseconds;

  bool _initialized = false;
  int _anchorElapsedSeconds = 0;
  int _anchorMilliseconds = 0;
  int _currentPeriod = 1;
  TickerStatus _status = TickerStatus.notStarted;

  int get elapsedSeconds {
    if (!_initialized || _status != TickerStatus.live) {
      return _anchorElapsedSeconds;
    }
    final elapsedMilliseconds =
        max(0, _monotonicMilliseconds() - _anchorMilliseconds);
    return _anchorElapsedSeconds + elapsedMilliseconds ~/ 1000;
  }

  /// Remaining monotonic time until the displayed second changes.
  ///
  /// A one-shot timer can use this value after every callback. This keeps the
  /// UI aligned with the actual clock instead of accumulating the scheduling
  /// delay of a periodic timer.
  int get millisecondsUntilNextSecond {
    if (!_initialized || _status != TickerStatus.live) return 1000;
    final elapsedMilliseconds =
        max(0, _monotonicMilliseconds() - _anchorMilliseconds);
    return 1000 - (elapsedMilliseconds % 1000);
  }

  void synchronize(LiveTickerModel ticker) {
    final now = _monotonicMilliseconds();
    if (!_initialized) {
      _setAnchor(ticker.elapsedSeconds, ticker, now);
      _initialized = true;
      return;
    }

    final localElapsed = elapsedSeconds;
    final periodChanged = ticker.currentPeriod != _currentPeriod;
    final statusChanged = ticker.status != _status;

    if (periodChanged) {
      _setAnchor(ticker.elapsedSeconds, ticker, now);
      return;
    }

    if (statusChanged) {
      _setAnchor(
        max(localElapsed, ticker.elapsedSeconds),
        ticker,
        now,
      );
      return;
    }

    if (ticker.status != TickerStatus.live) {
      _setAnchor(
        max(localElapsed, ticker.elapsedSeconds),
        ticker,
        now,
      );
      return;
    }

    // Routine polls contain rounded server seconds and arrive with network
    // latency. Keeping the monotonic local anchor avoids visible jumps.
    // Only a large forward discrepancy indicates that the local clock really
    // missed an external update and needs a hard correction.
    if (ticker.elapsedSeconds > localElapsed + 10) {
      _setAnchor(ticker.elapsedSeconds, ticker, now);
    }
  }

  void _setAnchor(
    int elapsedSeconds,
    LiveTickerModel ticker,
    int monotonicMilliseconds,
  ) {
    _anchorElapsedSeconds = max(0, elapsedSeconds);
    _anchorMilliseconds = monotonicMilliseconds;
    _currentPeriod = ticker.currentPeriod;
    _status = ticker.status;
  }
}

class MatchClockValue {
  const MatchClockValue({
    required this.elapsedSeconds,
    required this.periodElapsedSeconds,
    required this.remainingSeconds,
    required this.periodDurationSeconds,
  });

  final int elapsedSeconds;
  final int periodElapsedSeconds;
  final int remainingSeconds;
  final int periodDurationSeconds;

  bool get expired => remainingSeconds == 0;

  double get progress => periodDurationSeconds == 0
      ? 0
      : (remainingSeconds / periodDurationSeconds).clamp(0, 1).toDouble();

  String get countdown {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

MatchClockValue calculateMatchClock({
  required LiveTickerModel ticker,
  required int periodMinutes,
  required int effectiveElapsedSeconds,
}) {
  final durationSeconds = max(1, periodMinutes) * 60;
  final periodStart = _periodStartElapsed(ticker, durationSeconds);
  final periodElapsed = max(0, effectiveElapsedSeconds - periodStart);

  return MatchClockValue(
    elapsedSeconds: effectiveElapsedSeconds,
    periodElapsedSeconds: periodElapsed,
    remainingSeconds: max(0, durationSeconds - periodElapsed),
    periodDurationSeconds: durationSeconds,
  );
}

int _periodStartElapsed(LiveTickerModel ticker, int periodDurationSeconds) {
  for (final event in ticker.events.reversed) {
    final startsPeriod = event.type == TickerEventType.matchStart ||
        event.type == TickerEventType.periodStart;
    if (startsPeriod && event.period == ticker.currentPeriod) {
      return event.elapsedSeconds;
    }
  }

  return max(0, ticker.currentPeriod - 1) * periodDurationSeconds;
}

String matchPeriodLabel(int currentPeriod, int periodCount) {
  if (periodCount == 2) return '$currentPeriod. Halbzeit';
  if (periodCount == 4) return '$currentPeriod. Viertel';
  return 'Abschnitt $currentPeriod von $periodCount';
}
