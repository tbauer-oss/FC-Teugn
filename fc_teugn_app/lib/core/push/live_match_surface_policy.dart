import '../models/matchday.dart';

enum LiveMatchSurfaceAction { cancel, update, none }

LiveMatchSurfaceAction liveMatchSurfaceAction({
  required TickerStatus? previousStatus,
  required TickerStatus? currentStatus,
}) {
  if (currentStatus == null || currentStatus == TickerStatus.notStarted) {
    return LiveMatchSurfaceAction.cancel;
  }
  if (currentStatus == TickerStatus.finished) {
    final justFinished = previousStatus != null &&
        previousStatus != TickerStatus.notStarted &&
        previousStatus != TickerStatus.finished;
    return justFinished
        ? LiveMatchSurfaceAction.update
        : LiveMatchSurfaceAction.none;
  }
  return LiveMatchSurfaceAction.update;
}
