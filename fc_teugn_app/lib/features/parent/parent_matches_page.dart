import 'package:flutter/material.dart';
import '../shared/section_card.dart';

class ParentMatchesPage extends StatelessWidget {
  const ParentMatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text(
          'Spiele',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        SectionCard(
          title: 'Match Details',
          subtitle: 'Gegner, Anstoßzeiten und Ergebnisse im Blick behalten.',
        ),
        SectionCard(
          title: 'Squad',
          subtitle: 'Sieh dir an, welche Spieler im Kader stehen.',
        ),
      ],
    );
  }
}
