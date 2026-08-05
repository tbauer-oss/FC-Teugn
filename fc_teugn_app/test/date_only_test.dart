import 'package:fc_teugn_app/core/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final testCase in <({String label, DateTime date})>[
    (label: 'Montag', date: DateTime(2026, 8, 3)),
    (label: 'Dienstag', date: DateTime(2026, 8, 4)),
    (label: 'Samstag', date: DateTime(2026, 8, 8)),
    (label: 'Sonntag', date: DateTime(2026, 8, 9)),
  ]) {
    test('${testCase.label} bleibt beim Date-only-Roundtrip erhalten', () {
      final serialized = dateOnlyForApi(testCase.date);
      final restored = dateOnlyFromApi(serialized)!;
      expect(restored.year, testCase.date.year);
      expect(restored.month, testCase.date.month);
      expect(restored.day, testCase.date.day);
      expect(restored.weekday, testCase.date.weekday);
    });
  }
}
