import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/push/live_match_surface_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final notification is created only on the actual transition', () {
    expect(
      liveMatchSurfaceAction(
        previousStatus: TickerStatus.live,
        currentStatus: TickerStatus.finished,
      ),
      LiveMatchSurfaceAction.update,
    );
    expect(
      liveMatchSurfaceAction(
        previousStatus: null,
        currentStatus: TickerStatus.finished,
      ),
      LiveMatchSurfaceAction.none,
    );
    expect(
      liveMatchSurfaceAction(
        previousStatus: TickerStatus.finished,
        currentStatus: TickerStatus.finished,
      ),
      LiveMatchSurfaceAction.none,
    );
  });

  test('active matches update and reset matches cancel the system surface', () {
    expect(
      liveMatchSurfaceAction(
        previousStatus: null,
        currentStatus: TickerStatus.live,
      ),
      LiveMatchSurfaceAction.update,
    );
    expect(
      liveMatchSurfaceAction(
        previousStatus: TickerStatus.finished,
        currentStatus: TickerStatus.notStarted,
      ),
      LiveMatchSurfaceAction.cancel,
    );
  });
}
