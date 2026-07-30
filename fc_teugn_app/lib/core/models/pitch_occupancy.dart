enum PitchOccupancySlotKind { training, matchday }

class PitchOccupancyPlan {
  const PitchOccupancyPlan({
    required this.seasonId,
    required this.clubName,
    required this.seasonName,
    required this.teams,
    this.indoor = false,
    this.recreationalSchedule,
    this.seniorSchedule,
    this.approvedConflictKeys = const {},
    this.canManageOccupancy = false,
    this.specialEntries = const [],
  });

  final String seasonId;
  final String clubName;
  final String seasonName;
  final List<PitchOccupancyTeam> teams;
  final bool indoor;
  final PitchOccupancyTeam? recreationalSchedule;
  final PitchOccupancyTeam? seniorSchedule;
  final Set<String> approvedConflictKeys;
  final bool canManageOccupancy;
  final List<IndoorOccupancyEntry> specialEntries;

  List<PitchOccupancySlot> get slots => [
        for (final team in teams) ...team.slots,
      ];

  List<PitchOccupancyConflict> get conflicts {
    final trainingSlots = slots
        .where((slot) => slot.kind == PitchOccupancySlotKind.training)
        .toList();
    final result = <PitchOccupancyConflict>[];
    for (var first = 0; first < trainingSlots.length; first++) {
      for (var second = first + 1; second < trainingSlots.length; second++) {
        final left = trainingSlots[first];
        final right = trainingSlots[second];
        if (left.teamId == right.teamId ||
            !left.overlaps(right) ||
            teamsTrainTogether(left.teamId, right.teamId)) {
          continue;
        }
        final key = PitchOccupancyConflict.keyFor(left, right);
        result.add(
          PitchOccupancyConflict(
            key: key,
            first: left,
            second: right,
            approved: approvedConflictKeys.contains(key),
          ),
        );
      }
    }
    return result;
  }

  bool teamsTrainTogether(String firstTeamId, String secondTeamId) {
    final first = teams.where((team) => team.id == firstTeamId).firstOrNull;
    final second = teams.where((team) => team.id == secondTeamId).firstOrNull;
    return first?.trainingPartnerIds.contains(secondTeamId) == true ||
        second?.trainingPartnerIds.contains(firstTeamId) == true;
  }

