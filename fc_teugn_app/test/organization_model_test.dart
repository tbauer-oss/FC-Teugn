import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team profile parses professional master data and staff', () {
    final team = TeamSummary.fromJson({
      'id': 'team-1',
      'name': 'E1',
      'teamNumber': 1,
      'displayName': 'E1-Jugend',
      'shortName': 'E1',
      'level': 'Gruppe',
      'teamType': 'DEVELOPMENT',
      'gender': 'MIXED',
      'gameFormat': 'FOOTBALL_5',
      'customFormations': ['3-1'],
      'formationTemplates': [
        {
          'name': '3-1 · offensiv',
          'baseFormation': '3-1',
          'positions': [
            {
              'positionCode': 'TW',
              'x': .5,
              'y': .92,
              'isGoalkeeper': true,
              'sortOrder': 0,
            },
          ],
        },
      ],
      'birthYears': [2015, 2016],
      'description': 'Ballorientierte Ausbildung',
      'trainingLocation': 'Sportplatz Teugn',
      'trainingTimes': ['Dienstag 17:00–18:30'],
      'seasonStartDate': '2026-08-15T00:00:00.000Z',
      'seasonEndDate': '2027-05-31T00:00:00.000Z',
      'indoorSeasonStartDate': '2026-11-01T00:00:00.000Z',
      'indoorSeasonEndDate': '2027-03-15T00:00:00.000Z',
      'indoorTrainingLocation': 'Mehrzweckhalle Teugn',
      'indoorTrainingTimes': ['Freitag 17:00–18:30'],
      'homeVenue': 'Waldstadion',
      'bfvTeamId': 'bfv-1',
      'dfbnetTeamId': 'dfb-1',
      'bfvTeamUrl': 'https://www.bfv.de/team/e1',
      'photoUrl': 'https://blob.example/signed',
      'isActive': true,
      'staff': [
        {
          'id': 'user-1',
          'name': 'Max Trainer',
          'email': 'trainer@example.de',
          'role': 'COACH',
        },
      ],
      'ageGroup': {'id': 'age-1', 'name': 'E-Jugend', 'code': 'E'},
      'season': {'id': 'season-1', 'name': '2026/27'},
    });

    expect(team.teamType, 'DEVELOPMENT');
    expect(team.teamNumber, 1);
    expect(team.displayName, 'E1-Jugend');
    expect(team.birthYears, [2015, 2016]);
    expect(team.trainingTimes, ['Dienstag 17:00–18:30']);
    expect(team.seasonStartDate?.year, 2026);
    expect(team.seasonEndDate?.month, 5);
    expect(team.indoorTrainingLocation, 'Mehrzweckhalle Teugn');
    expect(team.indoorTrainingTimes, ['Freitag 17:00–18:30']);
    expect(team.staff.single.name, 'Max Trainer');
    expect(team.staff.single.role, 'COACH');
    expect(team.photoUrl, isNotNull);
    expect(team.customFormations, ['3-1']);
    expect(team.formationTemplates.single.name, '3-1 · offensiv');
    expect(
      team.formationTemplates.single.positions.single.positionCode,
      'TW',
    );
    expect(team.formationOptions.first, '3-1');
  });

  test('legacy team responses retain safe defaults', () {
    final team = TeamSummary.fromJson({
      'id': 'team-1',
      'name': 'F1',
      'ageGroup': {'id': 'age-1', 'name': 'F-Jugend', 'code': 'F'},
      'season': {'id': 'season-1', 'name': '2026/27'},
    });

    expect(team.teamType, 'COMPETITIVE');
    expect(team.gender, 'MIXED');
    expect(team.birthYears, isEmpty);
    expect(team.trainingTimes, isEmpty);
    expect(team.staff, isEmpty);
    expect(team.displayName, 'F1-Jugend');
  });
}
