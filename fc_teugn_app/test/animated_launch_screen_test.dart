import 'package:fc_teugn_app/features/launch/animated_launch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FC-Teugn-Startsequenz bleibt auf einem Handy überlauffrei',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: AnimatedLaunchScreen()),
    );

    expect(find.text('FC TEUGN'), findsOneWidget);
    expect(find.text('JUGENDFUSSBALL'), findsOneWidget);
    expect(find.text('EIN VEREIN. EIN TEAM.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduzierte Animationen werden respektiert', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AnimatedLaunchScreen(),
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 1);
    expect(tester.takeException(), isNull);
  });
}
