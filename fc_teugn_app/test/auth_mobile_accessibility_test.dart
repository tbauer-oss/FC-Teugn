import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/auth/login_page.dart';
import 'package:fc_teugn_app/features/auth/reset_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(320, 568),
  double textScale = 2,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  FlutterSecureStorage.setMockInitialValues({});

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login and password recovery stay usable at 320 px and 200% text',
      (tester) async {
    await _pumpAt(tester, const LoginPage());

    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Passwort vergessen?'));
    await tester.tap(find.text('Passwort vergessen?'));
    await tester.pumpAndSettle();

    expect(find.text('Passwort zurücksetzen'), findsOneWidget);
    expect(find.text('Reset-Link per E-Mail senden'), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline_rounded), findsWidgets);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset form remains readable at 320 px and exposes password help',
      (tester) async {
    await _pumpAt(
      tester,
      const ResetPasswordPage(token: 'one-time-token', requestId: ''),
    );

    expect(find.text('Neues Passwort festlegen'), findsOneWidget);
    expect(find.text('Passwort speichern'), findsOneWidget);
    expect(find.byTooltip('Passwort anzeigen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing email token explains how to request a fresh reset link',
      (tester) async {
    await _pumpAt(
      tester,
      const ResetPasswordPage(token: '', requestId: ''),
    );

    expect(find.textContaining('neue E-Mail'), findsOneWidget);
    expect(find.textContaining('Pushnachricht'), findsNothing);
    expect(find.text('Zur Anmeldung'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
