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
      'birthYears': [2015, 2016],
      'description': 'Ballorientierte Ausbildung',
      'trainingLocation': 'Sportplatz Teugn',
      'trainingTimes': ['Dienstag 17:00–18:30'],
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
    expect(team.staff.single.name, 'Max Trainer');
    expect(team.staff.single.role, 'COACH');
    expect(team.photoUrl, isNotNull);
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
