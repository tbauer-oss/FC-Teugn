import 'package:fc_teugn_app/core/runtime_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production is the safe default build environment', () {
    expect(RuntimeEnvironment.current, AppRuntimeEnvironment.production);
    expect(RuntimeEnvironment.isDemo, isFalse);
  });

  testWidgets('demo strip remains readable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DemoEnvironmentStrip())),
    );

    expect(find.text('TESTUMGEBUNG · KEINE PRODUKTIVDATEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
