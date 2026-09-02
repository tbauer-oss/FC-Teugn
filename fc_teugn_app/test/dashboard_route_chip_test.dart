import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/dashboard_summary.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/shared/dashboard_route_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _awayMatch() => EventModel(
      id: 'match-away',
      teamId: 'team-e1',
      type: EventType.match,
      category: EventCategory.friendlyMatch,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: 'TSV Langquaid – FC Teugn E1',
      startAt: DateTime(2026, 9, 8, 17, 30),
      location: 'Waldstadion',
      address: 'Am Waldstadion 1, 84085 Langquaid',
      homeAway: HomeAway.away,
      opponent: 'TSV Langquaid',
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
  testWidgets('away route shows live distance and drive time from Teugn',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchRouteEstimateProvider.overrideWith(
            (ref, eventId) async => const MatchRouteEstimate(
              distanceKm: 32,
              durationMinutes: 28,
              attribution: '© OpenStreetMap-Mitwirkende',
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: DashboardRouteChip(event: _awayMatch())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('32 km · ca. 28 Min.'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('unavailable route payload remains a clean fallback', () {
    expect(MatchRouteEstimate.fromJson({'available': false}), isNull);
  });
}
