import 'dart:io';

import 'package:fc_teugn_app/core/app_theme_controller.dart';
import 'package:fc_teugn_app/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('jede Hauptnavigation besitzt weiterhin eine passende App-Route', () {
    final source = File('lib/app.dart').readAsStringSync();
    final destinations = RegExp(r"route:\s*'([^']+)'")
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toSet();
    final routes = RegExp(r"path:\s*'([^']+)'")
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toSet();

    expect(destinations, isNotEmpty);
    expect(destinations.difference(routes), isEmpty);
  });

  test('Navigation verwendet verständliche Aufgabenbereiche', () {
    expect(
      ShellSection.values.map((section) => section.label),
      [
        'Übersicht',
        'Meine Mannschaft',
        'Training & Spielbetrieb',
        'Teamorganisation & Kommunikation',
        'Verein & Verwaltung',
        'Hilfe & Support',
      ],
    );
    expect(
      ShellSection.values.every((section) => section.description.isNotEmpty),
      isTrue,
    );
    expect(
      ShellSection.values
          .map((section) => section.labelFor(ShellAudience.family)),
      [
        'Übersicht',
        'Kinder & Mannschaft',
        'Termine & Spielbetrieb',
        'Kommunikation & Mithelfen',
        'Konto & Datenschutz',
        'Hilfe & Support',
      ],
    );
  });

  test('Meine Mannschaft erkennt untergeordnete Mannschaftsseiten', () {
    const destination = ShellDestination(
      label: 'Meine Mannschaft',
      mobileLabel: 'Team',
      icon: Icons.groups_rounded,
      route: '/trainer/team',
      section: ShellSection.team,
      hint: 'Mannschaft zentral verwalten',
      relatedRoutes: ['/trainer/players'],
    );

    expect(destination.matches('/trainer/team'), isTrue);
    expect(destination.matches('/trainer/players/spieler-1'), isTrue);
    expect(destination.matches('/trainer/matches'), isFalse);
  });

  test('Kurze mobile Bezeichnung kann vom Seitentitel abweichen', () {
    const destination = ShellDestination(
      label: 'Spieler & Kader',
      mobileLabel: 'Team',
      icon: Icons.groups_rounded,
      route: '/trainer/players',
      section: ShellSection.team,
      hint: 'Spielerprofile und Zuordnungen',
    );

    expect(destination.label, 'Spieler & Kader');
    expect(destination.mobileLabel, 'Team');
    expect(destination.section, ShellSection.team);
    expect(destination.hint, isNotEmpty);
  });

  testWidgets('Desktop-Sidebar bleibt bei kompakter Höhe ohne Überlauf',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var refreshCount = 0;
    var homeCount = 0;
    AppThemePreference? selectedTheme;

    final destinations = <ShellDestination>[
      const ShellDestination(
        label: 'Startseite',
        mobileLabel: 'Start',
        icon: Icons.grid_view_rounded,
        route: '/trainer',
        section: ShellSection.overview,
        hint: 'Das Wichtigste auf einen Blick',
      ),
      const ShellDestination(
        label: 'Spieler & Kader',
        icon: Icons.groups_rounded,
        route: '/trainer/players',
        section: ShellSection.team,
        hint: 'Spielerprofile und Zuordnungen',
      ),
      const ShellDestination(
        label: 'Kalender',
        icon: Icons.calendar_month_rounded,
        route: '/trainer/events',
        section: ShellSection.schedule,
        hint: 'Termine, Serien und Rückmeldungen',
      ),
      const ShellDestination(
        label: 'Spiele & Turniere',
        icon: Icons.sports_soccer_rounded,
        route: '/trainer/matches',
        section: ShellSection.schedule,
        hint: 'Spieltage, Kader und Liveticker',
      ),
      const ShellDestination(
        label: 'Training & Planung',
        icon: Icons.fitness_center_rounded,
        route: '/trainer/training',
        section: ShellSection.schedule,
        hint: 'Einheiten, Übungen und Belegung',
      ),
      const ShellDestination(
        label: 'Auswertungen',
        icon: Icons.query_stats_rounded,
        route: '/trainer/statistics',
        section: ShellSection.schedule,
        hint: 'Leistung und Saisonstatistik',
      ),
      const ShellDestination(
        label: 'Nachrichten',
        icon: Icons.forum_rounded,
        route: '/trainer/messages',
        section: ShellSection.communication,
        hint: 'Absprachen im Verein',
      ),
      const ShellDestination(
        label: 'Aufgaben & Material',
        icon: Icons.assignment_turned_in_rounded,
        route: '/trainer/operations',
        section: ShellSection.communication,
        hint: 'Aufgaben, Listen und Ausrüstung',
      ),
      const ShellDestination(
        label: 'Mitglieder & Rechte',
        icon: Icons.manage_accounts_rounded,
        route: '/trainer/approvals',
        section: ShellSection.administration,
        hint: 'Zugänge, Rollen und Freigaben',
      ),
      const ShellDestination(
        label: 'Vereinsverwaltung',
        icon: Icons.account_tree_rounded,
        route: '/trainer/organization',
        section: ShellSection.administration,
        hint: 'Mannschaften und Strukturen',
      ),
      const ShellDestination(
        label: 'Datenschutz & Einwilligungen',
        icon: Icons.shield_outlined,
        route: '/trainer/privacy',
        section: ShellSection.administration,
        hint: 'Daten, Dokumente und Zustimmungen',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              DesktopSidebar(
                title: 'Trainer & Verwaltung',
                destinations: destinations,
                selectedIndex: 0,
                userName: 'Tobias Bauer',
                userRole: 'Systemadministration',
                contextLabel: 'E1-Jugend · FC Teugn',
                seasonLabel: '2026/27',
                onHome: () => homeCount++,
                onSelect: (_) {},
                onLogout: () {},
                onRefresh: () async => refreshCount++,
                onThemePreferenceChanged: (value) => selectedTheme = value,
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('ÜBERSICHT'), findsOneWidget);
    expect(find.text('MEINE MANNSCHAFT'), findsOneWidget);
    expect(find.text('TRAINING & SPIELBETRIEB'), findsOneWidget);
    expect(find.byTooltip('Daten aktualisieren'), findsOneWidget);
    expect(find.byTooltip('Darstellung: System'), findsOneWidget);

    await tester.tap(find.byTooltip('Darstellung: System'));
    await tester.pumpAndSettle();
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('Dunkel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-option-dark')));
    await tester.pumpAndSettle();
    expect(selectedTheme, AppThemePreference.dark);

    await tester.tap(find.byTooltip('Daten aktualisieren'));
    await tester.pumpAndSettle();
    expect(refreshCount, 1);

    await tester.tap(find.byKey(const ValueKey('desktop-home-logo')));
    await tester.pump();
    expect(homeCount, 1);
  });

  testWidgets('Mobiles App-Menü ist kompakt und nach Bereichen gegliedert',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const destinations = <ShellDestination>[
      ShellDestination(
        label: 'Startseite',
        mobileLabel: 'Start',
        icon: Icons.grid_view_rounded,
        route: '/trainer',
        section: ShellSection.overview,
        hint: 'Das Wichtigste auf einen Blick',
      ),
      ShellDestination(
        label: 'Spieler & Kader',
        icon: Icons.groups_rounded,
        route: '/trainer/players',
        section: ShellSection.team,
        hint: 'Spielerprofile und Zuordnungen',
      ),
      ShellDestination(
        label: 'Nachrichten & Umfragen',
        icon: Icons.forum_rounded,
        route: '/trainer/messages',
        section: ShellSection.communication,
        hint: 'Absprachen im Verein',
      ),
      ShellDestination(
        label: 'Mitglieder, Rollen & Zugänge',
        icon: Icons.manage_accounts_rounded,
        route: '/trainer/approvals',
        section: ShellSection.administration,
        hint: 'Zugänge, Rollen und Freigaben',
      ),
    ];

    var homeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileNavigationPanel(
            destinations: destinations,
            location: '/trainer/players',
            contextLabel: 'E1-Jugend · FC Teugn',
            seasonLabel: '2026/27',
            userName: 'Tobias Bauer',
            userRole: 'Systemadministration',
            onHome: () => homeCount++,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('FC TEUGN TALENTS · APP-MENÜ'), findsOneWidget);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Meine Mannschaft'), findsOneWidget);
    expect(find.text('Teamorganisation & Kommunikation'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile-menu-home-logo')));
    await tester.pump();
    expect(homeCount, 1);

    final teamHeading = tester.widget<Container>(
      find.byKey(const ValueKey('mobile-menu-section-header-team')),
    );
    final headingDecoration = teamHeading.decoration! as BoxDecoration;
    expect(headingDecoration.gradient, isA<LinearGradient>());
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile-menu-section-header-team')),
          matching: find.text('BEREICH'),
        ),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Verein & Verwaltung'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Verein & Verwaltung'), findsOneWidget);
    expect(find.text('Mitglieder, Rollen & Zugänge'), findsOneWidget);
    expect(find.byTooltip('Funktion suchen'), findsOneWidget);
    await tester.tap(find.byTooltip('Funktion suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rollen');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Mitglieder, Rollen & Zugänge'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mobiler Kalenderwechsel öffnet die Kalenderroute zuverlässig',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/trainer',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Trainer & Verwaltung',
            destinations: const [
              ShellDestination(
                label: 'Startseite',
                mobileLabel: 'Start',
                icon: Icons.grid_view_rounded,
                route: '/trainer',
                section: ShellSection.overview,
                hint: 'Das Wichtigste auf einen Blick',
              ),
              ShellDestination(
                label: 'Meine Mannschaft',
                mobileLabel: 'Team',
                icon: Icons.groups_rounded,
                route: '/trainer/team',
                section: ShellSection.team,
                hint: 'Mannschaft zentral verwalten',
              ),
              ShellDestination(
                label: 'Kalender',
                icon: Icons.calendar_month_rounded,
                route: '/trainer/events',
                section: ShellSection.schedule,
                hint: 'Termine, Serien und Rückmeldungen',
              ),
              ShellDestination(
                label: 'Spiele & Turniere',
                mobileLabel: 'Spiele',
                icon: Icons.sports_soccer_rounded,
                route: '/trainer/matches',
                section: ShellSection.schedule,
                hint: 'Spieltage, Kader und Liveticker',
              ),
            ],
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/trainer',
              builder: (context, state) => const Text('Startinhalt'),
            ),
            GoRoute(
              path: '/trainer/team',
              builder: (context, state) => const Text('Teaminhalt'),
            ),
            GoRoute(
              path: '/trainer/events',
              builder: (context, state) => const Text('Kalenderinhalt'),
            ),
            GoRoute(
              path: '/trainer/matches',
              builder: (context, state) => const Text('Spielinhalt'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Startinhalt'), findsOneWidget);
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/trainer/events');
    expect(find.text('Kalenderinhalt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kontext-Zurück führt sicher von einer Detailseite zum Bereich',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const destinations = <ShellDestination>[
      ShellDestination(
        label: 'Startseite',
        icon: Icons.grid_view_rounded,
        route: '/trainer',
        section: ShellSection.overview,
        hint: 'Das Wichtigste auf einen Blick',
      ),
      ShellDestination(
        label: 'Spiele & Turniere',
        icon: Icons.sports_soccer_rounded,
        route: '/trainer/matches',
        section: ShellSection.schedule,
        hint: 'Spieltage, Kader und Liveticker',
      ),
    ];
    final router = GoRouter(
      initialLocation: '/trainer/matches/match-1',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Trainer & Verwaltung',
            destinations: destinations,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/trainer',
              builder: (context, state) => const Text('Startinhalt'),
            ),
            GoRoute(
              path: '/trainer/matches',
              builder: (context, state) => const Text('Spielübersicht'),
              routes: [
                GoRoute(
                  path: ':matchId',
                  builder: (context, state) => const Text('Spieldetail'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spieldetail'), findsOneWidget);
    expect(find.byKey(const ValueKey('context-back-button')), findsOneWidget);
    expect(find.text('Zurück zu „Spiele & Turniere“'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('context-back-button')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/trainer/matches');
    expect(find.text('Spielübersicht'), findsOneWidget);
    expect(find.byKey(const ValueKey('context-back-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Mitteilungscenter aus Mehr-Menü bleibt nach dem Schließen geöffnet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const destinations = <ShellDestination>[
      ShellDestination(
        label: 'Startseite',
        mobileLabel: 'Start',
        icon: Icons.grid_view_rounded,
        route: '/trainer',
        section: ShellSection.overview,
        hint: 'Das Wichtigste auf einen Blick',
      ),
      ShellDestination(
        label: 'Meine Mannschaft',
        mobileLabel: 'Team',
        icon: Icons.groups_rounded,
        route: '/trainer/team',
        section: ShellSection.team,
        hint: 'Mannschaft zentral verwalten',
      ),
      ShellDestination(
        label: 'Kalender',
        icon: Icons.calendar_month_rounded,
        route: '/trainer/events',
        section: ShellSection.schedule,
        hint: 'Termine, Serien und Rückmeldungen',
      ),
      ShellDestination(
        label: 'Spiele & Turniere',
        mobileLabel: 'Spiele',
        icon: Icons.sports_soccer_rounded,
        route: '/trainer/matches',
        section: ShellSection.schedule,
        hint: 'Spieltage, Kader und Liveticker',
      ),
      ShellDestination(
        label: 'Nachrichten & Umfragen',
        icon: Icons.forum_rounded,
        route: '/trainer/messages',
        section: ShellSection.communication,
        hint: 'Mitteilungen und persönliche Absprachen',
      ),
    ];

    final router = GoRouter(
      initialLocation: '/trainer',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Trainer & Verwaltung',
            destinations: destinations,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/trainer',
              builder: (context, state) => const Text('Startinhalt'),
            ),
            GoRoute(
              path: '/trainer/team',
              builder: (context, state) => const Text('Teaminhalt'),
            ),
            GoRoute(
              path: '/trainer/events',
              builder: (context, state) => const Text('Kalenderinhalt'),
            ),
            GoRoute(
              path: '/trainer/matches',
              builder: (context, state) => const Text('Spielinhalt'),
            ),
            GoRoute(
              path: '/trainer/messages',
              builder: (context, state) => const Text('Mitteilungsinhalt'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mehr'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Nachrichten & Umfragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nachrichten & Umfragen'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));

    expect(router.routeInformationProvider.value.uri.path, '/trainer/messages');
    expect(find.text('Mitteilungsinhalt'), findsOneWidget);
    expect(find.text('Startinhalt'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
