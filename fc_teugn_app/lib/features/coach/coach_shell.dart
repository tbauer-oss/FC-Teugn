import 'package:flutter/material.dart';
import 'dashboard/coach_dashboard_page.dart';
import 'players/coach_players_page.dart';
import 'matches/coach_matches_page.dart';
import 'trainings/coach_trainings_page.dart';
import 'events/coach_events_page.dart';

class CoachShell extends StatefulWidget {
  const CoachShell({super.key});

  @override
  State<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends State<CoachShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const CoachDashboardPage(),
      const CoachPlayersPage(),
      const CoachMatchesPage(),
      const CoachTrainingsPage(),
      const CoachEventsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Übersicht'),
          NavigationDestination(icon: Icon(Icons.group), label: 'Spieler'),
          NavigationDestination(icon: Icon(Icons.sports_soccer), label: 'Spiele'),
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Training'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Events'),
        ],
      ),
    );
  }
}
