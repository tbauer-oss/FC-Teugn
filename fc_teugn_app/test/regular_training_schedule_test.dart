import 'package:fc_teugn_app/core/regular_training_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an individual weekday, time range and pitch', () {
    final slot = RegularTrainingSlot.tryParse(
      'Dienstag 17:30–19:00 · Platz: Platz 1 unten',
      fallbackLocation: 'Platz 2 oben',
    );

    expect(slot, isNotNull);
    expect(slot!.weekday, DateTime.tuesday);
    expect(slot.startMinutes, 17 * 60 + 30);
    expect(slot.endMinutes, 19 * 60);
    expect(slot.location, 'Platz 1 unten');
  });

  test('creates weekly occurrences only within the season', () {
    final slot = RegularTrainingSlot.tryParse(
      'Donnerstag 16:30 - 18:00',
      fallbackLocation: 'Platz 2 oben',
    )!;

    final occurrences = slot
        .occurrences(
          DateTime(2026, 7, 1),
          DateTime(2026, 7, 31),
        )
        .toList();

    expect(occurrences.length, 5);
    expect(occurrences.first.$1, DateTime(2026, 7, 2, 16, 30));
    expect(occurrences.last.$2, DateTime(2026, 7, 30, 18));
    expect(slot.location, 'Platz 2 oben');
  });
}
