import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/widgets/responsive_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long editor stays scrollable and actionable on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ResponsiveFormDialog(
                    title: 'Stammdaten bearbeiten',
                    subtitle: 'Mobile Bearbeitung',
                    onSave: () {},
                    children: [
                      for (var index = 0; index < 12; index++) ...[
                        TextField(
                          decoration: InputDecoration(
                            labelText: 'Feld ${index + 1}',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Stammdaten bearbeiten'), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Feld 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
