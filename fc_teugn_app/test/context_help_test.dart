import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shared/context_help.dart';
import 'package:fc_teugn_app/features/shared/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('context help reflects responses, opponents, and publication', () {
    final responses = contextHelpFor(
      'Meine Kinder & Rückmeldungen',
      'Rückmeldungen für alle dir zugeordneten Kinder.',
    );
    expect(responses.steps.join(' '), contains('vielleicht'));
    expect(responses.steps.join(' '), contains('Grund'));
    expect(responses.steps.join(' '), contains('einer Woche'));

    final calendar = contextHelpFor(
      'Vereinskalender',
      'Termine und Rückmeldungen zentral verwalten.',
    );
    expect(calendar.steps.join(' '), contains('🏃 Training'));
    expect(calendar.steps.join(' '), contains('Legende'));

    final messages = contextHelpFor(
      'Nachrichten & Abstimmung',
      'Nachrichten zentral verwalten.',
    );
    expect(messages.steps.join(' '), contains('Direktkontakt'));
    expect(messages.steps.join(' '), contains('30 Tagen'));

    final opponents = contextHelpFor(
      'Liga & Gegner',
      'Gegner verwalten.',
    );
    expect(opponents.steps.join(' '), contains('Vereins-Pool'));
    expect(
      opponents.steps.join(' '),
      contains('ausschließlich Trainer der jeweiligen Jugend'),
    );

    final matchday = contextHelpFor(
      'FC Teugn · SV Saal E1',
      '14.8.2026 · 17:30 Uhr',
    );
    expect(matchday.steps.join(' '), contains('„Mit Trainerteam teilen“'));
    expect(matchday.steps.join(' '), contains('Treffpunktzeit'));
  });

  testWidgets('page help explains the area and opens filtered FAQ',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/trainer/events',
      routes: [
        GoRoute(
          path: '/trainer/events',
          builder: (context, state) => const Scaffold(
            body: PageScaffold(
              title: 'Vereinskalender',
              subtitle: 'Termine und Rückmeldungen zentral verwalten.',
              child: SizedBox(),
            ),
          ),
        ),
        GoRoute(
          path: '/trainer/help',
          builder: (context, state) => Scaffold(
            body: Text('FAQ: ${state.uri.queryParameters['topic']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hilfe zu diesem Bereich'));
    await tester.pumpAndSettle();

    expect(find.text('Hilfe zu diesem Bereich'), findsOneWidget);
    expect(find.text('Vereinskalender'), findsWidgets);
    expect(find.textContaining('Plane Termine'), findsOneWidget);

    await tester.tap(find.text('Ausführliches Hilfe-Center öffnen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('FAQ: Termin Kalender anlegen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
