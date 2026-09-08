import 'package:fc_teugn_app/core/visible_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'foreground refresh keeps its interval; background work stops and resumes immediately',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    final timer = VisibleRefreshTimer(
        const Duration(seconds: 30), () => calls++,
        repeat: true, now: tester.binding.clock.now);
    addTearDown(timer.dispose);
    await tester.pump(const Duration(seconds: 29));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 20));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 3);
    timer.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 3);
  });

  testWidgets(
      'brief interruption preserves the remaining interval instead of restarting it',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    final timer = VisibleRefreshTimer(
        const Duration(seconds: 30), () => calls++,
        now: tester.binding.clock.now);
    addTearDown(timer.dispose);
    await tester.pump(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 9));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    timer.resume();
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1, reason: 'one-shot invalidation must not fire twice');
  });

  testWidgets('an unobserved provider stops polling until listeners return',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    final timer = VisibleRefreshTimer(
        const Duration(seconds: 15), () => calls++,
        repeat: true, now: tester.binding.clock.now);
    addTearDown(timer.dispose);
    timer.pause();
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 0);
    timer.resume();
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    timer.dispose();
  });
}
