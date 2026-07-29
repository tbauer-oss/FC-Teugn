enum TeamGameFormat {
  football3('FOOTBALL_3', 3, 'Fußball 3', '3 gegen 3'),
  football4('FOOTBALL_4', 4, 'Fußball 4', '4 gegen 4'),
  football5('FOOTBALL_5', 5, 'Fußball 5', '5 gegen 5'),
  football7('FOOTBALL_7', 7, 'Fußball 7', '7 gegen 7'),
  football9('FOOTBALL_9', 9, 'Fußball 9', '9 gegen 9'),
  football11('FOOTBALL_11', 11, 'Fußball 11', '11 gegen 11');

  const TeamGameFormat(
    this.apiValue,
    this.playerCount,
    this.name,
    this.strength,
  );

  final String apiValue;
  final int playerCount;
  final String name;
  final String strength;

  String get label => '$name · $strength';

  String get defaultFormation => formations.first;

  List<String> get formations => switch (this) {
        TeamGameFormat.football3 => const ['1-1', '2-0', '1-1-0'],
        TeamGameFormat.football4 => const ['1-2', '2-1', '1-1-1'],
        TeamGameFormat.football5 => const ['1-2-1', '2-2', '1-1-2'],
        TeamGameFormat.football7 => const ['2-3-1', '3-2-1', '3-3'],
        TeamGameFormat.football9 => const ['3-3-2', '3-4-1', '4-3-1'],
        TeamGameFormat.football11 => const ['4-4-2', '4-3-3', '3-5-2'],
      };

  static TeamGameFormat fromApi(Object? value) =>
      TeamGameFormat.values.firstWhere(
        (format) => format.apiValue == value,
        orElse: () => TeamGameFormat.football7,
      );
}

TeamGameFormat suggestedGameFormat(String ageGroupCode) => switch (
      ageGroupCode.toUpperCase()
    ) {
      'G' => TeamGameFormat.football3,
      'F' => TeamGameFormat.football4,
      'E' => TeamGameFormat.football5,
      'D' => TeamGameFormat.football9,
      _ => TeamGameFormat.football11,
    };

List<TeamGameFormat> gameFormatsForAgeGroup(String ageGroupCode) => switch (
      ageGroupCode.toUpperCase()
    ) {
      'G' => const [TeamGameFormat.football3],
      'F' => const [
          TeamGameFormat.football3,
          TeamGameFormat.football4,
          TeamGameFormat.football5,
        ],
      'E' => const [
          TeamGameFormat.football4,
          TeamGameFormat.football5,
          TeamGameFormat.football7,
        ],
      'D' => const [
          TeamGameFormat.football7,
          TeamGameFormat.football9,
        ],
      'C' => const [
          TeamGameFormat.football9,
          TeamGameFormat.football11,
        ],
      _ => const [TeamGameFormat.football11],
    };
