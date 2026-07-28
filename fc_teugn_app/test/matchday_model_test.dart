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
      'location': 'Waldstadion',
      'matchDetails': {
        'opponent': 'SV Beispiel',
        'isHome': true,
        'status': 'LIVE',
        'durationMinutes': 60,
        'periodMinutes': 30,
        'periodCount': 2,
      },
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
            'elapsedSeconds': 720,
            'ourGoals': 1,
            'theirGoals': 0,
          },
        ],
      },
    });

    expect(match.details?.status, MatchStatus.live);
    expect(match.squad?.lineup?.status, LineupStatus.published);
    expect(match.squad?.lineup?.positions.single.player.name, 'Max Muster');
    expect(match.ticker?.events.single.type, TickerEventType.homeGoal);
    expect(match.ticker?.ourGoals, 1);
  });

  test('converts camel-case enum values to API constants', () {
    expect(apiEnum(LineupStatus.internallyApproved), 'INTERNALLY_APPROVED');
    expect(apiEnum(TickerEventType.matchStart), 'MATCH_START');
  });
}
