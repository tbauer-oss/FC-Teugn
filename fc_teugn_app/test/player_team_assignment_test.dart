import 'package:fc_teugn_app/core/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player list entries preserve youth and team assignment', () {
    final player = PlayerModel.fromJson({
      'id': 'player-1',
      'teamId': 'team-e1',
      'firstName': 'Max',
      'lastName': 'Muster',
      'dominantFoot': 'RIGHT',
      'status': 'ACTIVE',
      'statistics': {
        'goals': 8,
        'assists': 5,
        'appearances': 20,
        'starts': 17,
        'minutes': 940,
      },
      'statisticsBySeason': [
        {
          'seasonId': 'season-2026',
          'seasonName': '2026/27',
          'goals': 3,
          'assists': 2,
          'appearances': 7,
          'starts': 6,
          'minutes': 330,
        },
      ],
      'team': {
        'id': 'team-e1',
        'name': 'E1',
        'ageGroup': {
          'id': 'age-e',
          'name': 'E-Junioren',
          'code': 'E',
        },
      },
    });

    expect(player.teamId, 'team-e1');
    expect(player.teamName, 'E1');
    expect(player.ageGroupCode, 'E');
    expect(player.minutes, 940);
    expect(player.statisticsBySeason.single.goals, 3);
    expect(player.statisticsBySeason.single.seasonName, '2026/27');
  });
}
