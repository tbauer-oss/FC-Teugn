import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/dashboard_summary.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/models/team_operations.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/trainer/trainer_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _ageGroup = AgeGroupSummary(
  id: 'age-e',
  name: 'E-Jugend',
  code: 'E',
);
const _teamE1 = TeamSummary(
  id: 'team-e1',
  name: 'E1',
  apiDisplayName: 'E1-Jugend',
  ageGroup: _ageGroup,
  seasonName: '2026/27',
);
const _teamE2 = TeamSummary(
  id: 'team-e2',
  name: 'E2',
  apiDisplayName: 'E2-Jugend',
  ageGroup: _ageGroup,
  seasonName: '2026/27',
);
const _operations = TeamOperationsOverview(
  teamId: 'team-e1',
  canManage: true,
  tasks: [],
  equipment: [],
  checklistTemplates: [],
  checklistRuns: [],
  members: [],
  players: [],
);

class _AttendanceCorrectionRepository extends DataRepository {
  _AttendanceCorrectionRepository(this.updatedEvent, {this.removedEvent})
      : super(ApiClient(baseUrl: 'http://localhost'));

  final EventModel updatedEvent;
  final EventModel? removedEvent;
  final List<({String eventId, String playerId, AttendanceStatus status})>
      calls = [];
  final List<({String eventId, String playerId})> removalCalls = [];

  @override
  Future<EventModel> setAttendance({
    required String eventId,
    required String playerId,
    required AttendanceStatus status,
    String? reason,
    bool? goalkeeperAvailable,
    bool personalResponse = false,
  }) async {
    calls.add((eventId: eventId, playerId: playerId, status: status));
    return updatedEvent;
  }

  @override
  Future<EventModel> removeEventParticipant({
    required String eventId,
    required String playerId,
  }) async {
    removalCalls.add((eventId: eventId, playerId: playerId));
    return removedEvent ?? updatedEvent;
  }
}

OrganizationContext _organization() => OrganizationContext(
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
        startDate: DateTime(2026, 7),
        endDate: DateTime(2027, 6, 30),
        isActive: true,
      ),
      currentTeam: _teamE1,
      ageGroups: const [_ageGroup],
      teams: const [_teamE1, _teamE2],
      permissions: const {},
      metrics: const OrganizationMetrics(
        players: 0,
        members: 0,
        upcomingEvents: 2,
        pendingApprovals: 0,
      ),
      workingContext: const WorkingContext(
        ageGroupId: 'age-e',
        teamIds: ['team-e1', 'team-e2'],
        includeAllTeams: true,
      ),
    );

EventModel _event({
  required String id,
  required EventCategory category,
  required DateTime startAt,
  String teamId = 'team-e1',
  List<EventTeam> targetTeams = const [],
  List<EventAttendance> attendance = const [],
  AttendanceSummary attendanceSummary = const AttendanceSummary(),
  List<MissingAttendance> missingAttendance = const [],
  EventCapabilities capabilities = const EventCapabilities(),
  EventStatus status = EventStatus.scheduled,
  bool isHiddenRegularOccurrence = false,
  List<String> excludedParticipantPlayerIds = const [],
}) =>
    EventModel(
      id: id,
      teamId: teamId,
      type: category == EventCategory.training
          ? EventType.training
          : EventType.event,
      category: category,
      status: status,
      visibility: EventVisibility.team,
      title: category.label,
      startAt: startAt,
      location: 'Teugn Sportplatz',
      attendanceFinalized: false,
      targetTeams: targetTeams,
      attachments: const [],
      attendance: attendance,
      attendanceSummary: attendanceSummary,
      missingAttendance: missingAttendance,
      carpoolOffers: const [],
      capabilities: capabilities,
      reminderMinutes: const [],
      isHiddenRegularOccurrence: isHiddenRegularOccurrence,
      excludedParticipantPlayerIds: excludedParticipantPlayerIds,
    );

