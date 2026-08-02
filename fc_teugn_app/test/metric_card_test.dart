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

  testWidgets('page scaffold stays readable on a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.25),
          ),
          child: Scaffold(
            body: PageScaffold(
              title: 'Mitglieder & Freigaben',
              subtitle:
                  'Anfragen prüfen, Rollen festlegen und Zugriffe zuordnen.',
              action: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Mitglied anlegen'),
              ),
              child: const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Mobiler Inhalt'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mitglieder & Freigaben'), findsOneWidget);
    expect(find.text('Mitglied anlegen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page scaffold supports a dense mobile match header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.25),
          ),
          child: Scaffold(
            body: PageScaffold(
              title: 'FC Teugn · Besonders langer Gegnername',
              subtitle: '15.8.2026 · 17:00 Uhr · Sportplatz Teugn',
              denseMobileHeader: true,
              child: Text('Spielinhalt'),
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(
      find.text('FC Teugn · Besonders langer Gegnername'),
    );
    final subtitle = tester.widget<Text>(
      find.text('15.8.2026 · 17:00 Uhr · Sportplatz Teugn'),
    );

    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);
    expect(find.text('Spielinhalt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
