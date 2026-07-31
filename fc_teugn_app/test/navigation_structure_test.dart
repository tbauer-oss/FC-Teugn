import 'package:fc_teugn_app/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Navigation verwendet verständliche Aufgabenbereiche', () {
    expect(
      ShellSection.values.map((section) => section.label),
      [
        'Start',
        'Mannschaft & Sport',
        'Kommunikation & Organisation',
        'Verwaltung & Konto',
      ],
    );
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
        section: ShellSection.team,
        hint: 'Termine, Serien und Rückmeldungen',
      ),
      const ShellDestination(
        label: 'Spielbetrieb',
        icon: Icons.sports_soccer_rounded,
        route: '/trainer/matches',
        section: ShellSection.team,
        hint: 'Spieltage, Kader und Liveticker',
      ),
      const ShellDestination(
        label: 'Training & Planung',
        icon: Icons.fitness_center_rounded,
        route: '/trainer/training',
        section: ShellSection.team,
        hint: 'Einheiten, Übungen und Belegung',
      ),
      const ShellDestination(
        label: 'Auswertungen',
        icon: Icons.query_stats_rounded,
        route: '/trainer/statistics',
        section: ShellSection.team,
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
    expect(find.text('START'), findsOneWidget);
    expect(find.text('MANNSCHAFT & SPORT'), findsOneWidget);
  });
}
