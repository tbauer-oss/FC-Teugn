import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
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
          calendarEventsProvider.overrideWith((ref, range) async {
            ref.keepAlive();
            return const [];
          }),
          playersProvider.overrideWith((ref) async => const []),
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
          calendarEventsProvider.overrideWith((ref, range) async {
            ref.keepAlive();
            return events;
          }),
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
        opponent: 'SC Thaldorf E1',
        isHome: true,
      ),
      _calendarEvent(
        id: 'away-match',
        title: 'Auswärtsspiel',
        startAt: date.add(const Duration(days: 2)),
        category: 'LEAGUE_MATCH',
        opponent: 'TSV Abensberg E3',
        isHome: false,
      ),
      _calendarEvent(
        id: 'party',
        title: 'Weihnachtsfeier',
        startAt: date.add(const Duration(days: 3)),
        category: 'CHRISTMAS_PARTY',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarEventsProvider.overrideWith((ref, range) async {
            ref.keepAlive();
            return events;
          }),
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
    expect(find.text('⚽ H'), findsWidgets);
    expect(find.text('⚽ A'), findsWidgets);
    expect(find.text('H Heim'), findsOneWidget);
    expect(find.text('A Auswärts'), findsOneWidget);
    expect(find.text('FC Teugn – SC Thaldorf E1'), findsOneWidget);
    expect(find.text('TSV Abensberg E3 – FC Teugn'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final width in const [360.0, 390.0, 480.0, 599.0, 720.0, 884.0]) {
      tester.view.physicalSize = Size(width, 820);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-month-swipe-surface')),
        findsOneWidget,
        reason: 'Auch ein $width px breites Foldable-Pane muss die kompakte, '
            'wischbare Monatsansicht verwenden.',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Der Kalender muss auch bei $width px und in Foldable-Panes '
            'ohne Überlauf bleiben.',
      );
    }
  });

  testWidgets('empty mobile calendar day can create a preselected appointment',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final organization = _organization(
      now,
      permissions: const {'MANAGE_EVENTS'},
    );
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: options.path.contains('pitch-conflicts')
                ? <String, dynamic>{'conflicts': <dynamic>[]}
                : <dynamic>[],
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarEventsProvider.overrideWith((ref, range) async {
            ref.keepAlive();
            return const [];
          }),
          repositoryProvider.overrideWithValue(DataRepository(client)),
          organizationProvider.overrideWith((ref) async => organization),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CalendarPage(canManage: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final emptyDay = find.bySemanticsLabel(
      RegExp(r'^15, keine Termine'),
    );
    expect(emptyDay, findsOneWidget);
    await tester.tap(emptyDay);
    await tester.pumpAndSettle();

    expect(
      find.text('Für diesen Tag sind noch keine Termine eingetragen.'),
      findsOneWidget,
    );
    final create = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Termin anlegen'),
    );
    expect(create, findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(find.byType(EventEditorDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

OrganizationContext _organization(
  DateTime now, {
  Set<String> permissions = const {},
}) {
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
    permissions: permissions,
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
  String? opponent,
  bool? isHome,
}) {
  return EventModel.fromJson({
    'id': id,
    'teamId': 'team-e1',
    'type': 'EVENT',
    'category': category,
    'status': 'SCHEDULED',
    'visibility': 'TEAM',
    'title': title,
    'ownTeam': {
      'name': 'FC Teugn',
      'shortName': 'FCT',
      'isPlayingCommunity': false,
    },
    'startAt': startAt.toIso8601String(),
    'location': 'Sportplatz Teugn',
    if (opponent != null)
      'matchDetails': {
        'opponent': opponent,
        'isHome': isHome ?? true,
      },
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
