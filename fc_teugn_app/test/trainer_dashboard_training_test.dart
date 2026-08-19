import 'package:fc_teugn_app/core/app_theme.dart';
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
}) =>
    EventModel(
      id: id,
      teamId: teamId,
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
      targetTeams: targetTeams,
      attachments: const [],
      attendance: attendance,
      attendanceSummary: attendanceSummary,
      missingAttendance: missingAttendance,
      carpoolOffers: const [],
      capabilities: capabilities,
      reminderMinutes: const [],
    );

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

  testWidgets(
      'missing responses open the trainer overview even with a linked child',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final startAt = DateTime.now().add(const Duration(hours: 2));
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

    final priority = find.text('1 Rückmeldungen fehlen');
    await tester.ensureVisible(priority);
    await tester.tap(priority);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('trainer-response-overview-sheet')),
      findsOneWidget,
    );
    expect(find.text('Rückmeldungen zum Training'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('trainer-response-event-details')),
      findsOneWidget,
    );
    final eventDetails = find.byKey(
      const ValueKey('trainer-response-event-details'),
    );
    expect(
      find.descendant(
        of: eventDetails,
        matching: find.textContaining('Training · E1-Jugend'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: eventDetails,
        matching: find.textContaining('Teugn Sportplatz'),
      ),
      findsOneWidget,
    );
    expect(find.text('Anna Zugesagt'), findsOneWidget);
    expect(find.text('Ben Offen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('trainer-training-reminder')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('trainer-training-reminder')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alle zum Training erinnern'), findsOneWidget);
    expect(find.text('Individuelle Nachricht (optional)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard shows missing responses for every selected team',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final startAt = DateTime.now().add(const Duration(hours: 2));
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
          MissingAttendance(id: 'player-e1-a', name: 'E1 A'),
          MissingAttendance(id: 'player-e1-b', name: 'E1 B'),
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
          MissingAttendance(id: 'player-e2-a', name: 'E2 A'),
          MissingAttendance(id: 'player-e2-b', name: 'E2 B'),
          MissingAttendance(id: 'player-e2-c', name: 'E2 C'),
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

    expect(find.text('2 Rückmeldungen fehlen'), findsOneWidget);
    expect(find.text('3 Rückmeldungen fehlen'), findsOneWidget);
    expect(find.textContaining('E1-Jugend'), findsWidgets);
    expect(find.textContaining('E2-Jugend'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
