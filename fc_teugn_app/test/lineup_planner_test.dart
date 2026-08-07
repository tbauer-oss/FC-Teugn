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

  test('builds the selected formation with the expected position rows', () {
    final slots = lineupSlots(7, formation: '3-2-1');

    expect(slots, hasLength(7));
    expect(slots.map((slot) => slot.$3), [
      'TW',
      'LV',
      'IV',
      'RV',
      'LM',
      'RM',
      'ST',
    ]);
  });

  test('uses a matching secondary position before an unrelated player', () {
    final players = [
      _player('keeper', 'Torwart', 'TW'),
      _player('defender', 'Verteidiger', 'IV'),
      _player('midfielder', 'Mittelfeld', 'ZM'),
      const MatchPlayer(
        id: 'versatile',
        name: 'Flexibel',
        position: 'ZM',
        secondaryPosition: 'ST',
      ),
      _player('unrelated', 'Weitere Option', 'RV'),
    ];

    final lineup = planInitialLineup(
      players: players,
      fieldSize: 4,
      formation: '1-1-1',
    );

    expect(
      lineup.singleWhere((position) => position.positionCode == 'ST').player.id,
      'versatile',
    );
  });

  test('reserves exact starters before filling earlier unmatched slots', () {
    final lineup = planInitialLineup(
      players: [
        _player('striker', 'Stürmer', 'ST'),
        _player('defender', 'Verteidiger', 'IV'),
      ],
      fieldSize: 4,
      formation: '1-2',
    );

    expect(
      lineup.singleWhere((position) => position.positionCode == 'ST').player.id,
      'striker',
    );
  });

  test('rates exact, secondary and incompatible formation roles distinctly',
      () {
    expect(lineupFitScore('ST', null, 'ST'), 1000);
    expect(lineupFitScore('ZM', 'ST', 'ST'), 850);
    expect(lineupFitScore('TW', null, 'ST'), -1000);
    expect(lineupFitScore('ST', null, 'IV'), lessThan(0));
    expect(lineupFitScore('ST', null, 'ZM'), greaterThan(0));
    expect(lineupFitScore('IV', null, 'LV'), greaterThan(0));
  });

  test('validates and builds a custom team formation', () {
    expect(isValidFormation('3-1', 5), isTrue);
    expect(isValidFormation('3-1 · offensiv', 5), isTrue);
    expect(isValidFormation('2-1', 5), isFalse);
    expect(isValidFormation('vier-eins', 5), isFalse);

    final slots = lineupSlots(5, formation: '3-1');
    expect(slots.map((slot) => slot.$3), ['TW', 'LV', 'IV', 'RV', 'ST']);
    expect(baseFormationOf('3-1 · offensiv'), '3-1');
    expect(formationName('3-1', 'offensiv'), '3-1 · offensiv');
  });
}

MatchPlayer _player(String id, String name, String position) => MatchPlayer(
      id: id,
      name: name,
      position: position,
    );
