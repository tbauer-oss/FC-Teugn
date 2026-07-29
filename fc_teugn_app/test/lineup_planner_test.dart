import 'package:fc_teugn_app/core/lineup_planner.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('places the goalkeeper in goal and preserves suitable field roles', () {
    final players = [
      _player('striker', 'Stürmer', 'ST'),
      _player('keeper', 'Torwart', 'TW'),
      _player('right', 'Rechts', 'RV'),
      _player('left', 'Links', 'LV'),
      _player('midfield', 'Mitte', 'ZM'),
      _player('bench', 'Bank', 'RA'),
    ];

    final lineup = planInitialLineup(players: players, fieldSize: 5);

    expect(lineup, hasLength(5));
    expect(
      lineup.singleWhere((position) => position.positionCode == 'TW').player.id,
      'keeper',
    );
    expect(
      lineup.singleWhere((position) => position.positionCode == 'ST').player.id,
      'striker',
    );
    expect(
        lineup.map((position) => position.player.id), isNot(contains('bench')));
  });

  test('never uses a second goalkeeper as an outfield preference', () {
    final players = [
      _player('keeper-1', 'Torwart Eins', 'TW'),
      _player('keeper-2', 'Torwart Zwei', 'TW'),
      _player('field-1', 'Feld Eins', 'IV'),
      _player('field-2', 'Feld Zwei', 'ZM'),
    ];

    final lineup = planInitialLineup(players: players, fieldSize: 3);

    expect(
      lineup.where((position) => position.player.position == 'TW'),
      hasLength(1),
    );
  });
}

MatchPlayer _player(String id, String name, String position) => MatchPlayer(
      id: id,
      name: name,
      position: position,
    );
