import 'dart:async';

import 'package:fc_teugn_app/core/push/initial_push_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first-start push prompt explains benefits and returns consent',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const InitialPushPromptDialog(),
                );
              },
              child: const Text('Dialog öffnen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dialog öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Pushnachrichten aktivieren?'), findsOneWidget);
    expect(find.text('Termin- und Trainingsänderungen'), findsOneWidget);
    expect(find.text('Aktivieren'), findsOneWidget);

    await tester.tap(find.text('Aktivieren'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('web activation runs directly from the confirmation tap',
      (tester) async {
    var activated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => InitialPushPromptDialog(
                  onActivate: () async => activated = true,
                ),
              ),
              child: const Text('Web-Push öffnen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Web-Push öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aktivieren'));
    await tester.pumpAndSettle();

    expect(activated, isTrue);
    expect(find.text('Pushnachrichten aktivieren?'), findsNothing);
  });

  testWidgets('a stalled browser permission can always be cancelled',
      (tester) async {
    final stalled = Completer<void>();
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => InitialPushPromptDialog(
                    onActivate: () => stalled.future,
                  ),
                );
              },
              child: const Text('Edge-Push öffnen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edge-Push öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aktivieren'));
    await tester.pump();
    expect(find.text('Abbrechen'), findsOneWidget);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('Pushnachrichten aktivieren?'), findsNothing);
  });
}
