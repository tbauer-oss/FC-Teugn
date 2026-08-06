import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/features/matches/matchday_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewport in const [
    Size(320, 568),
    Size(390, 844),
    Size(673, 841),
    Size(841, 673),
    Size(1280, 720),
  ]) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets(
        'squad stays readable at ${viewport.width}x${viewport.height} and $scale',
        (tester) async {
          await _pumpSquad(tester, viewport, scale);

          expect(find.byKey(const ValueKey('squad-responsive-list')),
              findsOneWidget);
          expect(find.text('2 ausgewählt · 3 sichtbar'), findsOneWidget);
          expect(
            tester
                .getSize(find.byKey(const ValueKey('squad-selection-summary')))
                .width,
            greaterThan(100),
          );
          expect(find.text('Alle auswählen'), findsOneWidget);
          expect(find.text('Alle abwählen'), findsOneWidget);
          expect(find.text('Kader verbindlich nominieren'), findsOneWidget);
          expect(find.text('Kader speichern'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('squad recalculates after fold and orientation changes',
      (tester) async {
    await _pumpSquad(tester, const Size(320, 568), 1.5);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(673, 841);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const ValueKey('squad-adaptive-actions')), findsOneWidget);

    tester.view.physicalSize = const Size(841, 673);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('all teams filter reveals E1 and E2 without changing selection',
      (tester) async {
    await _pumpSquad(tester, const Size(320, 568), 1);

    await tester.tap(find.byKey(const ValueKey('squad-team-filter-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle Mannschaften').last);
    await tester.pump();

    expect(find.text('2 ausgewählt · 4 sichtbar'), findsOneWidget);
    await tester.tap(find.text('Alle auswählen'));
    await tester.pump();
    expect(find.text('4 ausgewählt · 4 sichtbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long player name receives readable width on narrow phone',
      (tester) async {
    await _pumpSquad(tester, const Size(320, 568), 1.5);
    await tester.drag(
      find.byKey(const ValueKey('squad-responsive-list')),
      const Offset(0, -360),
    );
    await tester.pump();

    final name = find.text('Anna mit einem außergewöhnlich langen Spielernamen');
    expect(name, findsOneWidget);
    expect(tester.getSize(name).width, greaterThan(100));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSquad(
  WidgetTester tester,
  Size viewport,
  double scale,
) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: MatchSquadTab(
                match: _match(),
                allPlayers: _players(),
                editable: true,
                onSaved: (_) async {},
                onReload: () async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

MatchdayModel _match() => MatchdayModel(
      id: 'match-responsive',
      title: 'FC Teugn · Gegner',
      startAt: DateTime(2026, 8, 15, 10),
      location: 'Sportplatz Teugn',
      teamId: 'team-e1',
      squad: const MatchSquadModel(
        id: 'squad-1',
        members: [
          SquadMemberModel(
            player: MatchPlayer(id: 'p1', name: 'Anna'),
            status: NominationStatus.nominated,
          ),
          SquadMemberModel(
            player: MatchPlayer(id: 'p2', name: 'Max'),
            status: NominationStatus.nominated,
          ),
        ],
      ),
    );

List<PlayerModel> _players() => const [
      PlayerModel(
        id: 'p1',
        teamId: 'team-e1',
        firstName: 'Anna',
        lastName: 'Jackermeyer',
        preferredName: 'Anna mit einem außergewöhnlich langen Spielernamen',
        status: PlayerStatus.active,
        dominantFoot: DominantFoot.both,
        position: 'RM',
        shirtNumber: 3,
        ageGroupCode: 'E',
        teamNumber: 1,
      ),
      PlayerModel(
        id: 'p2',
        teamId: 'team-e1',
        firstName: 'Max',
        lastName: 'Mustermann',
        status: PlayerStatus.active,
        dominantFoot: DominantFoot.right,
        position: 'TW',
        shirtNumber: 1,
        ageGroupCode: 'E',
        teamNumber: 1,
      ),
      PlayerModel(
        id: 'p3',
        teamId: 'team-e1',
        firstName: 'Levin',
        lastName: 'Baumann',
        status: PlayerStatus.active,
        dominantFoot: DominantFoot.left,
        position: 'LM',
        shirtNumber: 7,
        ageGroupCode: 'E',
        teamNumber: 1,
      ),
      PlayerModel(
        id: 'p4',
        teamId: 'team-e2',
        firstName: 'Felix',
        lastName: 'Lorenz',
        status: PlayerStatus.active,
        dominantFoot: DominantFoot.right,
        position: 'IV',
        shirtNumber: 8,
        ageGroupCode: 'E',
        teamNumber: 2,
      ),
    ];
