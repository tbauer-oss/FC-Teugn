import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shared/family_responses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('response counts stay legible with large system text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ResponseSummaryPill(
                  label: 'Offen',
                  count: 12,
                  color: AppColors.orange,
                ),
                ResponseSummaryPill(
                  label: 'Zugesagt',
                  count: 3,
                  color: AppColors.teal,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('12'), findsOneWidget);
    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Zugesagt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
