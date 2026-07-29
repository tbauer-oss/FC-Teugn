import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shared/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('metric card acts as a compact shortcut', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 118,
            child: MetricCard(
              label: 'Spieler im Team',
              value: '10',
              icon: Icons.groups_rounded,
              color: AppColors.blue,
              caption: 'Kader öffnen',
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('10'), findsOneWidget);
    expect(find.text('Kader öffnen'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(find.text('Spieler im Team'));
    expect(tapped, isTrue);
  });
}
