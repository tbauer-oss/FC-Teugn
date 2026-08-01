import 'package:fc_teugn_app/features/shared/app_about_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('App-Info zeigt Marke, Version, Build und Entwickler',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'FC Teugn Talents',
      packageName: 'de.fcteugn.talents',
      version: '1.1.1',
      buildNumber: '7',
      buildSignature: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showAppAboutSheet(context),
              child: const Text('App-Info öffnen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('App-Info öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('FC Teugn Talents'), findsOneWidget);
    expect(find.text('Dein Team. Dein Verein. Deine App.'), findsOneWidget);
    expect(find.text('Version 1.1.1 · Build 7'), findsOneWidget);
    expect(find.text('© 2026 FC Teugn'), findsOneWidget);
    expect(find.text('Entwickelt von Tobias Bauer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
