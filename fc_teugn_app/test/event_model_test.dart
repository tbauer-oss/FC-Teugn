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
      'communicationStatus': 'FAMILY_RELEASED',
      'visibility': 'TEAM',
      'title': 'Festival',
      'startAt': '2026-08-03T16:00:00.000Z',
      'endAt': '2026-08-03T18:00:00.000Z',
      'meetingAt': '2026-08-03T15:00:00.000Z',
      'meetingLocation': 'Vereinsheim Teugn',
      'location': 'Sportplatz',
      'opponentId': 'opponent-1',
      'carpoolRequired': true,
      'familyReleasedAt': '2026-08-01T12:00:00.000Z',
      'familyReleaseAudience': 'NOMINATED',
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
      'carpoolOffers': [
        {
          'id': 'offer-1',
          'driverId': 'parent-1',
          'driver': {'name': 'Max Muster', 'phone': '0123'},
          'seatsTotal': 3,
          'freeSeats': 2,
          'departureLocation': 'Vereinsheim',
          'departureAt': '2026-08-03T15:20:00.000Z',
          'passengers': [],
          'canManage': true,
        },
      ],
      'carpoolNeeds': [
        {
          'id': 'need-1',
          'playerId': 'player-1',
          'player': {'firstName': 'Mia', 'lastName': 'Muster'},
          'status': 'OPEN',
          'note': 'Hin- und Rückfahrt',
          'canCancel': true,
        },
      ],
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
    expect(event.communicationStatus, EventCommunicationStatus.familyReleased);
    expect(
      event.familyReleasedAt,
      DateTime.parse('2026-08-01T12:00:00.000Z').toLocal(),
    );
    expect(event.familyReleaseAudience, 'NOMINATED');
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
    expect(event.carpoolOffers.single.freeSeats, 2);
    expect(event.carpoolNeeds.single.playerName, 'Mia Muster');
    expect(event.carpoolNeeds.single.status, CarpoolNeedStatus.open);
    expect(event.carpoolNeeds.single.canCancel, isTrue);
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

  test('parses a tournament container with independent fixtures', () {
    final event = EventModel.fromJson({
      'id': 'tournament-1',
      'teamId': 'team-1',
      'type': 'MATCH',
      'category': 'TOURNAMENT',
      'status': 'SCHEDULED',
      'communicationStatus': 'FAMILY_RELEASED',
      'visibility': 'TEAM',
      'title': 'Sommercup',
      'startAt': '2026-08-22T08:00:00.000Z',
      'endAt': '2026-08-22T15:00:00.000Z',
      'location': 'Kelheim',
      'targetTeams': [],
      'attachments': [],
      'attendance': [],
      'missingAttendance': [],
      'carpoolOffers': [],
      'carpoolNeeds': [],
      'tournamentFixtures': [
        {
          'id': 'fixture-1',
          'parentTournamentId': 'tournament-1',
          'title': 'Sommercup · ATSV Kelheim E1',
          'startAt': '2026-08-22T08:30:00.000Z',
          'endAt': '2026-08-22T08:40:00.000Z',
          'location': 'Kelheim',
          'status': 'SCHEDULED',
          'communicationStatus': 'FAMILY_RELEASED',
          'familyReleasedAt': '2026-08-20T12:00:00.000Z',
          'matchDetails': {
            'opponent': 'ATSV Kelheim E1',
            'isHome': true,
            'competition': 'Turnierspiel',
            'periodCount': 1,
            'periodMinutes': 10,
            'durationMinutes': 10,
          },
        },
      ],
      'capabilities': <String, dynamic>{},
    });

    expect(event.category.isTournament, isTrue);
    expect(event.matchDetails, isNull);
    expect(event.tournamentFixtures, hasLength(1));
    expect(
      event.tournamentFixtures.single.matchDetails?.opponent,
      'ATSV Kelheim E1',
    );
  });
}
