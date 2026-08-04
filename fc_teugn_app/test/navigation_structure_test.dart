import 'dart:io';

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
        'Training & Spieltag',
        'Organisation & Kommunikation',
        'Verein & Verwaltung',
      ],
    );
    expect(
      ShellSection.values.every((section) => section.description.isNotEmpty),
      isTrue,
    );
  });

  test('Team-Zentrale erkennt untergeordnete Mannschaftsseiten', () {
    const destination = ShellDestination(
      label: 'Team-Zentrale',
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
        label: 'Spielbetrieb',
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
                onSelect: (_) {},
                onLogout: () {},
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
    expect(find.text('TRAINING & SPIELTAG'), findsOneWidget);
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
        label: 'Nachrichten & Abstimmung',
        icon: Icons.forum_rounded,
        route: '/trainer/messages',
        section: ShellSection.communication,
        hint: 'Absprachen im Verein',
      ),
      ShellDestination(
        label: 'Mitglieder & Berechtigungen',
        icon: Icons.manage_accounts_rounded,
        route: '/trainer/approvals',
        section: ShellSection.administration,
        hint: 'Zugänge, Rollen und Freigaben',
      ),
    ];

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
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('FC TEUGN TALENTS · APP-MENÜ'), findsOneWidget);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Meine Mannschaft'), findsOneWidget);
    expect(find.text('Organisation & Kommunikation'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Verein & Verwaltung'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Verein & Verwaltung'), findsOneWidget);
    expect(find.text('Mitglieder & Berechtigungen'), findsOneWidget);
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
                label: 'Team-Zentrale',
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
                label: 'Spielbetrieb',
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
        label: 'Team-Zentrale',
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
        label: 'Spielbetrieb',
        mobileLabel: 'Spiele',
        icon: Icons.sports_soccer_rounded,
        route: '/trainer/matches',
        section: ShellSection.schedule,
        hint: 'Spieltage, Kader und Liveticker',
      ),
      ShellDestination(
        label: 'Nachrichten & Abstimmung',
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
    await tester.ensureVisible(find.text('Nachrichten & Abstimmung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nachrichten & Abstimmung'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));

    expect(router.routeInformationProvider.value.uri.path, '/trainer/messages');
    expect(find.text('Mitteilungsinhalt'), findsOneWidget);
    expect(find.text('Startinhalt'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
