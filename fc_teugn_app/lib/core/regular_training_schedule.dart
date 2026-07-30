class RegularTrainingSlot {
  const RegularTrainingSlot({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.location,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final String location;

  static const _weekdays = {
    'montag': DateTime.monday,
    'dienstag': DateTime.tuesday,
    'mittwoch': DateTime.wednesday,
    'donnerstag': DateTime.thursday,
    'freitag': DateTime.friday,
    'samstag': DateTime.saturday,
    'sonntag': DateTime.sunday,
  };

  static RegularTrainingSlot? tryParse(
    String value, {
    String? fallbackLocation,
  }) {
    final dayMatch = RegExp(
      r'(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)',
      caseSensitive: false,
    ).firstMatch(value);
    final timeMatch = RegExp(
      r'(\d{1,2}):(\d{2})\s*(?:-|–|—|bis)\s*(\d{1,2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(value);
    if (dayMatch == null || timeMatch == null) return null;
    final start =
        int.parse(timeMatch.group(1)!) * 60 + int.parse(timeMatch.group(2)!);
    final end =
        int.parse(timeMatch.group(3)!) * 60 + int.parse(timeMatch.group(4)!);
    if (start < 0 || start >= 1440 || end <= start || end > 1440) return null;
    final pitchMatch = RegExp(
      r'(?:·|\|)\s*Platz:\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    return RegularTrainingSlot(
      weekday: _weekdays[dayMatch.group(1)!.toLowerCase()]!,
      startMinutes: start,
      endMinutes: end,
      location: pitchMatch?.group(1)?.trim().isNotEmpty == true
          ? pitchMatch!.group(1)!.trim()
          : (fallbackLocation?.trim().isNotEmpty == true
              ? fallbackLocation!.trim()
              : 'Platz noch offen / unklar'),
    );
  }

  Iterable<(DateTime, DateTime)> occurrences(
    DateTime seasonStart,
    DateTime seasonEnd,
  ) sync* {
    var date = DateTime(seasonStart.year, seasonStart.month, seasonStart.day);
    final last = DateTime(seasonEnd.year, seasonEnd.month, seasonEnd.day);
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }
    while (!date.isAfter(last)) {
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        startMinutes ~/ 60,
        startMinutes % 60,
      );
      final end = DateTime(
        date.year,
        date.month,
        date.day,
        endMinutes ~/ 60,
        endMinutes % 60,
      );
      yield (start, end);
      date = date.add(const Duration(days: 7));
    }
  }
}
