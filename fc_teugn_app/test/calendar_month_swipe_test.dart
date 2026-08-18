import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/calendar/calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile calendar changes months with horizontal swipes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
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

    final pageScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final scrollBeforeCalendarDrag = pageScroll.position.pixels;
    await tester.drag(swipeSurface, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(
      pageScroll.position.pixels,
      lessThan(scrollBeforeCalendarDrag - 20),
      reason: 'Reine vertikale Gesten müssen auch über dem Kalender die '
          'gesamte Seite wieder nach oben scrollen können.',
    );
    await tester.ensureVisible(swipeSurface);
    await tester.pumpAndSettle();

    var swipeStart = tester.getTopLeft(swipeSurface) + const Offset(280, 120);
    final scrollBeforeHorizontalDrag = pageScroll.position.pixels;
    final gesture = await tester.startGesture(swipeStart);
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    expect(
      pageScroll.position.pixels,
      closeTo(scrollBeforeHorizontalDrag, .1),
      reason: 'Während der horizontalen Monatsgeste darf die Seite nicht '
          'vertikal wandern.',
    );
    expect(
      find.byKey(const ValueKey('calendar-month-dragging-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-month-adjacent-page')),
      findsOneWidget,
    );
    final adjacentTransform = tester.widget<Transform>(
      find.byKey(const ValueKey('calendar-month-adjacent-page')),
    );
    expect(
      adjacentTransform.transform.storage[12],
      greaterThan(0),
      reason: 'Der Folgemonat muss bereits unter dem Finger ins Bild kommen.',
    );
    await gesture.moveBy(const Offset(-90, 0));
    await gesture.up();
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

  testWidgets('desktop calendar opens every appointment of an overflowing day',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 15, 16);
    final events = List.generate(
      4,
      (index) => _calendarEvent(
        id: 'event-$index',
        title: 'Termin ${index + 1}',
        startAt: date.add(Duration(minutes: index * 30)),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsProvider.overrideWith((ref) async => events),
          organizationProvider.overrideWith(
            (ref) async => _organization(now),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CalendarPage(canManage: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final overflow = find.text('+ 2 weitere');
    expect(overflow, findsOneWidget);
    await tester.ensureVisible(overflow);
    await tester.tap(overflow);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-day-events-dialog')),
      findsOneWidget,
    );
    expect(find.text('Termin 4'), findsOneWidget);
    expect(find.text('Schließen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mobile calendar shows distinct emoji categories without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 18, 17, 15);
    final events = [
      _calendarEvent(
        id: 'training',
        title: 'Training',
        startAt: date,
        category: 'TRAINING',
      ),
      _calendarEvent(
        id: 'match',
        title: 'Pflichtspiel',
        startAt: date.add(const Duration(days: 1)),
        category: 'LEAGUE_MATCH',
      ),
      _calendarEvent(
        id: 'party',
        title: 'Weihnachtsfeier',
        startAt: date.add(const Duration(days: 2)),
        category: 'CHRISTMAS_PARTY',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsProvider.overrideWith((ref) async => events),
          organizationProvider.overrideWith((ref) async => _organization(now)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CalendarPage(canManage: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🏃 Training'), findsWidgets);
    expect(find.text('⚽ Pflichtspiel'), findsWidgets);
    expect(find.text('🎄 Weihnachtsfeier'), findsWidgets);
    expect(tester.takeException(), isNull);

    for (final width in const [360.0, 390.0, 480.0, 599.0]) {
      tester.view.physicalSize = Size(width, 820);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Der Kalender muss auch bei $width px und in Foldable-Panes '
            'ohne Überlauf bleiben.',
      );
    }
  });
}

OrganizationContext _organization(DateTime now) {
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
  return OrganizationContext(
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
      upcomingEvents: 4,
      pendingApprovals: 0,
    ),
  );
}

EventModel _calendarEvent({
  required String id,
  required String title,
  required DateTime startAt,
  String category = 'SPECIAL_EVENT',
}) {
  return EventModel.fromJson({
    'id': id,
    'teamId': 'team-e1',
    'type': 'EVENT',
    'category': category,
    'status': 'SCHEDULED',
    'visibility': 'TEAM',
    'title': title,
    'startAt': startAt.toIso8601String(),
    'location': 'Sportplatz Teugn',
    'attendanceFinalized': false,
    'targetTeams': <dynamic>[],
    'attachments': <dynamic>[],
    'attendance': <dynamic>[],
    'attendanceSummary': <String, dynamic>{},
    'missingAttendance': <dynamic>[],
    'carpoolOffers': <dynamic>[],
    'capabilities': <String, dynamic>{},
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
