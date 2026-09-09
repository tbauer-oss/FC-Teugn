import 'dart:async';

import 'package:fc_teugn_app/core/app_update/app_update_service.dart';
import 'package:fc_teugn_app/features/shared/app_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeUpdates implements AppUpdateClient {
  Future<AppUpdateManifest?> Function() check = () async => null;
  AppUpdateInstallResult result = AppUpdateInstallResult.launched;
  @override
  bool supported = true;
  @override
  Future<AppUpdateManifest?> checkForUpdate() => check();
  @override
  Future<AppUpdateInstallResult> downloadAndInstall(
    AppUpdateManifest manifest, {
    required AppUpdateProgress onProgress,
  }) async =>
      result;
}

final requiredUpdate = AppUpdateManifest(
  schemaVersion: 1,
  versionName: '1.8.1',
  versionCode: 195,
  apkUri: Uri.parse('https://example.test/app.apk'),
  sha256: 'a' * 64,
  fileSize: 100,
  publishedAt: DateTime.utc(2026, 9, 9),
  mandatory: true,
  releaseNotes: const [],
);

void main() {
  testWidgets('checks before building any API-dependent app widget',
      (tester) async {
    final check = Completer<AppUpdateManifest?>();
    final updates = FakeUpdates()..check = () => check.future;
    var builds = 0;
    await tester.pumpWidget(AppUpdateGate(
      client: updates,
      child: Builder(builder: (_) {
        builds++;
        return const MaterialApp(home: Text('Vereinsdaten'));
      }),
    ));
    expect(builds, 0);
    check.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsOneWidget);
  });

  testWidgets(
      'installer launch, cancellation and failed resume keep update blocked',
      (tester) async {
    final updates = FakeUpdates()..check = () async => requiredUpdate;
    await tester.pumpWidget(AppUpdateGate(
      client: updates,
      child: const MaterialApp(home: Text('Vereinsdaten')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsNothing);
    expect(find.text('Später'), findsNothing);
    await tester.tap(find.text('Jetzt aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Jetzt aktualisieren'), findsOneWidget);
    updates.check = () async => throw Exception('offline');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsNothing);
    // A fresh installed-version check, not an installer result, releases the app.
    updates.check = () async => null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsOneWidget);
  });

  testWidgets(
      'initial offline check offers retry without starting authentication',
      (tester) async {
    final updates = FakeUpdates()
      ..check = () async => throw Exception('offline');
    await tester.pumpWidget(AppUpdateGate(
      client: updates,
      child: const MaterialApp(home: Text('Vereinsdaten')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsNothing);
    updates.check = () async => null;
    await tester.tap(find.text('Erneut prüfen'));
    await tester.pumpAndSettle();
    expect(find.text('Vereinsdaten'), findsOneWidget);
  });
}
