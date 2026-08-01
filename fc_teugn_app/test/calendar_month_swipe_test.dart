import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/calendar/calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile calendar changes months with horizontal swipes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    const ageGroup = AgeGroupSummary(
      id: 'age-e',
      name: 'E-Jugend',
      code: 'E',
    );
    const team = TeamSummary(
      id: 'team-e1',
      name: 'E1',
      ageGroup: ageGroup,
      seasonName: '2026/27',
    );
    final organization = OrganizationContext(
      club: const ClubSummary(
        id: 'club-1',
        name: 'FC Teugn',
        shortName: 'FCT',
        primaryColor: '#171918',
        accentColor: '#FFE600',
      ),
      season: SeasonSummary(
        id: 'season-1',
        name: '2026/27',
        startDate: DateTime(now.year - 1, 7, 1),
        endDate: DateTime(now.year + 1, 6, 30),
        isActive: true,
      ),
      currentTeam: team,
      ageGroups: const [ageGroup],
      teams: const [team],
      permissions: const {},
      metrics: const OrganizationMetrics(
        players: 0,
        members: 0,
        upcomingEvents: 0,
        pendingApprovals: 0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsProvider.overrideWith((ref) async => const []),
          organizationProvider.overrideWith((ref) async => organization),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CalendarPage(canManage: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialLabel = _monthLabel(now);
    final nextLabel = _monthLabel(DateTime(now.year, now.month + 1));
    expect(find.text(initialLabel), findsOneWidget);

    final swipeSurface = find.byKey(
      const ValueKey('calendar-month-swipe-surface'),
    );
    expect(swipeSurface, findsOneWidget);
    await tester.ensureVisible(swipeSurface);
    await tester.pumpAndSettle();

    var swipeStart = tester.getTopLeft(swipeSurface) + const Offset(280, 120);
    await tester.flingFrom(swipeStart, const Offset(-180, 0), 800);
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.byKey(const ValueKey('calendar-month-page-transition')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text(nextLabel), findsOneWidget);

    swipeStart = tester.getTopLeft(swipeSurface) + const Offset(100, 120);
    await tester.flingFrom(swipeStart, const Offset(180, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text(initialLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String _monthLabel(DateTime value) {
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  return '${months[value.month - 1]} ${value.year}';
}
