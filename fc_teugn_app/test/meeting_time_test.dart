import 'package:fc_teugn_app/core/meeting_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates meeting time before kickoff across the previous day', () {
    final kickoff = DateTime(2026, 9, 12, 0, 30);

    expect(
      meetingTimeBefore(kickoff, 60),
      DateTime(2026, 9, 11, 23, 30),
    );
  });

  test('recognizes supported offsets from an existing meeting time', () {
    final kickoff = DateTime(2026, 9, 12, 10);

    expect(
      standardMeetingOffset(kickoff, DateTime(2026, 9, 12, 9, 15)),
      45,
    );
  });

  test('keeps unusual existing meeting times in exact-time mode', () {
    final kickoff = DateTime(2026, 9, 12, 10);

    expect(
      standardMeetingOffset(kickoff, DateTime(2026, 9, 12, 9, 23)),
      isNull,
    );
  });
}
