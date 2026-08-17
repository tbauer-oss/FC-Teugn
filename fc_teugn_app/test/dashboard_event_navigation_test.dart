import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/features/shared/dashboard_event_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _event({
  String id = 'training-1',
  EventType type = EventType.training,
  EventCategory category = EventCategory.training,
}) =>
    EventModel(
      id: id,
      teamId: 'team-e1',
      type: type,
      category: category,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: 'Training',
      startAt: DateTime(2026, 8, 18, 17, 30),
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
  test('parent dashboard training opens the highlighted family response', () {
    expect(
      dashboardEventRoute(event: _event(), isTrainer: false),
      '/parent/family?eventId=training-1',
    );
  });

  test('trainer dashboard uses family response only for a linked child', () {
    expect(
      dashboardEventRoute(
        event: _event(),
        isTrainer: true,
        personalResponseEventIds: const {'training-1'},
      ),
      '/trainer/family?eventId=training-1',
    );
    expect(
      dashboardEventRoute(event: _event(), isTrainer: true),
      '/trainer/training/training-1',
    );
  });

  test('match navigation remains unchanged', () {
    expect(
      dashboardEventRoute(
        event: _event(
          id: 'match-1',
          type: EventType.match,
          category: EventCategory.leagueMatch,
        ),
        isTrainer: false,
      ),
      '/parent/matches/match-1',
    );
  });

  test('parent special event opens the matching calendar detail', () {
    expect(
      dashboardEventRoute(
        event: _event(
          id: 'event-1',
          type: EventType.event,
          category: EventCategory.specialEvent,
        ),
        isTrainer: false,
      ),
      '/parent/events?eventId=event-1',
    );
  });
}
