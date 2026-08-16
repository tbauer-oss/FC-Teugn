import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/features/trainer/trainer_dashboard_page.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _event({
  required String id,
  required EventCategory category,
  required DateTime startAt,
}) =>
    EventModel(
      id: id,
      teamId: 'team-e1',
      type: category == EventCategory.training
          ? EventType.training
          : EventType.event,
      category: category,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: category.label,
      startAt: startAt,
      location: 'Teugn Sportplatz',
      attendanceFinalized: false,
      targetTeams: const [],
      attachments: const [],
      attendance: const [],
      attendanceSummary: const AttendanceSummary(),
      missingAttendance: const [],
      carpoolOffers: const [],
      capabilities: const EventCapabilities(),
      reminderMinutes: const [],
    );

void main() {
  test('dashboard selects the chronologically next training', () {
    final selected = nextTrainingForDashboard([
      _event(
        id: 'meeting',
        category: EventCategory.teamMeeting,
        startAt: DateTime(2026, 8, 17, 17),
      ),
      _event(
        id: 'training-later',
        category: EventCategory.training,
        startAt: DateTime(2026, 8, 25, 17, 30),
      ),
      _event(
        id: 'training-next',
        category: EventCategory.training,
        startAt: DateTime(2026, 8, 18, 17, 30),
      ),
    ]);

    expect(selected?.id, 'training-next');
  });

  test('dashboard counters include replies and every open player', () {
    final counts = trainingDashboardCounts(
      const AttendanceSummary(yes: 9, no: 2, maybe: 1, unknown: 3),
      missingCount: 3,
      rosterCount: 15,
    );

    expect(counts, (yes: 9, no: 2, maybe: 1, open: 3, total: 15));
  });

  test('dashboard uses the roster while no responses exist yet', () {
    final counts = trainingDashboardCounts(
      const AttendanceSummary(),
      missingCount: 0,
      rosterCount: 12,
    );

    expect(counts.open, 12);
    expect(counts.total, 12);
  });
}
