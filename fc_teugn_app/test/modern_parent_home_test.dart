import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/dashboard_summary.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/auth/auth_controller.dart';
import 'package:fc_teugn_app/features/parent/parent_dashboard_page.dart';
import 'package:fc_teugn_app/features/parent/parent_family_page.dart';
import 'package:fc_teugn_app/features/parent/parent_home_models.dart';
import 'package:fc_teugn_app/features/parent/parent_home_providers.dart';
import 'package:fc_teugn_app/features/shared/family_responses.dart';
import 'package:fc_teugn_app/features/shell/app_shell.dart';
import 'package:fc_teugn_app/features/talents/assistant_page.dart';

final today =
    DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
PlayerModel child(String id, {String team = 'E1'}) => PlayerModel(
    id: id,
    firstName: id == 'mia' ? 'Mia' : 'Ben',
    lastName: '',
    preferredName: id == 'mia' ? 'Mia' : 'Ben',
    teamId: team,
    teamName: '$team-Jugend',
    teamNumber: team == 'E1' ? 1 : 2,
    ageGroupCode: team.substring(0, 1),
    status: PlayerStatus.active,
    dominantFoot: DominantFoot.right);
EventModel event(String id,
        {bool match = false,
        String team = 'E1',
        int days = 4,
        DateTime? deadline,
        EventCategory? category}) =>
    EventModel(
        id: id,
        teamId: team,
        type: match ? EventType.match : EventType.training,
        category: category ??
            (match ? EventCategory.friendlyMatch : EventCategory.training),
        status: EventStatus.scheduled,
        visibility: EventVisibility.team,
        title: match ? 'SV Saal $team – FC Teugn $team' : 'Training',
        startAt: today.add(Duration(
            days: days, hours: match ? 10 : 17, minutes: match ? 0 : 15)),
        meetingAt: match
            ? today.add(Duration(days: days, hours: 9, minutes: 15))
            : null,
        responseDeadline: deadline,
        location: match ? 'Sportplatz Saal' : 'Platz 1 unten',
        address: match ? 'Lindenstraße 30, 93342 Saal an der Donau' : null,
        homeAway: match ? HomeAway.away : HomeAway.home,
        opponent: match ? 'SV Saal $team' : null,
        ownTeamName: 'FC Teugn $team',
        attendanceFinalized: false,
        targetTeams: const [],
        attachments: const [],
        attendance: const [],
        attendanceSummary: const AttendanceSummary(),
        missingAttendance: const [],
        carpoolOffers: const [],
        capabilities: const EventCapabilities(),
        reminderMinutes: const []);
PersonalResponseModel response(EventModel e, PlayerModel p,
        {AttendanceStatus status = AttendanceStatus.unknown,
        bool canRespond = true}) =>
    PersonalResponseModel(
        eventId: e.id,
        playerId: p.id,
        playerName: p.displayName,
        teamName: p.teamName ?? '',
        ageGroupCode: p.teamCode,
        title: e.title,
        type: e.type == EventType.match ? 'MATCH' : 'TRAINING',
        category: e.type == EventType.match ? 'FRIENDLY_MATCH' : 'TRAINING',
        startAt: e.startAt,
        meetingAt: e.meetingAt,
        responseDeadline: e.responseDeadline,
        location: e.location,
        responseStatus: status,
        canRespond: canRespond,
        isOverdue: false);

class _Auth extends AuthController {
  @override
  Future<String?> refreshAccessToken() async => 'local-test';
  _Auth({bool preview = false}) {
    state = AuthState(
        user: AppUser(
            id: 'alex',
            email: 'alex@example.test',
            name: 'Alex Ludwig',
            role: UserRole.parent,
            status: AccountStatus.approved,
            teamId: 'E1',
            preview: preview
                ? AdminPreviewInfo.fromJson({'readOnly': true})
                : null));
  }
}

class _Repository extends DataRepository {
  _Repository(this.responses) : super(ApiClient(baseUrl: 'http://localhost'));
  List<PersonalResponseModel> responses;
  List<(String, String, AttendanceStatus, String?)> writes = [];
  Completer<void>? wait;
  bool fail = false;
  @override
  Future<EventModel> setAttendance(
      {required String eventId,
      required String playerId,
      required AttendanceStatus status,
      String? reason,
      bool personalResponse = false,
      bool? goalkeeperAvailable}) async {
    writes.add((eventId, playerId, status, reason));
    expect(personalResponse, isTrue);
    if (wait != null) await wait!.future;
    if (fail) throw Exception('offline');
    responses = responses
        .map((r) => r.eventId == eventId && r.playerId == playerId
            ? PersonalResponseModel(
                eventId: r.eventId,
                playerId: r.playerId,
                playerName: r.playerName,
                teamName: r.teamName,
                ageGroupCode: r.ageGroupCode,
                title: r.title,
                type: r.type,
                category: r.category,
                startAt: r.startAt,
                meetingAt: r.meetingAt,
                location: r.location,
                responseStatus: status,
                canRespond: true,
                isOverdue: false,
                reason: reason)
            : r)
        .toList();
    return event(eventId);
  }
}

