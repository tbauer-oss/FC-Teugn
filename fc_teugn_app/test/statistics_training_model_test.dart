import 'package:fc_teugn_app/core/models/statistics.dart';
import 'package:fc_teugn_app/core/models/training.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses privacy-aware team and player statistics', () {
    final overview = StatisticsOverview.fromJson({
      'team': {
        'matches': 4,
        'wins': 2,
        'draws': 1,
        'losses': 1,
        'goalsFor': 6,
        'goalsAgainst': 4,
        'winRate': 50,
        'goalsPerMatch': 1.5,
        'form': ['WIN', 'DRAW', 'LOSS', 'WIN'],
      },
      'players': [
        {
          'id': 'p1',
          'name': 'Fiktiver Spieler',
          'shirtNumber': 9,
          'appearances': 4,
          'starts': 3,
          'minutes': 180,
          'goals': 2,
          'assists': 1,
          'career': {
            'appearances': 12,
            'starts': 10,
            'minutes': 580,
            'goals': 7,
            'assists': 4,
          },
        },
      ],
      'matches': [],
      'seasons': [
        {
          'id': 'season-2026',
          'name': '2026/27',
          'startDate': '2026-07-01T00:00:00.000Z',
          'endDate': '2027-06-30T23:59:59.000Z',
          'isActive': true,
        },
      ],
      'selectedSeason': {
        'id': 'season-2026',
        'name': '2026/27',
        'startDate': '2026-07-01T00:00:00.000Z',
        'endDate': '2027-06-30T23:59:59.000Z',
        'isActive': true,
      },
      'privacy': {'individualScope': 'OWN_PLAYERS'},
      'performanceCenter': {
        'teamAverage': 7.5,
        'ratedMatches': 2,
        'unratedMatches': 1,
        'players': [
          {
            'playerId': 'p1',
            'name': 'Fiktiver Spieler',
            'shirtNumber': 9,
            'average': 7.5,
            'ratedMatches': 2,
            'lastScore': 8,
            'trend': 1,
            'recent': [
              {
                'eventId': 'event-1',
                'startAt': '2026-08-12T16:00:00.000Z',
                'opponent': 'SV Beispiel',
                'score': 8,
              }
            ],
          }
        ],
      },
    });

    expect(overview.team.winRate, 50);
    expect(overview.players.single.goals, 2);
    expect(overview.players.single.career?.goals, 7);
    expect(overview.selectedSeason?.name, '2026/27');
    expect(overview.seasons.single.isActive, isTrue);
    expect(overview.individualScope, 'OWN_PLAYERS');
    expect(overview.performanceCenter?.teamAverage, 7.5);
    expect(overview.performanceCenter?.players.single.lastScore, 8);
  });

  test('parses a structured training plan and attendance status', () {
    final training = TrainingModel.fromJson({
      'id': 't1',
      'teamId': 'team1',
      'title': 'Passspiel und Umschalten',
      'startAt': '2026-08-10T16:00:00.000Z',
      'location': 'Trainingsplatz',
      'roster': [
        {
          'id': 'p1',
          'firstName': 'Max',
          'lastName': 'Muster',
          'shirtNumber': 7,
        },
      ],
      'attendance': [
        {
          'trainingStatus': 'LEFT_EARLY',
          'player': {
            'id': 'p1',
            'firstName': 'Max',
            'lastName': 'Muster',
          },
        },
      ],
      'trainingPlan': {
        'focusAreas': ['Passspiel'],
        'durationMinutes': 75,
        'coachAssignments': [
          {
            'user': {
              'id': 'coach-1',
              'name': 'Erika Trainer',
              'role': 'COACH',
            },
          },
        ],
        'items': [
          {
            'title': 'Rondo',
            'phase': 'WARM_UP',
            'durationMinutes': 15,
          },
        ],
      },
    });

    expect(training.plan?.items.single.phase, TrainingPhase.warmUp);
    expect(training.plan?.coaches.single.name, 'Erika Trainer');
    expect(
      training.attendance.single.status,
      TrainingAttendanceStatus.leftEarly,
    );
    expect(training.roster.single.name, 'Max Muster');
    expect(trainingApiEnum(TrainingPhase.gameForm), 'GAME_FORM');
  });
}
