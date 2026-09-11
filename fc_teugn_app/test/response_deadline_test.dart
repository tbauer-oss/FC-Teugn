import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shared/response_deadline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('presets calculate exact lead time and can be removed',
      (tester) async {
    final start = DateTime.now().add(const Duration(days: 30));
    DateTime? deadline;
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
          child: StatefulBuilder(
              builder: (context, setState) => ResponseDeadlineField(
                  startAt: start,
                  value: deadline,
                  onChanged: (value) => setState(() => deadline = value))),
        ))));
    for (final hours in [24, 48, 72, 168, 336]) {
      final label =
          hours < 168 ? '$hours h vorher' : '${hours ~/ 24} Tage vorher';
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
      expect(deadline, start.subtract(Duration(hours: hours)));
      expect(find.text('Frist: ${responseDeadlineDate(deadline!)}'),
          findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ohne Frist'));
    await tester.pumpAndSettle();
    expect(deadline, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid cutoff at kickoff is rejected', (tester) async {
    final key = GlobalKey<FormState>();
    final start = DateTime(2027, 1, 12, 18);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Form(
                key: key,
                child: ResponseDeadlineField(
                    startAt: start, value: start, onChanged: (_) {})))));
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Die Rückmeldefrist muss vor dem Spielbeginn liegen.'),
        findsOneWidget);
  });
  testWidgets(
      'open screen locks automatically, supports reopening and disposes timer',
      (tester) async {
    DateTime? deadline = DateTime.now().add(const Duration(seconds: 5));
    Future<void> render() => tester.pumpWidget(MaterialApp(
        home: ResponseDeadlineGate(
            deadline: deadline,
            builder: (_, closed) => Text(closed ? 'closed' : 'open'))));
    await render();
    expect(find.text('open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('closed'), findsOneWidget);
    deadline = null;
    await render();
    expect(find.text('open'), findsOneWidget);
    deadline = DateTime.now().subtract(const Duration(seconds: 1));
    await render();
    expect(find.text('closed'), findsOneWidget);
    deadline = DateTime.now().add(const Duration(days: 1));
    await render();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 360.0, 720.0, 1100.0]) {
    testWidgets('field and notices wrap at $width and enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final start = DateTime.now().add(const Duration(days: 3));
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 1000),
                textScaler: const TextScaler.linear(1.4)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          ResponseDeadlineField(
                              startAt: start,
                              value: start.subtract(const Duration(days: 1)),
                              onChanged: (_) {}),
                          ResponseDeadlineNotice(
                              deadline: DateTime.now()
                                  .subtract(const Duration(days: 1))),
                          ResponseDeadlineNotice(
                              deadline: DateTime.now()
                                  .subtract(const Duration(days: 1)),
                              staffView: true),
                        ])))),
          )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Du kannst als Trainer weiterhin'),
          findsOneWidget);
      expect(find.textContaining('Bitte bei Änderungen direkt Kontakt'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
