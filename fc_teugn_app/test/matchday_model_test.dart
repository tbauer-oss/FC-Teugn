import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a published matchday with lineup and live ticker', () {
    final match = MatchdayModel.fromJson({
      'id': 'event-1',
      'teamId': 'team-1',
      'title': 'Testspiel',
      'startAt': '2026-08-12T16:00:00.000Z',
      'meetingAt': '2026-08-12T15:00:00.000Z',
      'meetingLocation': 'Vereinsheim Teugn',
      'location': 'Waldstadion',
      'teamGameFormat': 'FOOTBALL_5',
      'teamDefaultFormation': '1-2-1',
      'teamFormationOptions': ['1-2-1', '3-1'],
      'communicationStatus': 'FAMILY_RELEASED',
      'internalPublishedAt': '2026-08-11T10:00:00.000Z',
      'familyReleasedAt': '2026-08-11T11:00:00.000Z',
      'familyReleaseAudience': 'NOMINATED',
      'matchDetails': {
        'opponent': 'SV Beispiel',
        'isHome': true,
        'status': 'LIVE',
        'durationMinutes': 60,
        'periodMinutes': 30,
        'periodCount': 2,
      },
      'eligiblePlayers': [
        {
          'id': 'player-1',
          'teamId': 'team-1',
          'firstName': 'Max',
          'lastName': 'Muster',
          'dominantFoot': 'RIGHT',
          'status': 'ACTIVE',
          'position': 'ST',
          'shirtNumber': 9,
        },
      ],
      'squads': [
        {
          'id': 'squad-1',
          'publishedAt': '2026-08-11T12:00:00.000Z',
          'members': [
            {
              'status': 'NOMINATED',
              'player': {
                'id': 'player-1',
                'firstName': 'Max',
                'lastName': 'Muster',
                'shirtNumber': 9,
              },
            },
          ],
          'lineup': {
            'id': 'lineup-1',
            'formation': '2-3-1',
            'fieldSize': 7,
            'status': 'PUBLISHED',
            'positions': [
              {
                'player': {
                  'id': 'player-1',
                  'firstName': 'Max',
                  'lastName': 'Muster',
                  'shirtNumber': 9,
                },
                'positionCode': 'ST',
                'x': .5,
                'y': .2,
                'period': 1,
                'isStarter': true,
                'isGoalkeeper': false,
                'isCaptain': true,
              },
            ],
          },
        },
      ],
      'liveTicker': {
        'status': 'LIVE',
        'currentPeriod': 1,
        'elapsedSeconds': 720,
        'ourGoals': 1,
        'theirGoals': 0,
        'lastSequence': 2,
        'events': [
          {
            'id': 'ticker-event-1',
            'sequence': 2,
            'type': 'HOME_GOAL',
            'period': 1,
            'elapsedSeconds': 720,
            'ourGoals': 1,
            'theirGoals': 0,
            'scorer': {
              'id': 'player-1',
              'firstName': 'Max',
              'lastName': 'Muster',
            },
            'assist': {
              'id': 'player-2',
              'firstName': 'Tom',
              'lastName': 'Beispiel',
            },
          },
        ],
      },
    });

    expect(match.details?.status, MatchStatus.live);
    expect(match.meetingLocation, 'Vereinsheim Teugn');
    expect(
      match.communicationStatus,
      EventCommunicationStatus.familyReleased,
    );
    expect(match.familyReleaseAudience, 'NOMINATED');
    expect(match.teamDefaultFormation, '1-2-1');
    expect(match.teamFormationOptions, ['1-2-1', '3-1']);
    expect(match.squad?.lineup?.status, LineupStatus.published);
    expect(match.squad?.lineup?.positions.single.player.name, 'Max Muster');
    expect(match.ticker?.events.single.type, TickerEventType.homeGoal);
    expect(match.ticker?.events.single.period, 1);
    expect(match.ticker?.events.single.scorer?.name, 'Max Muster');
    expect(match.ticker?.events.single.assist?.name, 'Tom Beispiel');
    expect(match.ticker?.ourGoals, 1);
    expect(match.eligiblePlayers.single.displayName, 'Max');
    expect(match.eligiblePlayers.single.position, 'ST');
    expect(match.gameFormat.playerCount, 5);
  });

  test('converts camel-case enum values to API constants', () {
    expect(apiEnum(LineupStatus.internallyApproved), 'INTERNALLY_APPROVED');
    expect(apiEnum(TickerEventType.matchStart), 'MATCH_START');
  });
}
