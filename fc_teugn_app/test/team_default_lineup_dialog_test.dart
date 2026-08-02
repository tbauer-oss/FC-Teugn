import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/team_game_format.dart';
import 'package:fc_teugn_app/features/organization/team_default_lineup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const team = TeamSummary(
    id: 'team-e1',
    name: 'E1',
    ageGroup: AgeGroupSummary(id: 'age-e', name: 'E-Jugend', code: 'E'),
    seasonName: '2026/27',
    gameFormat: TeamGameFormat.football5,
  );
  const players = [
    PlayerModel(
      id: 'p1',
      firstName: 'Levin',
      lastName: 'Torwart',
      position: 'TW',
      shirtNumber: 1,
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
    ),
    PlayerModel(
      id: 'p2',
      firstName: 'Anna',
      lastName: 'Abwehr',
      position: 'LV',
      shirtNumber: 2,
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.left,
    ),
    PlayerModel(
      id: 'p3',
      firstName: 'Jakob',
      lastName: 'Abwehr',
      position: 'RV',
      shirtNumber: 3,
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
    ),
    PlayerModel(
      id: 'p4',
      firstName: 'Max',
      lastName: 'Mittelfeld',
      position: 'ZM',
      shirtNumber: 8,
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.both,
    ),
    PlayerModel(
      id: 'p5',
      firstName: 'Lukas',
      lastName: 'Sturm',
      position: 'ST',
      shirtNumber: 9,
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
    ),
    PlayerModel(
      id: 'p6',
      firstName: 'Elias',
      lastName: 'Sturm',
      position: 'ST',
      shirtNumber: 11,
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
    ),
  ];

  testWidgets('formation editor remains usable on a phone-sized screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: TeamDefaultLineupDialog(team: team, players: players),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('E1-Jugend · Team-Management'), findsOneWidget);
    expect(find.text('FORMATION'), findsOneWidget);
    expect(find.text('5/5 Spieler'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('formation-2-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-marker-1-LV')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-marker-2-RV')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-marker-4-ST')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Spielerpool'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Spielerpool'), findsOneWidget);
    expect(find.text('1 verfügbar'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('team-manager-scroll')),
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elias'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('slot-marker-4-ST')),
        matching: find.text('Elias'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
