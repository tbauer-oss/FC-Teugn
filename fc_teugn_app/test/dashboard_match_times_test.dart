import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shared/modern_dashboard_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester,
      {DateTime? meeting, double width = 360, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
            padding: const EdgeInsets.all(12),
            child: ModernDashboardEventCard(
                date: DateTime(2026, 9, 12, 17, 30),
                isMatch: true,
                meetingAt: meeting,
                title: 'FC Teugn E1 – TSV Langquaid E1',
                location: 'Waldstadion',
                icon: Icons.sports_soccer,
                accent: Colors.blue,
                onTap: () {}),
          ))),
        )));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 430.0, 720.0, 1100.0]) {
    for (final scale in [1.0, 1.4]) {
      testWidgets('match times readable at $width px and $scale text scale',
          (tester) async {
        await pumpCard(tester,
            meeting: DateTime(2026, 9, 12, 16, 45), width: width, scale: scale);
        for (final label in ['Beginn 17:30 Uhr', 'Treffpunkt 16:45 Uhr']) {
          final found = find.text(label);
          expect(found, findsOneWidget);
          final text = tester.widget<Text>(found);
          expect(text.style!.fontSize, greaterThanOrEqualTo(13));
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(text.maxLines, isNull);
          expect(tester.getRect(found).right, lessThanOrEqualTo(width));
        }
        expect(find.text('FC Teugn E1 – TSV Langquaid E1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('does not invent missing meeting time', (tester) async {
    await pumpCard(tester);
    expect(find.text('Beginn 17:30 Uhr'), findsOneWidget);
    expect(find.textContaining('Treffpunkt'), findsNothing);
  });
  testWidgets('meeting on previous day includes its date', (tester) async {
    await pumpCard(tester, meeting: DateTime(2026, 9, 11, 18));
    expect(find.text('Treffpunkt 11.9. · 18:00 Uhr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
