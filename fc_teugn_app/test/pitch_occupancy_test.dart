import 'package:fc_teugn_app/core/models/pitch_occupancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses German weekday and time ranges', () {
    const team = PitchOccupancyTeam(
      id: 'f1',
      name: 'F1',
      ageGroupCode: 'F',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 16:15–17:30'],
    );

    final slot = team.slots.single;

    expect(slot.weekday, DateTime.tuesday);
    expect(slot.startMinute, 16 * 60 + 15);
    expect(slot.endMinute, 17 * 60 + 30);
    expect(slot.timeLabel, '16:15–17:30');
    expect(slot.teamLabel, 'F · F1');
  });

  test('uses a smart 90 minute default for a single start time', () {
    const team = PitchOccupancyTeam(
      id: 'g',
      name: 'G',
      ageGroupCode: 'G',
      location: 'Platz 1 unten',
      trainingTimes: ['Samstag 10:00'],
    );

    final slot = team.slots.single;

    expect(slot.startMinute, 10 * 60);
    expect(slot.endMinute, 11 * 60 + 30);
  });

  test('detects overlaps only on the same weekday and pitch', () {
    const firstTeam = PitchOccupancyTeam(
      id: 'e',
      name: 'E',
      ageGroupCode: 'E',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 17:30-19:00'],
    );
    const secondTeam = PitchOccupancyTeam(
      id: 'c',
      name: 'C',
      ageGroupCode: 'C',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 18:30-20:00'],
    );
    const otherPitch = PitchOccupancyTeam(
      id: 'h',
      name: 'Herren',
      ageGroupCode: '',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 18:30-20:00'],
    );

    expect(firstTeam.slots.single.overlaps(secondTeam.slots.single), isTrue);
    expect(firstTeam.slots.single.overlaps(otherPitch.slots.single), isFalse);
  });
}
