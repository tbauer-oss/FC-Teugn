import 'package:flutter/material.dart';
import '../shared/section_card.dart';

class TrainerDashboardPage extends StatelessWidget {
  const TrainerDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text(
          'Trainer Dashboard',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        SectionCard(
          title: 'Pending Accounts',
          subtitle: 'Gebe neue Trainer/Eltern frei oder blockiere Accounts.',
        ),
        SectionCard(
          title: 'Players',
          subtitle: 'Spieler anlegen, bearbeiten und Eltern zuweisen.',
        ),
        SectionCard(
          title: 'Events & Spiele',
          subtitle: 'Trainings, Spiele und Events planen.',
        ),
        SectionCard(
          title: 'Attendance & Squad',
          subtitle: 'Zu-/Absagen verwalten und Kader festlegen.',
        ),
      ],
    );
  }
}
