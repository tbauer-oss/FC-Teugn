import 'package:fc_teugn_app/features/calendar/calendar_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Kalenderdatum für neue Termine', () {
    test('übernimmt den gewählten Tag und setzt 18:00 Uhr als Standard', () {
      final value = defaultCalendarStartForDate(
        DateTime(2026, 9, 15),
        now: DateTime(2026, 7, 31, 10, 12),
      );

      expect(value, DateTime(2026, 9, 15, 18));
    });

    test('rundet am heutigen Tag auf die nächste halbe Stunde', () {
      final value = defaultCalendarStartForDate(
        DateTime(2026, 7, 31),
        now: DateTime(2026, 7, 31, 14, 42),
      );

      expect(value, DateTime(2026, 7, 31, 15));
    });

    test('bleibt auch kurz vor Mitternacht auf dem gewählten Tag', () {
      final value = defaultCalendarStartForDate(
        DateTime(2026, 7, 31),
        now: DateTime(2026, 7, 31, 23, 45),
      );

      expect(value, DateTime(2026, 7, 31, 23, 59));
    });
  });
}
