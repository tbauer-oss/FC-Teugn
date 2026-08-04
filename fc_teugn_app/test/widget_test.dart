import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/app.dart';
import 'package:fc_teugn_app/core/providers.dart';

void main() {
  testWidgets('shows the FC Teugn login', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: FCTeugnApp()));
    expect(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
      findsOneWidget,
    );
    expect(find.text('Willkommen zurück'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.bySemanticsLabel('Wappen des FC Teugn'), findsOneWidget);

    final context = tester.element(find.text('Anmelden'));
    final locale = Localizations.localeOf(context);
    final material = MaterialLocalizations.of(context);
    expect(locale.languageCode, 'de');
    expect(material.cancelButtonLabel, 'Abbrechen');
    expect(material.datePickerHelpText, 'Datum auswählen');
  });

  testWidgets('background provider refresh keeps the active router instance',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FCTeugnApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final appBefore = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final routerBefore = appBefore.routerConfig;
    expect(routerBefore, isNotNull);

    container.invalidate(nativePushRegistrationProvider);
    await tester.pump();
    await tester.pumpAndSettle();

    final appAfter = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      identical(routerBefore, appAfter.routerConfig),
      isTrue,
      reason: 'Ein Hintergrund-Refresh darf die sichtbare Navigation nicht '
          'neu aufbauen.',
    );
  });
}
