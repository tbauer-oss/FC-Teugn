import 'package:fc_teugn_app/core/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event payload preserves required fields and UTC timestamps', () {
    final start = DateTime(2026, 9, 12, 10, 30);
    final end = DateTime(2026, 9, 12, 12);
    final payload = EventWriteData(
      category: EventCategory.training,
      title: 'E-Jugend Training',
      startAt: start,
      endAt: end,
      location: 'Sportplatz Teugn',
      teamIds: const ['team-e1'],
    ).toJson();

    expect(payload['category'], 'TRAINING');
    expect(payload['title'], 'E-Jugend Training');
    expect(payload['location'], 'Sportplatz Teugn');
    expect(payload['teamIds'], ['team-e1']);
    expect(DateTime.parse(payload['startAt'] as String).isUtc, isTrue);
    expect(DateTime.parse(payload['endAt'] as String).isUtc, isTrue);
  });

  test('recurring event payload includes recurrence contract', () {
    final payload = EventWriteData(
      category: EventCategory.teamMeeting,
      title: 'Trainerbesprechung',
      startAt: DateTime(2026, 9, 1, 18),
      location: 'Vereinsheim',
      teamIds: const ['team-e1', 'team-e2'],
      recurrence: EventRecurrenceDraft(
        frequency: RecurrenceFrequency.weekly,
        until: DateTime(2026, 12, 15),
      ),
    ).toJson();

    expect(payload['teamIds'], ['team-e1', 'team-e2']);
    expect(
      (payload['recurrence'] as Map<String, dynamic>)['frequency'],
      'WEEKLY',
    );
  });

  test('match payload stores four quarters and calculated duration', () {
    final payload = EventWriteData(
      category: EventCategory.leagueMatch,
      title: 'Punktspiel',
      startAt: DateTime(2026, 9, 12, 10),
      location: 'Sportplatz Teugn',
      teamIds: const ['team-e1'],
      opponent: 'Gegner',
      periodCount: 4,
      periodMinutes: 15,
    ).toJson();

    expect(payload['periodCount'], 4);
    expect(payload['periodMinutes'], 15);
    expect(payload['durationMinutes'], 60);
  });
}
