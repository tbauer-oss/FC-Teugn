import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/matches/competition_management_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

void main() {
  testWidgets('opponent save activates after both required fields are entered',
      (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    OpponentEditorDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<OpponentEditorDraft>(
                  context: context,
                  builder: (context) => const OpponentEditorDialog(),
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

    FilledButton saveButton() =>
        tester.widget(find.widgetWithText(FilledButton, 'Speichern'));

    expect(saveButton().onPressed, isNull);

    await tester.enterText(_field('Verein *'), 'SC Kelheim');
    await tester.pump();
    expect(saveButton().onPressed, isNull);

    await tester.enterText(_field('Jugend / Mannschaft *'), 'E1');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.clubName, 'SC Kelheim');
    expect(result!.teamDesignation, 'E1');
  });

  testWidgets('opponent editor trims values and stays usable on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: OpponentEditorDialog()),
      ),
    );
    await tester.enterText(_field('Verein *'), '  SC Kelheim  ');
    await tester.enterText(_field('Jugend / Mannschaft *'), '  E1  ');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Speichern'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
