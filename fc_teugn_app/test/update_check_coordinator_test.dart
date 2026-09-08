import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/core/app_update/update_check_coordinator.dart';
import 'package:fc_teugn_app/core/app_update/app_release.dart';

void main() {
  test('overlapping checks share one request; manual bypasses passive cooldown',
      () async {
    var calls = 0;
    var now = DateTime(2026);
    final pending = Completer<int?>();
    final checks = UpdateCheckCoordinator(
        check: () {
          calls++;
          return pending.future;
        },
        now: () => now);
    final first = checks.run();
    final second = checks.run(manual: true);
    pending.complete(193);
    expect(await first, 193);
    expect(await second, 193);
    expect(calls, 1);
    await checks.run();
    expect(calls, 1);
    await checks.run(manual: true);
    expect(calls, 2);
    now = now.add(const Duration(minutes: 2));
    await checks.run();
    expect(calls, 3);
  });
  test('failed check can be retried immediately', () async {
    var calls = 0;
    final checks = UpdateCheckCoordinator<int>(check: () async {
      if (++calls == 1) throw Exception('offline');
      return null;
    });
    await expectLater(checks.run(), throwsException);
    expect(await checks.run(), isNull);
    expect(calls, 2);
  });
  test('embedded web build matches the release being built', () {
    final source = File('pubspec.yaml').readAsStringSync();
    expect(
        int.parse(RegExp(r'version: \S+\+(\d+)').firstMatch(source)!.group(1)!),
        appReleaseBuild);
  });
}
