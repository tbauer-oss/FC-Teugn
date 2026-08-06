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
      'meetingAt': '2026-08-03T15:00:00.000Z',
      'meetingLocation': 'Vereinsheim Teugn',
      'location': 'Sportplatz',
      'opponentId': 'opponent-1',
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
        'canOpenEmergencyView': true,
        'canDelete': true,
        'canReschedule': true,
      },
    });

    expect(event.category, EventCategory.footballFestival);
    expect(event.isRecurring, isTrue);
    expect(event.targetTeams.single.label, 'E-Jugend · E1');
    expect(event.attendanceFor('player-1')?.status, AttendanceStatus.yes);
    expect(event.attendanceSummary.goalkeeperAvailable, 1);
    expect(event.capabilities.canManage, isTrue);
    expect(event.capabilities.canOpenEmergencyView, isTrue);
    expect(event.capabilities.canDelete, isTrue);
    expect(event.capabilities.canReschedule, isTrue);
    expect(event.meetingLocation, 'Vereinsheim Teugn');
    expect(event.opponentId, 'opponent-1');
  });

  test('serializes local calendar input as UTC and all selected teams', () {
    final data = EventWriteData(
      category: EventCategory.friendlyMatch,
      title: 'Testspiel',
      startAt: DateTime.parse('2026-08-03T18:00:00+02:00'),
      location: 'Teugn',
      meetingLocation: 'Vereinsheim Teugn',
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
    expect(data['meetingLocation'], 'Vereinsheim Teugn');
    expect(
      (data['recurrence'] as Map<String, dynamic>)['frequency'],
      'WEEKLY',
    );
  });

  test('parses the configured match period model', () {
    final details = MatchDetails.fromJson({
      'opponent': 'SV Beispiel',
      'isHome': true,
      'periodCount': 4,
      'periodMinutes': 15,
      'durationMinutes': 60,
      'opponentId': 'opponent-1',
      'leagueId': 'league-1',
    });

    expect(details.periodCount, 4);
    expect(details.periodMinutes, 15);
    expect(details.durationMinutes, 60);
    expect(details.opponentId, 'opponent-1');
    expect(details.leagueId, 'league-1');
  });
}
