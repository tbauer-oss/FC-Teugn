import 'package:fc_teugn_app/core/matchday_autopilot.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/team_game_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('erstellt eine positionsgerechte Startformation', () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: _players(),
    );

    expect(plan.positions, hasLength(5));
    expect(
      plan.positions
          .singleWhere((position) => position.positionCode == 'TW')
          .player
          .id,
      'keeper',
    );
    expect(
      plan.positions
          .singleWhere((position) => position.positionCode == 'ST')
          .player
          .position,
      'ST',
    );
    expect(
        plan.positions.where((position) => position.isCaptain), hasLength(1));
  });

  test('stellt alle drei Trainerstrategien explizit bereit', () {
    for (final strategy in AutopilotStrategy.values) {
      final plan = buildMatchdayAutopilotPlan(
        match: _match(),
        allPlayers: _players(),
        strategy: strategy,
      );

      expect(plan.strategy, strategy);
      expect(strategy.label, isNotEmpty);
      expect(strategy.description, isNotEmpty);
      expect(plan.substitutions, isNotEmpty);
    }
  });

  test('verteilt alle verfügbaren Einsatzminuten fair', () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: _players(),
    );

    expect(plan.plannedMinutes.values.reduce((a, b) => a + b), 300);
    expect(plan.minuteSpread, lessThanOrEqualTo(15));
  });

  test('plant für alle anfänglichen Ersatzspieler gültige Wechsel', () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: _players(),
    );

    expect(plan.benchCount, 2);
    expect(plan.substitutions.length, greaterThanOrEqualTo(2));
    final starters =
        plan.positions.map((position) => position.player.id).toSet();
    final initialBench = _players()
        .map((player) => player.id)
        .where((playerId) => !starters.contains(playerId))
        .toSet();
    expect(
      plan.substitutions.map((substitution) => substitution.playerInId),
      containsAll(initialBench),
    );
    for (final substitution in plan.substitutions) {
      expect(substitution.period, inInclusiveRange(1, 4));
      expect(substitution.minute, inInclusiveRange(0, 15));
      expect(substitution.playerInId, isNot(substitution.playerOutId));
    }
  });

  test('priorisiert Positionspassung vor bisheriger Einsatzzeit', () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: [
        _player('keeper', 'Levin', 'TW', 1, 300),
        _player('left', 'Anna', 'LV', 3, 50),
        _player('right', 'Andi', 'RV', 4, 50),
        _player('midfield', 'Max', 'ZM', 5, 50),
        _player('striker', 'Lukas', 'ST', 6, 0),
        _player('bench-striker', 'Felix', 'ST', 7, 500),
      ],
    );

    final first = plan.substitutions.first;
    expect(first.playerInId, 'bench-striker');
    expect(first.playerOutId, 'striker');
    expect(first.note, contains('Hauptposition'));
  });

  test('hält Ersatzspieler ohne exakte Position in ihrer taktischen Gruppe',
      () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: [
        _player('keeper', 'Levin', 'TW', 1, 300),
        _player('left', 'Anna', 'LV', 3, 50),
        _player('right', 'Andi', 'RV', 4, 50),
        _player('midfield', 'Max', 'ZM', 5, 50),
        _player('striker', 'Lukas', 'ST', 6, 50),
        _player('bench-attacker', 'Felix', 'OM', 7, 500),
        _player('bench-defender', 'Elias', 'IV', 2, 500),
      ],
    );

    final attackerChange = plan.substitutions.firstWhere(
      (item) => item.playerInId == 'bench-attacker',
    );
    final defenderChange = plan.substitutions.firstWhere(
      (item) => item.playerInId == 'bench-defender',
    );
    expect(attackerChange.playerOutId, isNot(anyOf('left', 'right')));
    expect(defenderChange.playerOutId, anyOf('left', 'right'));
  });

  test('führt Startspieler optional auf ihren ursprünglichen Stammplatz zurück',
      () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: _players(),
      strategy: AutopilotStrategy.positionFidelity,
      restoreStartersToStartingPositions: true,
    );

    final starterIds = plan.positions.map((position) => position.player.id);
    final returns = plan.substitutions.where(
      (substitution) =>
          substitution.note?.contains('Rückkehr auf Stammposition') ?? false,
    );

    expect(plan.restoreStartersToStartingPositions, isTrue);
    expect(returns, isNotEmpty);
    expect(
      returns.every(
        (substitution) => starterIds.contains(substitution.playerInId),
      ),
      isTrue,
    );
  });

  test('kommt ohne Wechselplan aus wenn keine Ersatzspieler vorhanden sind',
      () {
    final plan = buildMatchdayAutopilotPlan(
      match: _match(),
      allPlayers: _players().take(5).toList(),
    );

    expect(plan.canApply, isTrue);
    expect(plan.substitutions, isEmpty);
  });
}

MatchdayModel _match() => MatchdayModel(
      id: 'match-1',
      title: 'FC Teugn · Gegner',
      startAt: DateTime(2026, 8, 15, 10),
      meetingAt: DateTime(2026, 8, 15, 9),
      location: 'Platz 1 unten',
      teamId: 'team-1',
      gameFormat: TeamGameFormat.football5,
      details: const MatchDetailsModel(
        opponent: 'Gegner',
        isHome: true,
        status: MatchStatus.planned,
        durationMinutes: 60,
        periodMinutes: 15,
        periodCount: 4,
      ),
    );

List<PlayerModel> _players() => [
      _player('keeper', 'Levin', 'TW', 1, 300),
      _player('left', 'Anna', 'LV', 3, 260),
      _player('right', 'Andi', 'RV', 4, 280),
      _player('midfield', 'Max', 'ZM', 5, 310),
      _player('striker', 'Lukas', 'ST', 6, 290),
      _player('bench-wing', 'Felix', 'RA', 7, 120),
      _player('bench-defence', 'Elias', 'IV', 2, 150),
    ];

PlayerModel _player(
  String id,
  String name,
  String position,
  int shirtNumber,
  int minutes,
) =>
    PlayerModel(
      id: id,
      firstName: name,
      lastName: 'Teugn',
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
      position: position,
      shirtNumber: shirtNumber,
      minutes: minutes,
      ageGroupCode: 'E',
    );
