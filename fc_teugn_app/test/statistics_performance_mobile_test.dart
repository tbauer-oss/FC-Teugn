import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/statistics.dart';
import 'package:fc_teugn_app/features/statistics/statistics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in const [320.0, 360.0, 390.0]) {
    testWidgets('performance center stays compact at $width logical pixels',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: const TextScaler.linear(1.2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: performanceCenterCardForTesting(
                  const PerformanceCenter(
                    teamAverage: 7.4,
                    ratedMatches: 4,
                    unratedMatches: 1,
                    players: [],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Leistungszentrum · trainerintern'), findsOneWidget);
      expect(find.text('Trainer'), findsOneWidget);
      expect(find.text('Eltern · anonym'), findsOneWidget);
      expect(find.text('Spiele / offen'), findsOneWidget);
      final card = find.ancestor(
        of: find.text('Leistungszentrum · trainerintern'),
        matching: find.byType(Card),
      );
      expect(tester.getSize(card).height, lessThan(310));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ratings, filters and timeline stay usable at 320 pixels',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final point = PerformanceTimelinePoint(
      eventId: 'match-1',
      startAt: DateTime(2026, 8, 20),
      opponent: 'Testgegner',
      trainerScore: 8,
      parentAverage: 7.5,
      parentRatingCount: 4,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: performanceCenterCardForTesting(
              PerformanceCenter(
                teamAverage: 8,
                parentTeamAverage: 7.5,
                parentRatingCount: 4,
                ratedMatches: 1,
                unratedMatches: 0,
                players: [
                  PlayerPerformance(
                    playerId: 'player-1',
                    name: 'Max Mustermann',
                    average: 8,
                    ratedMatches: 1,
                    trend: 0,
                    recent: const [],
                    position: 'MF',
                    parentAverage: 7.5,
                    parentRatedMatches: 1,
                    parentRatingCount: 4,
                    timeline: [point],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trainer 8.0 / 10'), findsOneWidget);
    expect(find.text('Eltern 7.5 / 10'), findsOneWidget);
    expect(find.text('Stärke'), findsOneWidget);
    expect(find.text('Position'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Max Mustermann'));
    await tester.pumpAndSettle();
    expect(find.text('Entwicklungskurve'), findsOneWidget);
    expect(find.text('Zeitleiste'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
