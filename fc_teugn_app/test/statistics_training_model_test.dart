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
        },
      ],
      'matches': [],
      'privacy': {'individualScope': 'OWN_PLAYERS'},
    });

    expect(overview.team.winRate, 50);
    expect(overview.players.single.goals, 2);
    expect(overview.individualScope, 'OWN_PLAYERS');
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
    expect(
      training.attendance.single.status,
      TrainingAttendanceStatus.leftEarly,
    );
    expect(training.roster.single.name, 'Max Muster');
    expect(trainingApiEnum(TrainingPhase.gameForm), 'GAME_FORM');
  });
}