  factory PitchOccupancyPlan.fromJson(Map<String, dynamic> json) {
    final club = json['club'] as Map<String, dynamic>? ?? const {};
    final season = json['season'] as Map<String, dynamic>? ?? const {};
    return PitchOccupancyPlan(
      seasonId: season['id'] as String? ?? '',
      clubName: club['name'] as String? ?? 'FC Teugn',
      seasonName: season['name'] as String? ?? '',
      indoor: json['mode'] == 'INDOOR',
      teams: (json['teams'] as List<dynamic>? ?? const [])
          .map((item) =>
              PitchOccupancyTeam.fromJson(item as Map<String, dynamic>))
          .toList(),
      recreationalSchedule: json['recreationalSchedule'] == null
          ? null
          : PitchOccupancyTeam.fromJson(
              json['recreationalSchedule'] as Map<String, dynamic>,
            ),
      seniorSchedule: json['seniorSchedule'] == null
          ? null
          : PitchOccupancyTeam.fromJson(
              json['seniorSchedule'] as Map<String, dynamic>,
            ),
      approvedConflictKeys:
          (json['approvedConflictKeys'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet(),
      canManageOccupancy: json['canManageOccupancy'] as bool? ?? false,
      specialEntries: (json['specialEntries'] as List<dynamic>? ?? const [])
          .map(
            (item) => IndoorOccupancyEntry.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class IndoorOccupancyEntry {
  const IndoorOccupancyEntry({
    required this.id,
    required this.title,
    required this.location,
    required this.startAt,
    required this.endAt,
    this.notes,
    this.isRecurring = false,
    this.recurrenceWeekdays = const [],
    this.recurrenceIntervalWeeks = 1,
    this.recurrenceUntil,
  });

  final String id;
  final String title;
  final String location;
  final DateTime startAt;
  final DateTime endAt;
  final String? notes;
  final bool isRecurring;
  final List<int> recurrenceWeekdays;
  final int recurrenceIntervalWeeks;
  final DateTime? recurrenceUntil;

  factory IndoorOccupancyEntry.fromJson(Map<String, dynamic> json) =>
      IndoorOccupancyEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Sonderbelegung',
        location: json['location'] as String? ?? 'Halle',
        startAt: DateTime.parse(json['startAt'] as String).toLocal(),
        endAt: DateTime.parse(json['endAt'] as String).toLocal(),
        notes: json['notes'] as String?,
        isRecurring: json['isRecurring'] as bool? ?? false,
        recurrenceWeekdays:
            (json['recurrenceWeekdays'] as List<dynamic>? ?? const [])
                .whereType<num>()
                .map((value) => value.toInt())
                .toList(),
        recurrenceIntervalWeeks: json['recurrenceIntervalWeeks'] as int? ?? 1,
        recurrenceUntil: DateTime.tryParse(
          json['recurrenceUntil'] as String? ?? '',
        )?.toLocal(),
      );
}

class PitchOccupancyTeam {
  const PitchOccupancyTeam({
    required this.id,
    required this.name,
    required this.ageGroupCode,
    required this.location,
    required this.trainingTimes,
    this.trainingPartnerIds = const [],
    this.matchdayTimes = const [],
  });

  final String id;
  final String name;
  final String ageGroupCode;
  final String location;
  final List<String> trainingTimes;
  final List<String> trainingPartnerIds;
  final List<String> matchdayTimes;

  String get label => ageGroupCode.isEmpty ? name : '$ageGroupCode · $name';
  String get locationLabel {
    final locations = slots
        .where((slot) => slot.kind == PitchOccupancySlotKind.training)
        .map((slot) => slot.location)
        .toSet();
    if (locations.isEmpty) return location;
    if (locations.length == 1) return locations.single;
    return 'Unterschiedliche Plätze';
  }

  List<PitchOccupancySlot> get slots => [
        ...trainingTimes
            .map(
              (value) => PitchOccupancySlot.tryParse(
                this,
                value,
                PitchOccupancySlotKind.training,
              ),
            )
            .whereType<PitchOccupancySlot>(),
        ...matchdayTimes
            .map(
              (value) => PitchOccupancySlot.tryParse(
                this,
                value,
                PitchOccupancySlotKind.matchday,
              ),
            )
            .whereType<PitchOccupancySlot>(),
      ];

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
      trainingPartnerIds:
          (json['trainingPartnerIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      matchdayTimes: (json['matchdayTimes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class PitchOccupancyConflict {
  const PitchOccupancyConflict({
    required this.key,
    required this.first,
    required this.second,
    required this.approved,
  });

  final String key;
  final PitchOccupancySlot first;
  final PitchOccupancySlot second;
  final bool approved;

  static String keyFor(PitchOccupancySlot first, PitchOccupancySlot second) {
    final signatures = [first.conflictSignature, second.conflictSignature]
      ..sort();
    return signatures.join('||');
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
    required this.kind,
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
  final PitchOccupancySlotKind kind;

  String get timeLabel => '${_time(startMinute)}–${_time(endMinute)}';
  String get conflictSignature =>
      '$teamId:$weekday:$startMinute:$endMinute:${_normalizedLocation(location)}';

  bool overlaps(PitchOccupancySlot other) =>
      kind == PitchOccupancySlotKind.training &&
      other.kind == PitchOccupancySlotKind.training &&
      weekday == other.weekday &&
      !_isOpenLocation(location) &&
      !_isOpenLocation(other.location) &&
      _normalizedLocation(location) == _normalizedLocation(other.location) &&
      startMinute < other.endMinute &&
      other.startMinute < endMinute;

  static PitchOccupancySlot? tryParse(
    PitchOccupancyTeam team,
    String rawValue, [
    PitchOccupancySlotKind kind = PitchOccupancySlotKind.training,
  ]) {
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
    final locationMatch = RegExp(
      r'(?:·|\|)\s*Platz:\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(rawValue);
    final slotLocation = locationMatch?.group(1)?.trim();
    return PitchOccupancySlot(
      teamId: team.id,
      teamLabel: team.label,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      location:
          slotLocation?.isNotEmpty == true ? slotLocation! : team.location,
      rawValue: rawValue,
      kind: kind,
    );
  }

  static String _time(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:'
      '${(value % 60).toString().padLeft(2, '0')}';

  static String _normalizedLocation(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isOpenLocation(String value) {
    final normalized = _normalizedLocation(value);
    return normalized.contains('offen') || normalized.contains('unklar');
  }
}
