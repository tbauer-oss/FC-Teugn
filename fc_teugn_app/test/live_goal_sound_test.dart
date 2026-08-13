import 'package:fc_teugn_app/core/live_goal_sound.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial ticker history never triggers the goal sound', () {
    final tracker = LiveGoalSoundTracker(fcIsHome: true);
    final initial = _ticker(
      lastSequence: 4,
      events: [_goal(id: 'old-goal', sequence: 4, home: true)],
    );

    expect(tracker.observe(initial), isEmpty);
  });

  test('only a newly arriving FC Teugn goal triggers once', () {
    final tracker = LiveGoalSoundTracker(fcIsHome: true);
    tracker.observe(_ticker(lastSequence: 2));

    final update = _ticker(
      lastSequence: 3,
      events: [_goal(id: 'our-goal', sequence: 3, home: true)],
    );
    expect(tracker.observe(update).map((event) => event.id), ['our-goal']);
    expect(tracker.observe(update), isEmpty);
  });

  test('opponent goals and corrections stay silent', () {
    final tracker = LiveGoalSoundTracker(fcIsHome: true);
    tracker.observe(_ticker(lastSequence: 2));

    expect(
      tracker.observe(
        _ticker(
          lastSequence: 3,
          events: [_goal(id: 'their-goal', sequence: 3, home: false)],
        ),
      ),
      isEmpty,
    );
    expect(
      tracker.observe(
        _ticker(
          lastSequence: 4,
          events: [_correction(id: 'undo', sequence: 4)],
        ),
      ),
      isEmpty,
    );
  });

  test('FC Teugn away goals trigger and ticker resets create a new baseline',
      () {
    final tracker = LiveGoalSoundTracker(fcIsHome: false);
    tracker.observe(_ticker(lastSequence: 6));

    expect(
      tracker
          .observe(
            _ticker(
              lastSequence: 7,
              events: [_goal(id: 'away-goal', sequence: 7, home: false)],
            ),
          )
          .single
          .id,
      'away-goal',
    );
    expect(tracker.observe(_ticker(lastSequence: 0)), isEmpty);
    expect(
      tracker
          .observe(
            _ticker(
              lastSequence: 1,
              events: [_goal(id: 'new-match-goal', sequence: 1, home: false)],
            ),
          )
          .single
          .id,
      'new-match-goal',
    );
  });
}

LiveTickerModel _ticker({
  required int lastSequence,
  List<TickerEventModel> events = const [],
}) =>
    LiveTickerModel(
      status: TickerStatus.live,
      currentPeriod: 1,
      elapsedSeconds: 30,
      ourGoals: 0,
      theirGoals: 0,
      lastSequence: lastSequence,
      events: events,
    );

TickerEventModel _goal({
  required String id,
  required int sequence,
  required bool home,
}) =>
    TickerEventModel(
      id: id,
      sequence: sequence,
      type: home ? TickerEventType.homeGoal : TickerEventType.awayGoal,
      elapsedSeconds: 30,
      ourGoals: 0,
      theirGoals: 0,
    );

TickerEventModel _correction({required String id, required int sequence}) =>
    TickerEventModel(
      id: id,
      sequence: sequence,
      type: TickerEventType.eventRevoked,
      elapsedSeconds: 30,
      ourGoals: 0,
      theirGoals: 0,
    );
