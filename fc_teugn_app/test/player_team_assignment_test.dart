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
  });
}
