import 'dart:convert';

import 'package:fc_teugn_app/core/push/native_push_service.dart';
import 'package:fc_teugn_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('Android: anmelden, Umfrage und Abwesenheit dauerhaft speichern',
      (tester) async {
    const endpoint = String.fromEnvironment('API_BASE_URL');
    expect(Uri.tryParse(endpoint)?.host,
        anyOf('10.0.2.2', '127.0.0.1', 'localhost'),
        reason:
            'Gerätetest darf ausschließlich die isolierte lokale Test-API verwenden.');
    await nativePushService.markInitialPromptHandled();
    final originalErrorWidgetBuilder = ErrorWidget.builder;
    addTearDown(() => ErrorWidget.builder = originalErrorWidgetBuilder);
    final startup = Stopwatch()..start();
    await app.main();
    Future<void> waitFor(Finder finder,
        {Duration timeout = const Duration(seconds: 60)}) async {
      final deadline = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        final skip = find.text('Überspringen');
        if (skip.evaluate().isNotEmpty) await tester.tap(skip.first);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(finder, findsWidgets);
    }

    Future<void> waitForSavedDialog() async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (find.byType(AlertDialog).evaluate().isNotEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(AlertDialog), findsNothing,
          reason:
              'Speichern muss bestätigt und das Formular geschlossen sein.');
      await tester.pumpAndSettle();
    }

    await waitFor(find.text('Willkommen zurück'));
    startup.stop();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'admin@example.invalid');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'Teugn-Test-2030!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(find.text('Anmelden'));
    await tester.tap(find.text('Anmelden'));
    await waitFor(find.text('Schnellzugriff'));
    GoRouter router() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    router().go('/trainer/talents/polls');
    await waitFor(find.text('Neue Umfrage'));
    await tester.tap(find.text('Neue Umfrage'));
    await tester.pumpAndSettle();
    final question = 'Android-Abnahme ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byType(TextFormField).at(0), question);
    await tester.enterText(
        find.byType(TextFormField).at(1), 'Samstag\nSonntag');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await waitForSavedDialog();
    await waitFor(find.text(question));
    router().go('/trainer/talents/absences');
    await waitFor(find.text('Abwesenheit eintragen'));
    await tester.tap(find.text('Abwesenheit eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).last, 'Android-Gerätetest');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await waitForSavedDialog();
    await waitFor(find.textContaining('Android-Gerätetest'));
    router().go('/trainer/talents/polls');
    await waitFor(find.text(question));
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'platform': 'Android emulator',
      'buildMode': 'debug integration test',
      'flutterStartToLoginMs': startup.elapsedMilliseconds,
      'login': 'passed',
      'pollPersistedAfterReopen': true,
      'absencePersisted': true,
      'physicalDeviceTest': false,
      'pushDeliveryTest': false,
    };
    debugPrint('TALENTS_DEVICE_REPORT ${jsonEncode(binding.reportData)}');
    ErrorWidget.builder = originalErrorWidgetBuilder;
  });
}
