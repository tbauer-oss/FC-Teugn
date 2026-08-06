import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/features/shared/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
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

    await tester.tap(find.text('Ausführliche Hilfe & FAQ öffnen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('FAQ: Termin Kalender anlegen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
