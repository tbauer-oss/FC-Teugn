import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/trainer/trainer_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _event({
  required String id,
  required EventCategory category,
  required DateTime startAt,
  List<EventAttendance> attendance = const [],
  AttendanceSummary attendanceSummary = const AttendanceSummary(),
  List<MissingAttendance> missingAttendance = const [],
}) =>
    EventModel(
      id: id,
      teamId: 'team-e1',
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
      targetTeams: const [],
      attachments: const [],
      attendance: attendance,
      attendanceSummary: attendanceSummary,
      missingAttendance: missingAttendance,
      carpoolOffers: const [],
      capabilities: const EventCapabilities(),
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
          eventsProvider.overrideWith((ref) async => [event]),
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
    expect(find.text('Anna Zugesagt'), findsOneWidget);
    expect(find.text('Ben Offen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
