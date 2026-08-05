import 'package:fc_teugn_app/core/club_logo.dart';
import 'package:fc_teugn_app/core/loading/loading_controller.dart';
import 'package:fc_teugn_app/core/loading/loading_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parallel operations keep the blocking state active', () {
    final controller = AppLoadingController(
      showDelay: Duration.zero,
      minimumVisibleDuration: Duration.zero,
    );
    final first = controller.start(message: 'Erster Vorgang');
    final second = controller.start(message: 'Zweiter Vorgang');

    expect(controller.blockingVisible, isTrue);
    expect(controller.operationCount, 2);
    expect(controller.blockingOperation?.message, 'Zweiter Vorgang');

    first.finish();
    expect(controller.blockingVisible, isTrue);
    expect(controller.operationCount, 1);

    second.finish();
    expect(controller.blockingVisible, isFalse);
    expect(controller.operationCount, 0);
    controller.dispose();
  });

  test('real item progress is normalized and retained', () {
    final controller = AppLoadingController(
      showDelay: Duration.zero,
      minimumVisibleDuration: Duration.zero,
    );
    final handle = controller.start(
      message: 'Synchronisiert',
      mode: AppLoadingMode.background,
      completedItems: 3,
      totalItems: 10,
    );

    expect(controller.backgroundOperation?.progress, .3);
    handle.update(completedItems: 7, totalItems: 10);
    expect(controller.backgroundOperation?.progress, .7);
    handle.update(progress: 2);
    expect(controller.backgroundOperation?.progress, 1);
    handle.finish();
    controller.dispose();
  });

  test('run always releases the operation after an error', () async {
    final controller = AppLoadingController(
      showDelay: Duration.zero,
      minimumVisibleDuration: Duration.zero,
    );

    await expectLater(
      controller.run<void>(
        message: 'Speichert',
        action: (_) async => throw StateError('Fehler'),
      ),
      throwsStateError,
    );
    expect(controller.hasOperations, isFalse);
    expect(controller.blockingVisible, isFalse);
    controller.dispose();
  });

  test('delay and minimum duration prevent visible flicker', () async {
    final controller = AppLoadingController(
      showDelay: const Duration(milliseconds: 15),
      minimumVisibleDuration: const Duration(milliseconds: 30),
    );
    final handle = controller.start(message: 'Lädt');

    expect(controller.blockingVisible, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.blockingVisible, isTrue);
    handle.finish();
    expect(controller.blockingVisible, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(controller.blockingVisible, isFalse);
    controller.dispose();
  });

  testWidgets('local logo loader waits before becoming visible',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LogoLoadingPanel(message: 'Daten werden geladen …'),
        ),
      ),
    );

    expect(find.byType(ClubLogo), findsNothing);
    await tester.pump(const Duration(milliseconds: 249));
    expect(find.byType(ClubLogo), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ClubLogo), findsOneWidget);
  });

  testWidgets('reduced motion uses a static logo loader', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: LogoLoadingIndicator(
              semanticsLabel: 'Änderungen werden gespeichert',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ClubLogo), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LogoLoadingIndicator),
        matching: find.byType(RotationTransition),
      ),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(RegExp('Änderungen werden gespeichert')),
      findsOneWidget,
    );
  });
}
