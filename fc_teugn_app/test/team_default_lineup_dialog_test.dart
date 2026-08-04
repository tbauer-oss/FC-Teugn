import 'dart:ui';

import 'package:fc_teugn_app/core/app_theme.dart';
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
      photoUrl: 'https://example.test/levin.jpg',
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

  testWidgets('web layout presents formation as a tactical desk',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: TeamDefaultLineupDialog(team: team, players: players),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-team-management')),
      findsOneWidget,
    );
    expect(find.text('TAKTIKBOARD · STAMMFORMATION'), findsOneWidget);
    expect(find.text('SPIELER & ROLLEN'), findsOneWidget);
    expect(find.text('Startelf'), findsOneWidget);
    expect(find.text('Kapitän'), findsOneWidget);
    expect(find.byKey(const ValueKey('team-manager-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player view keeps standard and offers photo and hover modes',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: TeamDefaultLineupDialog(team: team, players: players),
      ),
    );
    await tester.pumpAndSettle();

    final selector = tester.widget<SegmentedButton<dynamic>>(
      find.byKey(const ValueKey('player-marker-view-selector')),
    );
    expect(selector.selected.single.toString(), contains('standard'));
    expect(
      find.byKey(const ValueKey('formation-player-photo-p1')),
      findsNothing,
    );

    await tester.tap(find.text('Mit Foto'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('formation-player-photo-p1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Hover'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('formation-player-photo-p1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('hover-player-photo-p1')),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('slot-marker-0-TW'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('hover-player-preview-p1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('coach can add and select a custom team formation',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: TeamDefaultLineupDialog(team: team, players: players),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-custom-formation')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-formation-field')),
      '3-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-formation-suffix-field')),
      'offensiv',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Anlegen'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('formation-3-1 · offensiv')),
      findsOneWidget,
    );
    expect(find.text('3-1 · offensiv'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('formation choices remain readable in the product theme',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const TeamDefaultLineupDialog(team: team, players: players),
      ),
    );
    await tester.pumpAndSettle();

    final selected = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('formation-1-2-1')),
    );
    final unselected = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('formation-2-2')),
    );

    expect(selected.color?.resolve({WidgetState.selected}), AppColors.yellow);
    expect(selected.labelStyle?.color, AppColors.black);
    expect(unselected.color?.resolve({}), AppColors.charcoal);
    expect(unselected.labelStyle?.color, Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed slot position is included when saving', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const savedTeam = TeamSummary(
      id: 'team-e1',
      name: 'E1',
      ageGroup: AgeGroupSummary(id: 'age-e', name: 'E-Jugend', code: 'E'),
      seasonName: '2026/27',
      gameFormat: TeamGameFormat.football5,
      defaultLineup: TeamDefaultLineup(
        formation: '2-2',
        positions: [
          TeamDefaultLineupPosition(
            player: TeamDefaultLineupPlayer(
              id: 'p1',
              firstName: 'Levin',
              lastName: 'Torwart',
              status: 'ACTIVE',
            ),
            positionCode: 'TW',
            x: .5,
            y: .92,
            isGoalkeeper: true,
            isCaptain: false,
            sortOrder: 0,
          ),
          TeamDefaultLineupPosition(
            player: TeamDefaultLineupPlayer(
              id: 'p2',
              firstName: 'Anna',
              lastName: 'Abwehr',
              status: 'ACTIVE',
            ),
            positionCode: 'LV',
            x: .28,
            y: .68,
            isGoalkeeper: false,
            isCaptain: false,
            sortOrder: 1,
          ),
          TeamDefaultLineupPosition(
            player: TeamDefaultLineupPlayer(
              id: 'p3',
              firstName: 'Jakob',
              lastName: 'Abwehr',
              status: 'ACTIVE',
            ),
            positionCode: 'RV',
            x: .72,
            y: .68,
            isGoalkeeper: false,
            isCaptain: false,
            sortOrder: 2,
          ),
        ],
      ),
    );
    TeamDefaultLineupDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<TeamDefaultLineupDraft>(
                    context: context,
                    builder: (_) => const TeamDefaultLineupDialog(
                      team: savedTeam,
                      players: players,
                    ),
                  );
                },
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slot-marker-2-RV')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('selected-position-RV')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('selected-position-RV')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IV').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-marker-2-IV')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    final changed = result!.positions.singleWhere(
      (position) => position.playerId == 'p3',
    );
    expect(changed.positionCode, 'IV');
    expect(changed.x, .72);
    expect(changed.y, .68);
    final savedTemplate = result!.formationTemplates.singleWhere(
      (template) => template.name == '2-2',
    );
    expect(savedTemplate.positions[2].positionCode, 'IV');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved seven-a-side lineup opens safely on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const savedTeam = TeamSummary(
      id: 'team-e1',
      name: 'E1',
      ageGroup: AgeGroupSummary(id: 'age-e', name: 'E-Jugend', code: 'E'),
      seasonName: '2026/27',
      gameFormat: TeamGameFormat.football7,
      defaultLineup: TeamDefaultLineup(
        formation: '2-3-1',
        positions: [
          TeamDefaultLineupPosition(
            player: TeamDefaultLineupPlayer(
              id: 'p1',
              firstName: 'Levin',
              lastName: 'Torwart',
              status: 'ACTIVE',
              position: 'TW',
              shirtNumber: 1,
            ),
            positionCode: 'TW',
            x: .5,
            y: .92,
            isGoalkeeper: true,
            isCaptain: false,
            sortOrder: 0,
          ),
          TeamDefaultLineupPosition(
            player: TeamDefaultLineupPlayer(
              id: 'p2',
              firstName: 'Anna',
              lastName: 'Abwehr',
              status: 'ACTIVE',
              position: 'LV',
              shirtNumber: 2,
            ),
            positionCode: 'LV',
            x: .25,
            y: .72,
            isGoalkeeper: false,
            isCaptain: true,
            sortOrder: 1,
          ),
          TeamDefaultLineupPosition(
            player: TeamDefaultLineupPlayer(
              id: 'retired-player',
              firstName: 'Nicht mehr',
              lastName: 'Im Kader',
              status: 'LEFT',
              position: 'RV',
            ),
            positionCode: 'RV',
            x: .75,
            y: .72,
            isGoalkeeper: false,
            isCaptain: false,
            sortOrder: 2,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const TeamDefaultLineupDialog(
          team: savedTeam,
          players: players,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('E1-Jugend · Team-Management'), findsOneWidget);
    expect(find.byKey(const ValueKey('formation-2-3-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-manager-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
