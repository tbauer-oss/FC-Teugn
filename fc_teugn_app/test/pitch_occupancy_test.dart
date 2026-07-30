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

  test('supports a different pitch for each training day', () {
    const team = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1',
      ageGroupCode: 'E',
      location: 'Platz 1 unten',
      trainingTimes: [
        'Dienstag 17:00–18:30 · Platz: Platz 1 unten',
        'Donnerstag 17:00–18:30 · Platz: Platz 2 oben',
      ],
    );

    expect(team.slots, hasLength(2));
    expect(team.slots.first.location, 'Platz 1 unten');
    expect(team.slots.last.location, 'Platz 2 oben');
    expect(team.locationLabel, 'Unterschiedliche Plätze');
  });

  test('slot-specific pitches are used for conflict detection', () {
    const first = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1',
      ageGroupCode: 'E',
      location: 'Platz 1 unten',
      trainingTimes: [
        'Dienstag 17:00–18:30 · Platz: Platz 2 oben',
      ],
    );
    const second = PitchOccupancyTeam(
      id: 'd1',
      name: 'D1',
      ageGroupCode: 'D',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 17:30–19:00'],
    );

    expect(first.slots.single.overlaps(second.slots.single), isFalse);
  });

  test('an open pitch does not create a false conflict', () {
    const first = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1',
      ageGroupCode: 'E',
      location: 'Platz 1 unten',
      trainingTimes: [
        'Dienstag 17:00–18:30 · Platz: Platz noch offen / unklar',
      ],
    );
    const second = PitchOccupancyTeam(
      id: 'd1',
      name: 'D1',
      ageGroupCode: 'D',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 17:30–19:00'],
    );

    expect(first.slots.single.overlaps(second.slots.single), isFalse);
  });

  test('parses the dedicated recreational schedule separately', () {
    final plan = PitchOccupancyPlan.fromJson({
      'club': {'name': 'FC Teugn'},
      'season': {'name': '2026/27'},
      'teams': <Map<String, dynamic>>[],
      'recreationalSchedule': {
        'id': 'recreational:season-1',
        'name': 'Freizeitkicker',
        'shortName': 'Freizeitkicker',
        'trainingLocation': 'Platz 1 unten',
        'trainingTimes': ['Montag 19:30–21:00'],
        'ageGroup': {'code': '', 'name': 'Freizeit'},
      },
    });

    expect(plan.recreationalSchedule?.label, 'Freizeitkicker');
    expect(plan.recreationalSchedule?.slots.single.timeLabel, '19:30–21:00');
  });

  test('matchday slots never create training conflicts', () {
    const team = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1',
      ageGroupCode: 'E',
      location: 'Platz 1 unten',
      trainingTimes: ['Samstag 10:00–12:00'],
      matchdayTimes: ['Samstag 10:00–12:00'],
    );

    expect(team.slots, hasLength(2));
    expect(team.slots.first.overlaps(team.slots.last), isFalse);
    expect(team.slots.last.kind, PitchOccupancySlotKind.matchday);
  });

  test('matchday slots keep their individual or open pitch', () {
    const team = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1',
      ageGroupCode: 'E',
      location: 'Platz 1 unten',
      trainingTimes: [],
      matchdayTimes: [
        'Samstag 10:00–12:00 · Platz: Platz noch offen / unklar',
        'Sonntag 14:00–16:00 · Platz: Platz 2 oben',
      ],
    );

    expect(team.slots, hasLength(2));
    expect(team.slots.first.location, 'Platz noch offen / unklar');
    expect(team.slots.last.location, 'Platz 2 oben');
    expect(
      team.slots.every(
        (slot) => slot.kind == PitchOccupancySlotKind.matchday,
      ),
      isTrue,
    );
  });

  test('joint training is not reported as a conflict', () {
    const first = PitchOccupancyTeam(
      id: 'e1',
      name: 'E1',
      ageGroupCode: 'E',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 17:00–18:30'],
      trainingPartnerIds: ['e2'],
    );
    const second = PitchOccupancyTeam(
      id: 'e2',
      name: 'E2',
      ageGroupCode: 'E',
      location: 'Platz 2 oben',
      trainingTimes: ['Dienstag 17:00–18:30'],
    );
    const plan = PitchOccupancyPlan(
      seasonId: 'season',
      clubName: 'FC Teugn',
      seasonName: '2026/27',
      teams: [first, second],
    );

    expect(plan.conflicts, isEmpty);
  });

  test('approved conflicts remain identifiable but are marked approved', () {
    const first = PitchOccupancyTeam(
      id: 'e',
      name: 'E',
      ageGroupCode: 'E',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 17:00–18:30'],
    );
    const second = PitchOccupancyTeam(
      id: 'd',
      name: 'D',
      ageGroupCode: 'D',
      location: 'Platz 1 unten',
      trainingTimes: ['Dienstag 18:00–19:30'],
    );
    final key = PitchOccupancyConflict.keyFor(
      first.slots.single,
      second.slots.single,
    );
    final plan = PitchOccupancyPlan(
      seasonId: 'season',
      clubName: 'FC Teugn',
      seasonName: '2026/27',
      teams: const [first, second],
      approvedConflictKeys: {key},
    );

    expect(plan.conflicts.single.approved, isTrue);
  });

  test('parses individual indoor occupancy entries with local times', () {
    final plan = PitchOccupancyPlan.fromJson({
      'club': {'name': 'FC Teugn'},
      'season': {'id': 'season', 'name': '2026/27'},
      'mode': 'INDOOR',
      'teams': <Map<String, dynamic>>[],
      'canManageOccupancy': true,
      'specialEntries': [
        {
          'id': 'entry-1',
          'title': 'Faschingsverein',
          'location': 'Sporthalle',
          'startAt': '2027-02-06T17:00:00.000Z',
          'endAt': '2027-02-06T22:00:00.000Z',
          'notes': 'Aufbau und Veranstaltung',
          'isRecurring': true,
          'recurrenceWeekdays': [2, 4],
          'recurrenceIntervalWeeks': 1,
          'recurrenceUntil': '2027-03-31T21:59:59.000Z',
        },
      ],
    });

    expect(plan.indoor, isTrue);
    expect(plan.canManageOccupancy, isTrue);
    expect(plan.specialEntries, hasLength(1));
    expect(plan.specialEntries.single.title, 'Faschingsverein');
    expect(plan.specialEntries.single.location, 'Sporthalle');
    expect(plan.specialEntries.single.isRecurring, isTrue);
    expect(plan.specialEntries.single.recurrenceWeekdays, [2, 4]);
    expect(plan.specialEntries.single.recurrenceIntervalWeeks, 1);
    expect(plan.specialEntries.single.recurrenceUntil, isNotNull);
    expect(
        plan.specialEntries.single.endAt.isAfter(
          plan.specialEntries.single.startAt,
        ),
        isTrue);
  });
}
