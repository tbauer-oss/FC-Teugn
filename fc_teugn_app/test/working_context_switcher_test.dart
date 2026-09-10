import 'dart:async';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shell/working_context_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mobile_audit_fixtures.dart';

Widget host(Future<void> Function(WorkingContextSelection) onSelect,
        {double textScale = 1}) =>
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      isScrollControlled: true,
                      showDragHandle: true,
                      constraints: const BoxConstraints(maxWidth: 640),
                      builder: (context) => ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * .85),
                        child: WorkingContextSwitcher(
                            organization: auditOrganization(twoTeams: true),
                            onSelect: onSelect),
                      ),
                    ),
                    child: const Text('Öffnen'),
                  ))),
    );

void main() {
  testWidgets('one tap selects a team without dropdown or confirmation',
      (tester) async {
    WorkingContextSelection? selected;
    await tester.pumpWidget(host((value) async {
      selected = value;
    }));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.byKey(const ValueKey('switch-team-team-e2')));
    await tester.pumpAndSettle();
    expect(
        selected, (ageGroupId: 'age-e', teamId: 'team-e2', includeAll: false));
    expect(find.byType(WorkingContextSwitcher), findsNothing);
  });

  testWidgets(
      'failed switch stays open and supports retry; duplicate taps are blocked',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(host((value) async {
      calls++;
      if (calls == 1) await pending.future;
    }));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    final team = find.byKey(const ValueKey('switch-team-team-e1'));
    await tester.tap(team);
    await tester.pump();
    await tester.tap(team);
    expect(calls, 1);
    pending.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.text('Wechsel nicht möglich. Bitte erneut versuchen.'),
        findsOneWidget);
    await tester.tap(team);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(WorkingContextSwitcher), findsNothing);
  });

  testWidgets(
      'open chooser reflows between phone and foldable widths at large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host((_) async {}, textScale: 1.5));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    for (final width in [
      320.0,
      360.0,
      375.0,
      390.0,
      412.0,
      430.0,
      650.0,
      850.0,
      320.0
    ]) {
      tester.view.physicalSize = Size(width, 740);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$width px');
      final bounds = tester.getRect(find.byType(WorkingContextSwitcher));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(width));
      expect(bounds.bottom, lessThanOrEqualTo(740));
      await tester.scrollUntilVisible(find.text('Alle Mannschaften'), 80,
          scrollable: find.descendant(
              of: find.byType(WorkingContextSwitcher),
              matching: find.byType(Scrollable)));
      expect(find.text('Alle Mannschaften'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
