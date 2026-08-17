import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/features/parent/family_assistant_model.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _event(String id, DateTime startAt) => EventModel(
      id: id,
      teamId: 'e1',
      type: EventType.training,
      category: EventCategory.training,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: 'Regeltraining',
      startAt: startAt,
      location: 'Platz 1',
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

PersonalResponseModel _response(String id, DateTime startAt) =>
    PersonalResponseModel(
      eventId: id,
      playerId: 'player-1',
      playerName: 'Max',
      teamName: 'E1',
      ageGroupCode: 'E',
      title: 'Regeltraining',
      type: 'TRAINING',
      category: 'TRAINING',
      startAt: startAt,
      location: 'Platz 1',
      responseStatus: AttendanceStatus.unknown,
      canRespond: true,
      isOverdue: false,
    );

void main() {
  test('week timeline merges calendar and response occurrence only once', () {
    final start = DateTime(2026, 8, 18, 17, 15);
    final items = buildFamilyTimeline(
      events: [_event('training-1', start)],
      responses: [_response('training-1', start)],
      from: DateTime(2026, 8, 17),
      until: DateTime(2026, 8, 25),
    );

    expect(items, hasLength(1));
    expect(items.single.event, isNotNull);
    expect(items.single.response, isNotNull);
  });

  test('regular training from personal responses remains visible', () {
    final start = DateTime(2026, 8, 18, 17, 15);
    final items = buildFamilyTimeline(
      events: const [],
      responses: [_response('generated-training', start)],
      from: DateTime(2026, 8, 17),
      until: DateTime(2026, 8, 25),
    );

    expect(items.single.isTraining, isTrue);
    expect(items.single.startAt, start);
  });

  test('duplicate calendar records for the same team and time are collapsed',
      () {
    final start = DateTime(2026, 8, 18, 17, 15);
    final items = buildFamilyTimeline(
      events: [_event('old-series', start), _event('new-series', start)],
      responses: const [],
      from: DateTime(2026, 8, 17),
      until: DateTime(2026, 8, 25),
    );

    expect(items, hasLength(1));
  });

  test('active ticker does not depend on a squad nomination', () {
    final match = MatchdayModel(
      id: 'match-1',
      title: 'FC Teugn gegen TSV Test',
      startAt: DateTime(2026, 8, 18, 17, 30),
      location: 'Sportplatz',
      teamId: 'e1',
      ticker: const LiveTickerModel(
        status: TickerStatus.live,
        currentPeriod: 1,
        elapsedSeconds: 120,
        ourGoals: 1,
        theirGoals: 0,
        lastSequence: 1,
        events: [],
      ),
    );

    expect(match.squad, isNull);
    expect(isActiveFamilyTicker(match), isTrue);
  });

  test('notifications are grouped into parent-friendly sections', () {
    AppNotificationModel notification(NotificationCategory category) =>
        AppNotificationModel(
          id: category.name,
          category: category,
          title: 'Hinweis',
          body: 'Text',
          createdAt: DateTime(2026, 8, 17),
          isRead: false,
        );

    expect(
      familyNotificationGroup(notification(NotificationCategory.nomination)),
      FamilyNotificationGroup.matchday,
    );
    expect(
      familyNotificationGroup(notification(NotificationCategory.eventReminder)),
      FamilyNotificationGroup.training,
    );
    expect(
      familyNotificationGroup(notification(NotificationCategory.urgent)),
      FamilyNotificationGroup.important,
    );
  });

  test('time change is displayed as old to new time', () {
    final notification = AppNotificationModel(
      id: 'change-1',
      category: NotificationCategory.event,
      title: 'Training verschoben',
      body: 'Das Training wurde von 17:30 auf 17:15 verlegt.',
      createdAt: DateTime(2026, 8, 17),
      isRead: false,
    );

    expect(
      scheduleChangeSummary(notification),
      'Training verschoben: 17:30 → 17:15 Uhr',
    );
  });
}
