import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/widgets/player_team_chip.dart';
import 'package:flutter/material.dart';
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
        'teamNumber': 1,
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
    expect(player.teamCode, 'E1');
    expect(player.minutes, 940);
    expect(player.statisticsBySeason.single.goals, 3);
    expect(player.statisticsBySeason.single.seasonName, '2026/27');
  });

  test('unassigned players remain readable after a team is deleted', () {
    final player = PlayerModel.fromJson({
      'id': 'player-unassigned',
      'clubId': 'club-fc-teugn',
      'teamId': null,
      'firstName': 'Mia',
      'lastName': 'Muster',
      'dominantFoot': 'UNKNOWN',
      'status': 'ACTIVE',
      'team': null,
    });

    expect(player.teamId, isNull);
    expect(player.teamCode, 'Nicht zugeordnet');
    expect(player.teamName, isNull);
    expect(player.ageGroupCode, isNull);
    expect(player.fullName, 'Mia Muster');
  });

  testWidgets('team chip shows the exact youth squad', (tester) async {
    final player = PlayerModel.fromJson({
      'id': 'player-e2',
      'teamId': 'team-e2',
      'firstName': 'Mia',
      'lastName': 'Muster',
      'dominantFoot': 'RIGHT',
      'status': 'ACTIVE',
      'team': {
        'id': 'team-e2',
        'name': 'E2-Jugend',
        'teamNumber': 2,
        'ageGroup': {
          'id': 'age-e',
          'name': 'E-Junioren',
          'code': 'E',
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PlayerTeamChip(player: player))),
    );

    expect(find.text('E2'), findsOneWidget);
  });
}