OrganizationContext _regularTrainingOrganization() {
  final seasonStart = DateTime(2026, 7);
  final seasonEnd = DateTime(2027, 6, 30);
  final teams = [
    TeamSummary(
      id: 'team-e1',
      name: 'E1',
      apiDisplayName: 'E1-Jugend',
      ageGroup: _ageGroup,
      seasonName: '2026/27',
      trainingLocation: 'Platz 1 unten',
      trainingTimes: const [
        'Dienstag 17:15–18:30 · Platz: Platz 1 unten',
      ],
      seasonStartDate: seasonStart,
      seasonEndDate: seasonEnd,
    ),
    TeamSummary(
      id: 'team-e2',
      name: 'E2',
      apiDisplayName: 'E2-Jugend',
      ageGroup: _ageGroup,
      seasonName: '2026/27',
      trainingLocation: 'Platz 1 unten',
      trainingTimes: const [
        'Dienstag 17:15–18:30 · Platz: Platz 1 unten',
      ],
      seasonStartDate: seasonStart,
      seasonEndDate: seasonEnd,
    ),
  ];
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
      startDate: seasonStart,
      endDate: seasonEnd,
      isActive: true,
    ),
    currentTeam: teams.first,
    ageGroups: const [_ageGroup],
    teams: teams,
    permissions: const {},
    metrics: const OrganizationMetrics(
      players: 0,
      members: 0,
      upcomingEvents: 0,
      pendingApprovals: 0,
    ),
    workingContext: const WorkingContext(
      ageGroupId: 'age-e',
      teamIds: ['team-e1', 'team-e2'],
      includeAllTeams: true,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

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

  test('dashboard selects the next training for every context team', () {
    final selected = nextTrainingsByTeamForDashboard(
      [
        _event(
          id: 'training-e1-later',
          teamId: 'team-e1',
          category: EventCategory.training,
          startAt: DateTime(2026, 8, 29, 17, 15),
        ),
        _event(
          id: 'training-e2-next',
          teamId: 'team-e2',
          category: EventCategory.training,
          startAt: DateTime(2026, 8, 25, 17, 15),
        ),
        _event(
          id: 'training-e1-next',
          teamId: 'team-e1',
          category: EventCategory.training,
          startAt: DateTime(2026, 8, 25, 17, 15),
        ),
      ],
      const {'team-e1', 'team-e2'},
    );

    expect(selected.map((event) => event.id).toSet(), {
      'training-e1-next',
      'training-e2-next',
    });
  });

  test('dashboard keeps every selected training from today visible', () {
    final selected = todaysTrainingsForDashboard(
      [
        _event(
          id: 'training-e1-today',
          teamId: 'team-e1',
          category: EventCategory.training,
          startAt: DateTime(2026, 8, 25, 17, 15),
        ),
        _event(
          id: 'training-e2-today',
          teamId: 'team-e2',
          category: EventCategory.training,
          startAt: DateTime(2026, 8, 25, 18),
        ),
        _event(
          id: 'training-tomorrow',
          teamId: 'team-e1',
          category: EventCategory.training,
          startAt: DateTime(2026, 8, 26, 17, 15),
        ),
      ],
      const {'team-e1', 'team-e2'},
      DateTime(2026, 8, 25, 20),
    );

    expect(selected.map((event) => event.id).toList(), [
      'training-e1-today',
      'training-e2-today',
    ]);
  });

  test('a deleted E2 occurrence cannot suppress the parallel E1 occurrence',
      () {
    final deletedStart = DateTime(2026, 9, 1, 17, 15);
    final events = dashboardEventsForContext(
      [
        _event(
          id: 'regular-training:team-e2:${deletedStart.millisecondsSinceEpoch}',
          teamId: 'team-e2',
          category: EventCategory.training,
          startAt: deletedStart,
          targetTeams: const [
            EventTeam(id: 'team-e1', name: 'E1', ageGroupCode: 'E1'),
            EventTeam(id: 'team-e2', name: 'E2', ageGroupCode: 'E2'),
          ],
          status: EventStatus.cancelled,
          isHiddenRegularOccurrence: true,
        ),
      ],
      _regularTrainingOrganization(),
      DateTime(2026, 8, 27),
      const {'team-e1', 'team-e2'},
    );

    final e1 = events.singleWhere((event) => event.teamId == 'team-e1');
    final e2 = events.singleWhere((event) => event.teamId == 'team-e2');
    expect(e1.startAt, deletedStart);
    expect(e2.startAt, DateTime(2026, 9, 8, 17, 15));
  });

  test('deleted parallel occurrences are skipped for both dashboard teams', () {
    final deletedStart = DateTime(2026, 9, 1, 17, 15);
    final events = dashboardEventsForContext(
      [
        for (final teamId in const ['team-e1', 'team-e2'])
          _event(
            id: 'regular-training:$teamId:${deletedStart.millisecondsSinceEpoch}',
            teamId: teamId,
            category: EventCategory.training,
            startAt: deletedStart,
            status: EventStatus.cancelled,
            isHiddenRegularOccurrence: true,
          ),
      ],
      _regularTrainingOrganization(),
      DateTime(2026, 8, 27),
      const {'team-e1', 'team-e2'},
    );

    expect(events, hasLength(2));
    expect(
      events.every((event) => event.startAt == DateTime(2026, 9, 8, 17, 15)),
      isTrue,
    );
  });

  test('dashboard counters include replies and every open player', () {
    final counts = trainingDashboardCounts(
      const AttendanceSummary(yes: 9, no: 2, maybe: 1, unknown: 3),
      missingCount: 3,
      rosterCount: 15,
    );

    expect(counts, (yes: 9, no: 2, open: 4, total: 15));
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

  testWidgets(
      'missing responses open the trainer overview even with a linked child',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final startAt = DateTime(now.year, now.month, now.day, 23);
    final event = _event(
      id: 'training-next',
      category: EventCategory.training,
      startAt: startAt,
      attendance: const [
        EventAttendance(
          id: 'attendance-anna',
          playerId: 'player-anna',
          playerName: 'Anna Zugesagt',
          status: AttendanceStatus.yes,
        ),
      ],
      attendanceSummary: const AttendanceSummary(yes: 1, unknown: 1),
      missingAttendance: const [
        MissingAttendance(id: 'player-ben', name: 'Ben Offen'),
      ],
      capabilities: const EventCapabilities(canManage: true),
    );
    final repository = _AttendanceCorrectionRepository(
      _event(
        id: 'training-next',
        category: EventCategory.training,
        startAt: startAt,
        attendance: const [
          EventAttendance(
            id: 'attendance-anna',
            playerId: 'player-anna',
            playerName: 'Anna Zugesagt',
            status: AttendanceStatus.yes,
          ),
          EventAttendance(
            id: 'attendance-ben',
            playerId: 'player-ben',
            playerName: 'Ben Offen',
            status: AttendanceStatus.yes,
          ),
        ],
        attendanceSummary: const AttendanceSummary(yes: 2),
        capabilities: const EventCapabilities(canManage: true),
      ),
      removedEvent: _event(
        id: 'training-next',
        category: EventCategory.training,
        startAt: startAt,
        attendance: const [
          EventAttendance(
            id: 'attendance-anna',
            playerId: 'player-anna',
            playerName: 'Anna Zugesagt',
            status: AttendanceStatus.yes,
          ),
        ],
        attendanceSummary: const AttendanceSummary(yes: 1),
        excludedParticipantPlayerIds: const ['player-ben'],
        capabilities: const EventCapabilities(canManage: true),
      ),
    );
    const players = [
      PlayerModel(
        id: 'player-anna',
        teamId: 'team-e1',
        firstName: 'Anna',
        lastName: 'Zugesagt',
        status: PlayerStatus.active,
        dominantFoot: DominantFoot.unknown,
      ),
      PlayerModel(
        id: 'player-ben',
        teamId: 'team-e1',
        firstName: 'Ben',
        lastName: 'Offen',
        status: PlayerStatus.active,
        dominantFoot: DominantFoot.unknown,
      ),
    ];
    final personalResponse = PersonalResponseModel(
      eventId: event.id,
      playerId: 'player-ben',
      playerName: 'Ben Offen',
      teamName: 'E1-Jugend',
      ageGroupCode: 'E1',
      title: 'Training',
      type: 'TRAINING',
      category: 'TRAINING',
      startAt: startAt,
      location: 'Teugn Sportplatz',
      responseStatus: AttendanceStatus.unknown,
      canRespond: true,
      isOverdue: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          playersProvider.overrideWith((ref) async => players),
          trainerDashboardSummaryProvider.overrideWith(
            (ref) async => DashboardSummary(
              players: players,
              events: [event],
              notifications: const [],
            ),
          ),
          organizationProvider.overrideWith((ref) async => _organization()),
          teamOperationsProvider('team-e1')
              .overrideWith((ref) async => _operations),
          pendingUsersProvider.overrideWith((ref) async => <AppUser>[]),
          personalResponsesProvider.overrideWith(
            (ref) async => [personalResponse],
          ),
          liveNotificationsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: TrainerDashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final responses = find.byKey(const ValueKey('today-training-summary'));
    await tester.ensureVisible(responses);
    await tester.tap(responses);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('combined-training-responses-sheet')),
      findsOneWidget,
    );
    expect(find.text('Alle Rückmeldungen'), findsOneWidget);
    expect(find.textContaining('E1'), findsWidgets);
    expect(find.textContaining('Teugn Sportplatz'), findsOneWidget);
    expect(find.text('Anna Zugesagt'), findsOneWidget);
    expect(find.text('Ben Offen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('trainer-training-reminder')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('attendance-status-menu-training-next-player-ben'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'attendance-status-choice-training-next-player-ben-YES',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.eventId, 'training-next');
    expect(repository.calls.single.playerId, 'player-ben');
    expect(repository.calls.single.status, AttendanceStatus.yes);
    expect(find.text('Ben Offen: Zugesagt gespeichert.'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('attendance-status-menu-training-next-player-ben'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'attendance-remove-choice-training-next-player-ben',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aus Termin entfernen?'), findsOneWidget);
    expect(
      find.textContaining('Mannschaft und Spielerprofil bleiben erhalten'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-remove-event-participant')),
    );
    await tester.pumpAndSettle();
    expect(repository.removalCalls, hasLength(1));
    expect(repository.removalCalls.single.eventId, 'training-next');
    expect(repository.removalCalls.single.playerId, 'player-ben');
    expect(find.text('Ben Offen'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('trainer-training-reminder')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alle zum Training erinnern'), findsOneWidget);
    expect(find.text('Individuelle Nachricht (optional)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard combines responses for every selected team',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final startAt = DateTime(now.year, now.month, now.day, 23);
    final events = [
      _event(
        id: 'training-e1',
        teamId: 'team-e1',
        category: EventCategory.training,
        startAt: startAt,
        targetTeams: const [
          EventTeam(id: 'team-e1', name: 'E1', ageGroupCode: 'E1'),
        ],
        attendanceSummary: const AttendanceSummary(unknown: 2),
        missingAttendance: const [
          MissingAttendance(id: 'player-e1-a', name: 'Anna Adler'),
          MissingAttendance(id: 'player-e1-b', name: 'Ben Bauer'),
        ],
      ),
      _event(
        id: 'training-e2',
        teamId: 'team-e2',
        category: EventCategory.training,
        startAt: startAt.add(const Duration(minutes: 15)),
        targetTeams: const [
          EventTeam(id: 'team-e2', name: 'E2', ageGroupCode: 'E2'),
        ],
        attendanceSummary: const AttendanceSummary(unknown: 3),
        missingAttendance: const [
          MissingAttendance(id: 'player-e2-a', name: 'Carla Christl'),
          MissingAttendance(id: 'player-e2-b', name: 'David Dietl'),
          MissingAttendance(id: 'player-e2-c', name: 'Eva Ebner'),
        ],
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playersProvider.overrideWith((ref) async => <PlayerModel>[]),
          trainerDashboardSummaryProvider.overrideWith(
            (ref) async => DashboardSummary(
              players: const [],
              events: events,
              notifications: const [],
            ),
          ),
          organizationProvider.overrideWith((ref) async => _organization()),
          teamOperationsProvider('team-e1')
              .overrideWith((ref) async => _operations),
          pendingUsersProvider.overrideWith((ref) async => <AppUser>[]),
          personalResponsesProvider.overrideWith((ref) async => const []),
          liveNotificationsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: TrainerDashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Rückmeldungen fehlen'), findsNothing);
    expect(
        find.byKey(const ValueKey('today-training-summary')), findsOneWidget);
    expect(find.textContaining('Heute'), findsOneWidget);
    expect(find.text('5 offen'), findsOneWidget);
    expect(find.textContaining('E1-Jugend'), findsWidgets);
    expect(find.textContaining('E2-Jugend'), findsWidgets);

    final combinedButton = find.byKey(const ValueKey('today-training-summary'));
    await tester.ensureVisible(combinedButton);
    await tester.tap(combinedButton);
    await tester.pumpAndSettle();

    final combinedSheet =
        find.byKey(const ValueKey('combined-training-responses-sheet'));
    expect(combinedSheet, findsOneWidget);
    expect(
      find.descendant(
        of: combinedSheet,
        matching: find.text('Alle Rückmeldungen'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('training-response-person-Anna Adler-E1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('training-response-person-Carla Christl-E2')),
      findsOneWidget,
    );
    expect(find.text('E1'), findsWidgets);
    expect(find.text('E2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
