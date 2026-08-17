import 'package:fc_teugn_app/core/models/pitch_occupancy.dart';
import 'package:fc_teugn_app/features/training/pitch_occupancy_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const plan = PitchOccupancyPlan(
    seasonId: 'season-1',
    clubName: 'FC Teugn',
    seasonName: '2026/27',
    teams: [
      PitchOccupancyTeam(
        id: 'e1',
        name: 'E1-Jugend',
        ageGroupCode: 'E',
        location: 'Platz 1 unten',
        trainingTimes: [
          'Dienstag 17:30–19:00 · Platz: Platz 1 unten',
          'Donnerstag 16:30–18:00 · Platz: Platz 2 oben',
        ],
      ),
      PitchOccupancyTeam(
        id: 'd1',
        name: 'D-Jugend',
        ageGroupCode: 'D',
        location: 'Platz 2 oben',
        trainingTimes: ['Mittwoch 17:30–19:00'],
      ),
    ],
  );

  PitchOccupancyPlan planWithCompactDetails() {
    const e1 = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1-Jugend',
      ageGroupCode: 'E',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 17:15–18:30'],
      trainingPartnerIds: ['e2'],
    );
    const e2 = PitchOccupancyTeam(
      id: 'e2',
      name: 'E2-Jugend',
      ageGroupCode: 'E',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 17:15–18:30'],
    );
    const f1 = PitchOccupancyTeam(
      id: 'f1',
      name: 'F1-Jugend',
      ageGroupCode: 'F',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 16:15–17:30'],
    );
    const f2 = PitchOccupancyTeam(
      id: 'f2',
      name: 'F2-Jugend',
      ageGroupCode: 'F',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 16:30–17:30'],
    );
    return PitchOccupancyPlan(
      seasonId: 'season-1',
      clubName: 'FC Teugn',
      seasonName: '2026/27',
      teams: const [e1, e2, f1, f2],
      canManageOccupancy: true,
      approvedConflictKeys: {
        PitchOccupancyConflict.keyFor(f1.slots.single, f2.slots.single),
      },
    );
  }

  testWidgets('mobile occupancy offers list, timeline and table views',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(14),
            child: PitchOccupancyBoard(plan: plan),
          ),
        ),
      ),
    );

    expect(find.text('Liste'), findsOneWidget);
    expect(find.text('Zeitplan'), findsOneWidget);
    expect(find.text('Tabelle'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Zeitplan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Grafische Wochenansicht'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tabelle'));
    await tester.pumpAndSettle();
    expect(find.text('Mannschaft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary occupancy details stay compact and open in sheets',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: PitchOccupancyBoard(plan: planWithCompactDetails()),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('approved-conflicts-button')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('joint-trainings-button')), findsOneWidget);
    expect(find.text('Wieder öffnen'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('approved-conflicts-button')));
    await tester.pumpAndSettle();
    expect(find.text('Abgestimmte Überschneidungen'), findsOneWidget);
    expect(find.text('Wieder öffnen'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('occupancy-details-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('joint-trainings-button')));
    await tester.pumpAndSettle();
    expect(find.text('Gemeinsame Trainings'), findsOneWidget);
    expect(find.text('E · E1-Jugend + E · E2-Jugend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary occupancy details use a dialog on wide screens',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PitchOccupancyBoard(plan: planWithCompactDetails()),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('joint-trainings-button')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Gemeinsame Trainings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
