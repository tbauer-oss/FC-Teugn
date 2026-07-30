import 'package:fc_teugn_app/core/team_game_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps every supported BFV-style format to its player count', () {
    expect(TeamGameFormat.football3.playerCount, 3);
    expect(TeamGameFormat.football4.playerCount, 4);
    expect(TeamGameFormat.football5.playerCount, 5);
    expect(TeamGameFormat.football7.playerCount, 7);
    expect(TeamGameFormat.football9.playerCount, 9);
    expect(TeamGameFormat.football11.playerCount, 11);
  });

  test('uses age-appropriate defaults while keeping the format editable', () {
    expect(suggestedGameFormat('G'), TeamGameFormat.football3);
    expect(suggestedGameFormat('F'), TeamGameFormat.football4);
    expect(suggestedGameFormat('E'), TeamGameFormat.football5);
    expect(suggestedGameFormat('D'), TeamGameFormat.football9);
    expect(suggestedGameFormat('C'), TeamGameFormat.football11);
  });

  test('offers the BFV child-football models for E youth', () {
    expect(
      gameFormatsForAgeGroup('E'),
      [
        TeamGameFormat.football4,
        TeamGameFormat.football5,
        TeamGameFormat.football7,
      ],
    );
  });

  test('parses API values and falls back safely', () {
    expect(
      TeamGameFormat.fromApi('FOOTBALL_5'),
      TeamGameFormat.football5,
    );
    expect(
      TeamGameFormat.fromApi('UNKNOWN'),
      TeamGameFormat.football7,
    );
  });

  test('provides current BFV match-time defaults per team model', () {
    expect(
      bfvMatchDefaults('E', TeamGameFormat.football7).durationLabel,
      '4 × 15 Minuten',
    );
    expect(
      bfvMatchDefaults('D', TeamGameFormat.football9).durationLabel,
      '2 × 30 Minuten',
    );
    expect(
      bfvMatchDefaults('C', TeamGameFormat.football11).durationLabel,
      '2 × 35 Minuten',
    );
    expect(
      bfvMatchDefaults('A', TeamGameFormat.football11).durationLabel,
      '2 × 45 Minuten',
    );
  });
}
