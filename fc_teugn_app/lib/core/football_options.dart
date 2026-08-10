import 'package:flutter/material.dart';

import 'models/event.dart';

typedef FootballOption = ({String value, String label});

const footballPositions = <FootballOption>[
  (value: 'TW', label: 'Torwart'),
  (value: 'IV', label: 'Innenverteidigung'),
  (value: 'AV', label: 'Außenverteidigung'),
  (value: 'AB', label: 'Abwehr'),
  (value: 'DM', label: 'Defensives Mittelfeld'),
  (value: 'LM', label: 'Linkes Mittelfeld'),
  (value: 'ZM', label: 'Zentrales Mittelfeld'),
  (value: 'RM', label: 'Rechtes Mittelfeld'),
  (value: 'OM', label: 'Offensives Mittelfeld'),
  (value: 'MF', label: 'Mittelfeld'),
  (value: 'LA', label: 'Linksaußen'),
  (value: 'RA', label: 'Rechtsaußen'),
  (value: 'ST', label: 'Sturm'),
];

const footballCompetitions = <FootballOption>[
  (value: 'Liga', label: 'Ligaspiel'),
  (value: 'Pokal', label: 'Pokalspiel'),
  (value: 'Freundschaftsspiel', label: 'Freundschaftsspiel'),
  (value: 'Turnier', label: 'Turnier'),
  (value: 'Hallenturnier', label: 'Hallenturnier'),
  (value: 'Fußballfestival', label: 'Fußballfestival'),
  (value: 'Testspiel', label: 'Testspiel'),
];

String? footballCompetitionForEvent({
  required EventCategory category,
  String? storedCompetition,
}) {
  final stored = storedCompetition?.trim();
  if (stored != null && stored.isNotEmpty) return stored;

  return switch (category) {
    EventCategory.leagueMatch => 'Liga',
    EventCategory.friendlyMatch => 'Freundschaftsspiel',
    EventCategory.cupMatch => 'Pokal',
    EventCategory.tournament => 'Turnier',
    EventCategory.indoorTournament => 'Hallenturnier',
    EventCategory.footballFestival => 'Fußballfestival',
    _ => null,
  };
}

List<DropdownMenuItem<String?>> footballOptionItems({
  required List<FootballOption> options,
  required String emptyLabel,
  String? currentValue,
  bool showCode = false,
}) {
  final knownValues = options.map((option) => option.value).toSet();
  return [
    DropdownMenuItem<String?>(
      value: null,
      child: Text(emptyLabel),
    ),
    if (currentValue != null &&
        currentValue.trim().isNotEmpty &&
        !knownValues.contains(currentValue))
      DropdownMenuItem<String?>(
        value: currentValue,
        child: Text('$currentValue · bisheriger Eintrag'),
      ),
    for (final option in options)
      DropdownMenuItem<String?>(
        value: option.value,
        child: Text(
          showCode ? '${option.value} · ${option.label}' : option.label,
        ),
      ),
  ];
}
