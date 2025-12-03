import 'package:flutter/material.dart';
import 'home/parent_home_page.dart';
import 'matches/parent_matches_page.dart';
import 'trainings/parent_trainings_page.dart';
import 'events/parent_events_page.dart';
import 'profile/parent_profile_page.dart';
import 'player/parent_player_page.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({super.key});

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ParentHomePage(),
      const ParentMatchesPage(),
      const ParentTrainingsPage(),
      const ParentEventsPage(),
      const ParentPlayerPage(),
      const ParentProfilePage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Übersicht'),
          NavigationDestination(icon: Icon(Icons.sports_soccer), label: 'Spiele'),
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Training'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Events'),
          NavigationDestination(icon: Icon(Icons.child_care), label: 'Mein Spieler'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Mein Konto'),
        ],
      ),
    );
  }
}
