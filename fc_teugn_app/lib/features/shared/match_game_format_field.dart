import 'package:flutter/material.dart';
import '../../core/team_game_format.dart';

class MatchGameFormatField extends StatelessWidget {
  const MatchGameFormatField(
      {super.key,
      required this.ageGroupCode,
      required this.value,
      required this.onChanged});
  final String ageGroupCode;
  final TeamGameFormat value;
  final ValueChanged<TeamGameFormat> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<TeamGameFormat>(
        key: ValueKey('match-format-$ageGroupCode-${value.apiValue}'),
        initialValue: value,
        isExpanded: true,
        itemHeight: null,
        decoration: InputDecoration(
          labelText: 'Spielform',
          helperMaxLines: 4,
          helperText: ['A', 'B', 'C', 'D'].contains(ageGroupCode.toUpperCase())
              ? 'Kleinere Spielformen je Wettbewerb und Kreisfreigabe. Bei Änderung wird die Aufstellung neu geplant.'
              : 'BFV: je Jahrgang und Spielmodus. Bei Änderung wird die Aufstellung neu geplant.',
        ),
        items: {...gameFormatsForAgeGroup(ageGroupCode), value}
            .map((format) => DropdownMenuItem(
                  value: format,
                  child: Text(
                      '${format.strength}${format.playerCount <= 3 ? ' · ohne Torwart' : format == TeamGameFormat.football4 ? ' · mit Torwart' : ''}'),
                ))
            .toList(),
        onChanged: (format) {
          if (format != null) onChanged(format);
        },
      );
}
