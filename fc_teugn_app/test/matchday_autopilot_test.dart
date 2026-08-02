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
    final initialBench = {'bench-wing', 'bench-defence'};
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
