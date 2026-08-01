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
}
