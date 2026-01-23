import 'package:flutter/material.dart';
import '../shared/section_card.dart';

class ParentDashboardPage extends StatelessWidget {
  const ParentDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text(
          'Eltern Dashboard',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        SectionCard(
          title: 'Deine Spieler',
          subtitle: 'Nur zugewiesene Spieler werden hier angezeigt.',
        ),
        SectionCard(
          title: 'Events & Trainings',
          subtitle: 'Teilnahmen für Trainings, Spiele und Events melden.',
        ),
        SectionCard(
          title: 'Spiele',
          subtitle: 'Match-Details und Kaderinformationen einsehen.',
        ),
      ],
    );
  }
}
