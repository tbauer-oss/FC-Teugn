import 'package:fc_teugn_app/core/match_overview_sort.dart';
import 'package:fc_teugn_app/core/match_view_preferences.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('match remains first after kick-off instead of becoming an old event',
      () {
    final now = DateTime(2026, 8, 31, 18, 5);
    final liveMatch = _event('live', DateTime(2026, 8, 31, 18));
    final nextMatch = _event('next', DateTime(2026, 9, 7, 18));
    final previousMatch = _event('previous', DateTime(2026, 8, 24, 18));
    final matches = [nextMatch, previousMatch, liveMatch]..sort(
        (first, second) => compareMatchOverviewEvents(
          first,
          second,
          now,
          MatchSortOrder.nextFirst,
        ),
      );

    expect(matches.map((item) => item.id), ['live', 'next', 'previous']);
    expect(
      matchOverviewPhase(liveMatch, now),
      MatchOverviewPhase.operational,
    );
  });

  test('delayed evening matches stay operational beyond their planned end', () {
    final match = _event(
      'delayed',
      DateTime(2026, 8, 31, 20, 30),
      durationMinutes: 60,
    );

    expect(
      matchOverviewPhase(match, DateTime(2026, 8, 31, 23, 45)),
      MatchOverviewPhase.operational,
    );
    expect(
      matchOverviewPhase(match, DateTime(2026, 9, 1, 4)),
      MatchOverviewPhase.operational,
    );
  });
}

EventModel _event(
  String id,
  DateTime startAt, {
  int durationMinutes = 60,
}) =>
    EventModel(
      id: id,
      teamId: 'team-1',
      type: EventType.match,
      category: EventCategory.friendlyMatch,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: id,
      startAt: startAt,
      location: 'Sportplatz',
      attendanceFinalized: false,
      targetTeams: const [],
      attachments: const [],
      attendance: const [],
      attendanceSummary: const AttendanceSummary(
        yes: 0,
        no: 0,
        maybe: 0,
        unknown: 0,
      ),
      missingAttendance: const [],
      carpoolOffers: const [],
      capabilities: const EventCapabilities(),
      reminderMinutes: const [],
      matchDetails: MatchDetails(
        opponent: 'Gegner',
        isHome: true,
        durationMinutes: durationMinutes,
      ),
    );
