import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/features/auth/account_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _user = AppUser(
  id: 'user-1',
  email: 'andreas@example.test',
  name: 'Andreas Wallner',
  firstName: 'Andreas',
  lastName: 'Wallner',
  phone: '+49 123 456789',
  role: UserRole.assistantCoach,
  status: AccountStatus.approved,
  teamId: 'team-e2',
);

void main() {
  for (final size in const [
    Size(320, 720),
    Size(360, 800),
    Size(599, 900),
    Size(1000, 800),
  ]) {
    testWidgets('account settings stay usable at ${size.width.toInt()} px',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AccountSettingsPage(initialUser: _user),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mein Konto'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('save-account-password')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account fields remain visible with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: AccountSettingsPage(initialUser: _user),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('save-account-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('current-password')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
