import 'package:flutter/material.dart';
import '../shared/section_card.dart';

class TrainerMatchesPage extends StatelessWidget {
  const TrainerMatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text(
          'Match Details & Squad',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        SectionCard(
          title: 'Match Details',
          subtitle: 'Bearbeite Gegner, Wettbewerb und Ergebnis zu Match-Events.',
        ),
        SectionCard(
          title: 'Squad Planung',
          subtitle: 'Kader + Formation für ein Spiel festlegen.',
        ),
      ],
    );
  }
}
