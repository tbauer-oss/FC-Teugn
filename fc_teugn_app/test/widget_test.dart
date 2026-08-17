import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/app.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/auth/auth_controller.dart';
import 'package:fc_teugn_app/features/auth/register_page.dart';

class _ControllableAuthController extends AuthController {
  _ControllableAuthController() : super(storage: const FlutterSecureStorage());

  void emit(AuthState next) => state = next;
}

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

  testWidgets(
      'login and registration loading never reopen the initial launch screen',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final authController = _ControllableAuthController();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => authController),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FCTeugnApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
      findsNothing,
    );

    authController.emit(AuthState(loading: true));
    await tester.pump();

    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
      findsNothing,
      reason: 'Eine laufende Anmeldung darf den Startbildschirm nicht erneut '
          'anzeigen.',
    );

    authController.emit(AuthState(error: 'E-Mail oder Passwort ist falsch.'));
    await tester.pump();

    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
      findsNothing,
      reason: 'Auch nach einem falschen Passwort bleibt die Anmeldung '
          'sichtbar.',
    );

    await tester.ensureVisible(find.text('Account registrieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account registrieren'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsOneWidget);

    authController.emit(AuthState(loading: true));
    await tester.pump();

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fc-teugn-talents-web-splash-image')),
      findsNothing,
      reason: 'Das Absenden einer Registrierung darf die Startsequenz nicht '
          'erneut auslösen.',
    );
  });
}
