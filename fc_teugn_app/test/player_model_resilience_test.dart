import 'package:fc_teugn_app/core/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player model accepts numeric variants and incomplete optional data',
      () {
    final player = PlayerModel.fromJson({
      'id': 'player-1',
      'teamId': 'team-e1',
      'firstName': 'Max',
      'lastName': 'Muster',
      'shirtNumber': 8.0,
      'passNumber': 'BFV-001234',
      'gender': 'DIVERSE',
      'birthDate': '2015-04-08T00:00:00.000Z',
      'joinedAt': '2022-07-01T00:00:00.000Z',
      'team': {
        'name': 'E1-Jugend',
        'teamNumber': '1',
        'ageGroup': {'code': 'E'},
      },
      'statistics': {
        'goals': 4.0,
        'assists': '3',
        'appearances': null,
        'cleanSheets': 5,
        'cleanSheetEligible': true,
      },
      'statisticsBySeason': [
        {
          'seasonId': 'season-1',
          'seasonName': '2026/27',
          'goals': 2.0,
          'assists': '1',
          'cleanSheets': 3,
        },
      ],
      'medicalProfile': 'nicht verfügbar',
    });

    expect(player.fullName, 'Max Muster');
    expect(player.shirtNumber, 8);
    expect(player.passNumber, 'BFV-001234');
    expect(player.gender, PlayerGender.diverse);
    expect(player.birthDate, DateTime.utc(2015, 4, 8));
    expect(player.joinedAt, DateTime.utc(2022, 7, 1));
    expect(player.teamCode, 'E1');
    expect(player.goals, 4);
    expect(player.assists, 3);
    expect(player.appearances, 0);
    expect(player.cleanSheets, 5);
    expect(player.cleanSheetEligible, isTrue);
    expect(player.statisticsBySeason.single.goals, 2);
    expect(player.statisticsBySeason.single.cleanSheets, 3);
    expect(player.medicalProfile, isNull);
  });

  test('player model still rejects responses without a player id', () {
    expect(
      () => PlayerModel.fromJson({
        'firstName': 'Ohne',
        'lastName': 'Kennung',
      }),
      throwsFormatException,
    );
  });
}
