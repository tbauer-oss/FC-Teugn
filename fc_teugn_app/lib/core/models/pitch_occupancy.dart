class PitchOccupancyPlan {
  const PitchOccupancyPlan({
    required this.clubName,
    required this.seasonName,
    required this.teams,
    this.recreationalSchedule,
  });

  final String clubName;
  final String seasonName;
  final List<PitchOccupancyTeam> teams;
  final PitchOccupancyTeam? recreationalSchedule;

  List<PitchOccupancySlot> get slots => [
        for (final team in teams) ...team.slots,
      ];

  factory PitchOccupancyPlan.fromJson(Map<String, dynamic> json) {
    final club = json['club'] as Map<String, dynamic>? ?? const {};
    final season = json['season'] as Map<String, dynamic>? ?? const {};
    return PitchOccupancyPlan(
      clubName: club['name'] as String? ?? 'FC Teugn',
      seasonName: season['name'] as String? ?? '',
      teams: (json['teams'] as List<dynamic>? ?? const [])
          .map(
            (item) => PitchOccupancyTeam.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      recreationalSchedule: json['recreationalSchedule'] == null
          ? null
          : PitchOccupancyTeam.fromJson(
              json['recreationalSchedule'] as Map<String, dynamic>,
            ),
    );
  }
}

class PitchOccupancyTeam {
  const PitchOccupancyTeam({
    required this.id,
    required this.name,
    required this.ageGroupCode,
    required this.location,
    required this.trainingTimes,
  });

  final String id;
  final String name;
  final String ageGroupCode;
  final String location;
  final List<String> trainingTimes;

  String get label => ageGroupCode.isEmpty ? name : '$ageGroupCode · $name';

  List<PitchOccupancySlot> get slots => trainingTimes
      .map((value) => PitchOccupancySlot.tryParse(this, value))
      .whereType<PitchOccupancySlot>()
      .toList();

  factory PitchOccupancyTeam.fromJson(Map<String, dynamic> json) {
    final ageGroup = json['ageGroup'] as Map<String, dynamic>? ?? const {};
    return PitchOccupancyTeam(
      id: json['id'] as String,
      name: json['shortName'] as String? ??
          json['name'] as String? ??
          'Mannschaft',
      ageGroupCode: ageGroup['code'] as String? ?? '',
      location: json['trainingLocation'] as String? ?? 'Platz offen',
      trainingTimes: (json['trainingTimes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class PitchOccupancySlot {
  const PitchOccupancySlot({
    required this.teamId,
    required this.teamLabel,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.location,
    required this.rawValue,
  });

  static const weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  final String teamId;
  final String teamLabel;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String location;
  final String rawValue;

  String get timeLabel => '${_time(startMinute)}–${_time(endMinute)}';

  bool overlaps(PitchOccupancySlot other) =>
      weekday == other.weekday &&
      _normalizedLocation(location) == _normalizedLocation(other.location) &&
      startMinute < other.endMinute &&
      other.startMinute < endMinute;

  static PitchOccupancySlot? tryParse(
    PitchOccupancyTeam team,
    String rawValue,
  ) {
    final dayMatch = RegExp(
      r'(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)',
      caseSensitive: false,
    ).firstMatch(rawValue);
    final timeMatch = RegExp(
      r'(\d{1,2}):(\d{2})(?:\s*(?:-|–|—|bis)\s*(\d{1,2}):(\d{2}))?',
      caseSensitive: false,
    ).firstMatch(rawValue);
    if (dayMatch == null || timeMatch == null) return null;
    final dayName = dayMatch.group(1)!.toLowerCase();
    final weekday =
        weekdays.indexWhere((day) => day.toLowerCase() == dayName) + 1;
    final startHour = int.tryParse(timeMatch.group(1)!) ?? 0;
    final startMinutePart = int.tryParse(timeMatch.group(2)!) ?? 0;
    final startMinute = startHour * 60 + startMinutePart;
    final hasEnd = timeMatch.group(3) != null;
    final endMinute = hasEnd
        ? (int.tryParse(timeMatch.group(3)!) ?? 0) * 60 +
            (int.tryParse(timeMatch.group(4)!) ?? 0)
        : startMinute + 90;
    if (weekday < 1 ||
        startMinute < 0 ||
        startMinute >= 1440 ||
        endMinute <= startMinute ||
        endMinute > 1440) {
      return null;
    }
    return PitchOccupancySlot(
      teamId: team.id,
      teamLabel: team.label,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      location: team.location,
      rawValue: rawValue,
    );
  }

  static String _time(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:'
      '${(value % 60).toString().padLeft(2, '0')}';

  static String _normalizedLocation(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
