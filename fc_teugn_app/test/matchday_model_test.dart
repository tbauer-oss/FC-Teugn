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
      'capabilities': {'canRatePlayers': true},
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
            'substitutions': [
              {
                'id': 'substitution-1',
                'period': 2,
                'minute': 5,
                'playerInId': 'player-2',
                'playerOutId': 'player-1',
                'positionCode': 'ST',
                'note': 'ST · Hauptposition',
              },
            ],
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
      'playerRatings': [
        {
          'score': 8,
          'updatedAt': '2026-08-12T18:00:00.000Z',
          'player': {
            'id': 'player-1',
            'firstName': 'Max',
            'lastName': 'Muster',
            'shirtNumber': 9,
            'position': 'ST',
          },
          'ratedBy': {'id': 'coach-1', 'name': 'Erika Trainer'},
        },
      ],
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
    expect(
      match.squad?.lineup?.substitutions.single.targetPositionCode,
      'ST',
    );
    expect(match.ticker?.events.single.type, TickerEventType.homeGoal);
    expect(match.ticker?.events.single.period, 1);
    expect(match.ticker?.events.single.scorer?.name, 'Max Muster');
    expect(match.ticker?.events.single.assist?.name, 'Tom Beispiel');
    expect(match.ticker?.ourGoals, 1);
    expect(match.eligiblePlayers.single.displayName, 'Max');
    expect(match.eligiblePlayers.single.position, 'ST');
    expect(match.gameFormat.playerCount, 5);
    expect(match.canRatePlayers, isTrue);
    expect(match.playerRatings.single.score, 8);
    expect(match.playerRatings.single.ratedByName, 'Erika Trainer');
  });

  test('converts camel-case enum values to API constants', () {
    expect(apiEnum(LineupStatus.internallyApproved), 'INTERNALLY_APPROVED');
    expect(apiEnum(TickerEventType.matchStart), 'MATCH_START');
  });

  test('parses compact kit laundry duty and trainer candidates', () {
    final duty = KitLaundryDutyModel.fromJson({
      'eventId': 'match-1',
      'title': 'Testspiel',
      'startAt': '2026-08-19T16:00:00.000Z',
      'status': 'PROPOSED',
      'assignmentSource': 'AUTOMATIC',
      'assignedPlayerId': 'player-1',
      'assignedFamilyLabel': 'Familie Max',
      'eligibleFamilyCount': 8,
      'nominationPublished': true,
      'viewerEligible': true,
      'viewerAssigned': true,
      'canRespond': true,
      'canComplete': false,
      'canManage': true,
      'candidates': [
        {
          'familyKey': 'parent-1:parent-2',
          'playerId': 'player-1',
          'playerNames': ['Max'],
          'guardianNames': ['Erika Muster', 'Tom Muster'],
          'selected': true,
        },
      ],
    });

    expect(duty.status, KitLaundryDutyStatus.proposed);
    expect(duty.viewerAssigned, isTrue);
    expect(duty.candidates.single.familyLabel, 'Familie Max');
    expect(duty.candidates.single.guardianNames, hasLength(2));
  });
}
