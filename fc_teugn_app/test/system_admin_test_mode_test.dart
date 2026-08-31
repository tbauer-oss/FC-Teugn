import 'dart:io';

import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/system_admin_test_mode.dart';
import 'package:fc_teugn_app/features/trainer/system_admin_test_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user(UserRole role) => AppUser(
      id: 'user-${role.name}',
      email: '${role.name}@example.test',
      name: 'Test ${role.name}',
      role: role,
      status: AccountStatus.approved,
      teamId: 'demo-team',
    );

void main() {
  test('only a system administrator can enable local test mode', () {
    final controller = SystemAdminTestModeController();

    expect(controller.enableFor(_user(UserRole.coach)), isFalse);
    expect(controller.state, isFalse);
    expect(controller.enableFor(_user(UserRole.superAdmin)), isTrue);
    expect(controller.state, isTrue);

    controller.disable();
    expect(controller.state, isFalse);
  });

  test('local test environment has no production API dependency', () {
    final source = File(
      'lib/features/trainer/system_admin_test_environment.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ApiClient')));
    expect(source, isNot(contains('Dio')));
    expect(source, isNot(contains('authProvider')));
    expect(source, isNot(contains('nativePushService')));
  });

  for (final width in [320.0, 390.0, 430.0, 680.0, 860.0]) {
    testWidgets('local test lab remains usable at ${width.toInt()} px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(brightness: Brightness.dark),
          home: const Scaffold(body: SystemAdminTestEnvironmentPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('system-admin-local-test-environment')),
        findsOneWidget,
      );
      expect(find.text('Sicher ausprobieren – ohne Produktivdaten'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('matchday simulation changes only its local score',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SystemAdminTestEnvironmentPage()),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('local-test-area-matchday')),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 : 0'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('local-test-match-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Tor FC Teugn'));
    await tester.pumpAndSettle();

    expect(find.text('1 : 0'), findsOneWidget);
    expect(find.textContaining('Tor für FC Teugn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
