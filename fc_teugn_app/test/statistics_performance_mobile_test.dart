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
      expect(find.text('Mannschaftsschnitt'), findsOneWidget);
      expect(find.text('Bewertete Spiele'), findsOneWidget);
      expect(find.text('Noch offen'), findsOneWidget);
      final card = find.ancestor(
        of: find.text('Leistungszentrum · trainerintern'),
        matching: find.byType(Card),
      );
      expect(tester.getSize(card).height, lessThan(310));
      expect(tester.takeException(), isNull);
    });
  }
}