const destinations = [
  ShellDestination(
      label: 'Start',
      icon: Icons.home_outlined,
      route: '/parent',
      section: ShellSection.overview,
      hint: ''),
  ShellDestination(
      label: 'Termine',
      icon: Icons.calendar_today_outlined,
      route: '/parent/events',
      section: ShellSection.schedule,
      hint: ''),
  ShellDestination(
      label: 'Spiele',
      icon: Icons.sports_soccer,
      route: '/parent/matches',
      section: ShellSection.schedule,
      hint: ''),
  ShellDestination(
      label: 'Postfach',
      icon: Icons.mail_outline,
      route: '/parent/messages',
      section: ShellSection.communication,
      hint: ''),
  ShellDestination(
      label: 'Familie',
      icon: Icons.people_outline,
      route: '/parent/family',
      relatedRoutes: [
        '/parent/players',
        '/parent/responses',
        '/parent/talents'
      ],
      section: ShellSection.team,
      hint: ''),
];
Future<GoRouter> _pumpHome(WidgetTester tester,
    {double width = 390,
    double height = 900,
    double scale = 1,
    bool dark = false,
    bool family = false,
    bool preview = false,
    _Repository? repository,
    List<PlayerModel>? players,
    List<EventModel>? events}) async {
  final kids = players ?? [child('mia'), child('ben', team: 'F2')];
  final fixtures = events ??
      [
        event('training'),
        event('match', match: true, days: 8),
        event('training-f2', team: 'F2', days: 5),
        event('match-f2', team: 'F2', match: true, days: 9)
      ];
  final repo = repository ??
      _Repository([
        for (final e in fixtures)
          for (final p in kids.where((p) => p.teamId == e.teamId))
            response(e, p,
                status: e.id == 'training'
                    ? AttendanceStatus.unknown
                    : AttendanceStatus.yes)
      ]);
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (const bool.fromEnvironment('CAPTURE_UI')) {
    await tester.runAsync(() async {
      final font = FontLoader('Arial')
        ..addFont(File('C:/Windows/Fonts/arial.ttf')
            .readAsBytes()
            .then(ByteData.sublistView));
      final bold = FontLoader('Arial')
        ..addFont(File('C:/Windows/Fonts/arialbd.ttf')
            .readAsBytes()
            .then(ByteData.sublistView));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([font.load(), bold.load(), icons.load()]);
    });
  }
  final router =
      GoRouter(initialLocation: family ? '/parent/family' : '/parent', routes: [
    ShellRoute(
        builder: (context, state, page) => AppShell(
            destinations: destinations,
            title: 'Familie & Team',
            audience: ShellAudience.family,
            child: page),
        routes: [
          GoRoute(
              path: '/parent', builder: (_, __) => const ParentDashboardPage()),
          GoRoute(
              path: '/parent/family',
              builder: (_, __) => const ParentFamilyPage()),
          GoRoute(
              path: '/parent/responses',
              builder: (_, state) => FamilyResponsesPage(
                  isTrainer: false,
                  onlyOpen: state.uri.queryParameters['open'] == '1',
                  highlightedPlayerId: state.uri.queryParameters['playerId'],
                  highlightedEventId: state.uri.queryParameters['eventId'])),
          for (final path in [
            '/parent/events',
            '/parent/matches',
            '/parent/messages',
            '/parent/players/:id',
            '/parent/talents/:section',
            '/parent/matches/:id',
            '/parent/account'
          ])
            GoRoute(
                path: path,
                builder: (_, state) =>
                    Center(child: Text('Destination ${state.uri}'))),
        ])
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _Auth(preview: preview)),
        repositoryProvider.overrideWithValue(repo),
        parentDashboardSummaryProvider.overrideWith((ref) async =>
            DashboardSummary(
                players: kids, events: fixtures, notifications: const [])),
        personalResponsesProvider.overrideWith((ref) async => repo.responses),
        parentMatchdaysProvider.overrideWith((ref) async => []),
        parentConsentAttentionProvider.overrideWith((ref) async => []),
        currentDevicePushReadyProvider.overrideWith((ref) async => true),
        parentContactPreviewProvider.overrideWith((ref) async => []),
        parentInboxUnreadProvider.overrideWith((ref) => 1),
        familyTaskListProvider.overrideWith((ref) async => []),
        organizationProvider.overrideWith(
            (ref) async => throw StateError('No working context needed')),
        offlineOutboxCountProvider.overrideWith((ref) => Stream.value(0)),
        for (final e in fixtures)
          matchRouteEstimateProvider(e.id).overrideWith((ref) async =>
              const MatchRouteEstimate(
                  distanceKm: 18,
                  durationMinutes: 20,
                  attribution: 'Beispieldaten · OpenStreetMap')),
      ],
      child: MaterialApp.router(
          theme: buildAppTheme(
              brightness: dark ? Brightness.dark : Brightness.light),
          routerConfig: router,
          builder: (context, page) => RepaintBoundary(
              key: const ValueKey('capture'),
              child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: MobileAppTheme(child: page!))))));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  test('siblings retain their own answer even at a joint training', () {
    final kids = [child('mia'), child('ben')], training = event('t');
    final visits = buildParentVisits(
        players: kids,
        events: [training],
        responses: [
          response(training, kids[0]),
          response(training, kids[1], status: AttendanceStatus.no)
        ],
        now: today);
    expect(visits.length, 2);
    expect(visits.map((v) => v.key).toSet().length, 2);
    expect(
        visits.singleWhere((v) => v.player.id == 'mia').response!.isOpen, true);
    expect(
        visits
            .singleWhere((v) => v.player.id == 'ben')
            .response!
            .responseStatus,
        AttendanceStatus.no);
  });
  for (final family in [false, true]) {
    for (final size in [
      (320.0, 800.0, 1.0),
      (390.0, 900.0, 1.0),
      (430.0, 900.0, 1.0),
      (320.0, 800.0, 1.6),
      (390.0, 900.0, 2.0),
      (740.0, 360.0, 1.0),
      (720.0, 900.0, 1.4),
      (1280.0, 850.0, 1.0)
    ]) {
      testWidgets(
          '${family ? 'B Familie' : 'A Start'} fits ${size.$1}x${size.$2} scale ${size.$3}',
          (tester) async {
        await _pumpHome(tester,
            width: size.$1, height: size.$2, scale: size.$3, family: family);
        expect(find.text(family ? 'Deine Familie' : 'Hallo Alex!'),
            findsOneWidget);
        expect(find.textContaining('SV Saal'), findsWidgets);
        expect(find.text('Mehr'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'child filters both next training and match, navigation remains direct',
      (tester) async {
    final router = await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('parent-child-filter-ben')));
    await tester.pumpAndSettle();
    expect(find.textContaining('TRAINING · Ben'), findsOneWidget);
    expect(find.textContaining('SV Saal F2'), findsOneWidget);
    expect(find.textContaining('SV Saal E1'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('family-nav-Familie')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('family-child-mia')), findsOneWidget);
    expect(find.byKey(const ValueKey('family-child-ben')), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('family-absence-action')));
    await tester.tap(find.byKey(const ValueKey('family-absence-action')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        '/parent/talents/absences');
  });
  testWidgets(
      'direct approval updates only the selected child and survives a page change',
      (tester) async {
    final kids = [child('mia'), child('ben')], training = event('training');
    final repo = _Repository([for (final p in kids) response(training, p)])
      ..wait = Completer<void>();
    final router = await _pumpHome(tester,
        players: kids, events: [training], repository: repo);
    final action = find.byKey(const ValueKey('parent-answer-training:mia'));
    await tester
        .tap(find.descendant(of: action, matching: find.text('Zusagen')));
    await tester.pump();
    expect(repo.writes.length, 1);
    expect(repo.writes.single.$2, 'mia');
    final button = tester.widget<FilledButton>(
        find.descendant(of: action, matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
    repo.wait!.complete();
    await tester.pumpAndSettle();
    expect(
        repo.responses.singleWhere((r) => r.playerId == 'mia').responseStatus,
        AttendanceStatus.yes);
    expect(repo.responses.singleWhere((r) => r.playerId == 'ben').isOpen, true);
    router.go('/parent/family');
    await tester.pumpAndSettle();
    final mia = find.byKey(const ValueKey('family-child-mia'));
    expect(find.descendant(of: mia, matching: find.text('Zugesagt')),
        findsOneWidget);
  });
  testWidgets('decline asks for a reason and sends it for the right child',
      (tester) async {
    final p = child('mia'), e = event('training');
    final repo = _Repository([response(e, p)]);
    await _pumpHome(tester, players: [p], events: [e], repository: repo);
    await tester.tap(find.text('Absagen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Verhindert');
    await tester.tap(find.widgetWithText(FilledButton, 'Absagen'));
    await tester.pumpAndSettle();
    expect(repo.writes.single,
        ('training', 'mia', AttendanceStatus.no, 'Verhindert'));
    expect(find.text('Abgesagt'), findsOneWidget);
  });
  testWidgets('failed approval never appears as accepted', (tester) async {
    final p = child('mia'), e = event('training');
    final repo = _Repository([response(e, p)])..fail = true;
    await _pumpHome(tester, players: [p], events: [e], repository: repo);
    await tester.tap(find.text('Zusagen'));
    await tester.pumpAndSettle();
    expect(find.text('Zugesagt'), findsNothing);
    expect(find.textContaining('konnte nicht gespeichert'), findsOneWidget);
  });
  testWidgets('expired deadline and preview never permit saving',
      (tester) async {
    final p = child('mia'),
        e = event('match',
            match: true,
            deadline: DateTime.now().subtract(const Duration(seconds: 1)));
    final repo = _Repository([response(e, p)]);
    await _pumpHome(tester, players: [p], events: [e], repository: repo);
    expect(find.text('Zusagen'), findsNothing);
    expect(find.text('Trainer kontaktieren'), findsOneWidget);
    expect(repo.writes, isEmpty);
  });
  testWidgets('read-only parent preview offers no attendance write buttons',
      (tester) async {
    await _pumpHome(tester, preview: true);
    expect(find.text('Zusagen'), findsNothing);
    expect(find.text('Vorschau · nur lesen'), findsOneWidget);
  });
  testWidgets(
      'open count opens all upcoming responses, family contacts have a real destination',
      (tester) async {
    final router = await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('parent-open-responses')));
    await tester.pumpAndSettle();
    expect(
        router.routeInformationProvider.value.uri.queryParameters['open'], '1');
    expect(find.text('Abgesagt'), findsWidgets);
    router.go('/parent/family');
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('family-contact-action')));
    await tester.tap(find.byKey(const ValueKey('family-contact-action')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(),
        '/parent/messages?section=contact');
  });
  testWidgets('tournament opens master squad, not an individual fixture',
      (tester) async {
    final e =
        event('tournament', match: true, category: EventCategory.tournament);
    final router = await _pumpHome(tester, events: [e]);
    await tester.ensureVisible(find.text('Kader & Spielinfo'));
    await tester.tap(find.text('Kader & Spielinfo'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(),
        '/parent/matches/tournament?planning=tournament');
  });

  testWidgets('training link carries its date into the next month',
      (tester) async {
    final e = event('next-month', days: 32);
    final router = await _pumpHome(tester, events: [e]);
    await tester.tap(find.text(parentDate(e.startAt)));
    await tester.pumpAndSettle();
    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/parent/events');
    expect(uri.queryParameters['eventId'], e.id);
    expect(DateTime.parse(uri.queryParameters['date']!), e.startAt);
  });

  testWidgets(
      'generated training opens the correct child response without a calendar row',
      (tester) async {
    final p = child('mia'), e = event('generated-training');
    final router = await _pumpHome(tester,
        players: [p], events: [], repository: _Repository([response(e, p)]));
    await tester.tap(find.text(parentDate(e.startAt)));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/parent/responses');
    expect(
        router.routeInformationProvider.value.uri.queryParameters['playerId'],
        'mia');
  });

  testWidgets('profile menu preserves account and display settings at 320 px',
      (tester) async {
    final router = await _pumpHome(tester, width: 320);
    await tester.tap(find.byKey(const ValueKey('family-account-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Mein Konto'), findsOneWidget);
    expect(find.text('Darstellung & Aktualisierung'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Mein Konto'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/parent/account');
  });

  testWidgets('captures implemented A and B, plus dark mode', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final entry in [
      (false, false, 'start'),
      (true, false, 'familie'),
      (false, true, 'start-dark')
    ]) {
      await _pumpHome(tester, family: entry.$1, dark: entry.$2, height: 1000);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')));
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../artifacts/parent-home/${entry.$3}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
  });
}
