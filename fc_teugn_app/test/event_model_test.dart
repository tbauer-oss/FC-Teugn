import 'package:fc_teugn_app/core/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a professional recurring calendar event', () {
    final event = EventModel.fromJson({
      'id': 'event-1',
      'teamId': 'team-1',
      'type': 'TRAINING',
      'category': 'FOOTBALL_FESTIVAL',
      'status': 'SCHEDULED',
      'visibility': 'TEAM',
      'title': 'Festival',
      'startAt': '2026-08-03T16:00:00.000Z',
      'endAt': '2026-08-03T18:00:00.000Z',
      'location': 'Sportplatz',
      'carpoolRequired': true,
      'reminderMinutes': [1440, 120],
      'attendanceFinalized': false,
      'series': {
        'id': 'series-1',
        'frequency': 'CUSTOM',
        'interval': 1,
        'weekdays': [1, 3],
        'until': '2026-09-01T16:00:00.000Z',
      },
      'targetTeams': [
        {
          'team': {
            'id': 'team-1',
            'name': 'E1',
            'ageGroup': {'code': 'E', 'name': 'E-Jugend'},
          },
        },
      ],
      'attachments': [],
      'attendance': [
        {
          'id': 'attendance-1',
          'playerId': 'player-1',
          'status': 'YES',
          'goalkeeperAvailable': true,
          'player': {
            'id': 'player-1',
            'firstName': 'Mia',
            'lastName': 'Muster',
            'position': 'Torwart',
          },
        },
      ],
      'attendanceSummary': {
        'yes': 1,
        'no': 0,
        'maybe': 0,
        'unknown': 3,
        'goalkeeperAvailable': 1,
      },
      'missingAttendance': [],
      'carpoolOffers': [],
      'capabilities': {
        'canManage': true,
        'canRespond': true,
        'canOfferRide': true,
      },
    });

    expect(event.category, EventCategory.footballFestival);
    expect(event.isRecurring, isTrue);
    expect(event.targetTeams.single.label, 'E-Jugend · E1');
    expect(event.attendanceFor('player-1')?.status, AttendanceStatus.yes);
    expect(event.attendanceSummary.goalkeeperAvailable, 1);
    expect(event.capabilities.canManage, isTrue);
  });

  test('serializes local calendar input as UTC and all selected teams', () {
    final data = EventWriteData(
      category: EventCategory.friendlyMatch,
      title: 'Testspiel',
      startAt: DateTime.parse('2026-08-03T18:00:00+02:00'),
      location: 'Teugn',
      teamIds: const ['team-1', 'team-2'],
      visibility: EventVisibility.team,
      homeAway: HomeAway.home,
      recurrence: EventRecurrenceDraft(
        frequency: RecurrenceFrequency.weekly,
        until: DateTime.parse('2026-09-01T18:00:00+02:00'),
      ),
    ).toJson();

    expect(data['category'], 'FRIENDLY_MATCH');
    expect(data['startAt'], '2026-08-03T16:00:00.000Z');
    expect(data['teamIds'], ['team-1', 'team-2']);
    expect(data['homeAway'], 'HOME');
    expect(
      (data['recurrence'] as Map<String, dynamic>)['frequency'],
      'WEEKLY',
    );
  });
}
