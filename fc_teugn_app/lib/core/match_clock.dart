import 'dart:math';

import 'models/matchday.dart';

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
