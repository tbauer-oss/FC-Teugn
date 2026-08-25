import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/parent/parent_matches_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next active match is first and completed matches follow newest first',
      () {
    final now = DateTime(2026, 8, 24, 12);
    final sorted = sortParentMatchesForOverview(
      [
        _match('past-old', DateTime(2026, 8, 10, 10)),
        _match('future-later', DateTime(2026, 9, 5, 10)),
        _match('past-new', DateTime(2026, 8, 20, 10)),
        _match(
          'currently-playing',
          DateTime(2026, 8, 24, 11, 30),
          endAt: DateTime(2026, 8, 24, 12, 30),
        ),
        _match('future-next', DateTime(2026, 8, 25, 10)),
      ],
      now: now,
    );

    expect(
      sorted.map((event) => event.id),
      [
        'currently-playing',
        'future-next',
        'future-later',
        'past-new',
        'past-old',
      ],
    );
  });

  testWidgets(
    'parent match cards stay readable on a narrow phone with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final match = EventModel(
        id: 'match-1',
        teamId: 'team-1',
        type: EventType.match,
        category: EventCategory.friendlyMatch,
        status: EventStatus.scheduled,
        visibility: EventVisibility.team,
        title: 'Freundschaftsspiel mit einem besonders langen Titel',
        startAt: DateTime(2026, 8, 15, 10, 30),
        location: 'Sportanlage mit einem besonders langen Ortsnamen',
        attendanceFinalized: false,
        targetTeams: const [],
        attachments: const [],
        attendance: const [],
        attendanceSummary: const AttendanceSummary(),
        missingAttendance: const [],
        carpoolOffers: const [],
        capabilities: const EventCapabilities(),
        reminderMinutes: const [],
        matchDetails: const MatchDetails(
          opponent: 'Sehr langer gegnerischer Vereinsname',
          isHome: true,
          competition: 'Freundschaftsspiel',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchEventsProvider.overrideWith((ref) async => [match]),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.35),
              ),
              child: Scaffold(body: ParentMatchesPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('FC Teugn – Sehr langer gegnerischer Vereinsname'),
        findsOneWidget,
      );
      expect(find.text('Heim'), findsOneWidget);
      expect(find.text('Spieltag öffnen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('away match shows the home side and home score first',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final match = EventModel.fromJson({
      'id': 'away-match',
      'teamId': 'team-1',
      'type': 'MATCH',
      'category': 'LEAGUE_MATCH',
      'status': 'SCHEDULED',
      'visibility': 'TEAM',
      'title': 'Legacy-Titel',
      'ownTeam': {
        'name': '(SG) SV Saal/Donau',
        'shortName': 'SG Saal/Donau',
        'isPlayingCommunity': true,
      },
      'startAt': '2026-09-18T16:00:00.000Z',
      'location': 'Thaldorf',
      'targetTeams': [],
      'attachments': [],
      'attendance': [],
      'missingAttendance': [],
      'carpoolOffers': [],
      'carpoolNeeds': [],
      'matchDetails': {
        'opponent': 'SC Thaldorf E1',
        'isHome': false,
        'ourGoals': 2,
        'theirGoals': 3,
        'competition': 'Pflichtspiel',
      },
      'capabilities': <String, dynamic>{},
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchEventsProvider.overrideWith((ref) async => [match]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ParentMatchesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('SC Thaldorf E1 – (SG) SV Saal/Donau'),
      findsOneWidget,
    );
    expect(find.text('Auswärts'), findsOneWidget);
    expect(find.text('3 : 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'parents can open a live tournament plan directly from the overview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tournament = EventModel(
        id: 'tournament-1',
        teamId: 'team-1',
        type: EventType.match,
        category: EventCategory.tournament,
        status: EventStatus.scheduled,
        visibility: EventVisibility.team,
        title: '3. Hopfenbach-Cup',
        startAt: DateTime(2026, 9, 12, 15),
        location: 'Hopfenbach-Arena',
        attendanceFinalized: false,
        targetTeams: const [],
        attachments: const [
          EventAttachment(
            id: 'attachment-1',
            name: meinTurnierplanAttachmentName,
            url: 'https://www.meinturnierplan.de/showit.php?id=2acei7shc3',
            mimeType: 'text/html',
          ),
        ],
        attendance: const [],
        attendanceSummary: const AttendanceSummary(),
        missingAttendance: const [],
        carpoolOffers: const [],
        capabilities: const EventCapabilities(),
        reminderMinutes: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchEventsProvider.overrideWith((ref) async => [tournament]),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: ParentMatchesPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final planButton = find.byKey(
        const ValueKey('parent-tournament-plan-tournament-1'),
      );
      expect(planButton, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(planButton);
      await tester.pumpAndSettle();

      expect(find.text('Turnierplan live öffnen'), findsOneWidget);
      expect(find.text('Live-Turnierplan laden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('parents do not see an invalid tournament plan link',
      (tester) async {
    final tournament = EventModel(
      id: 'tournament-invalid',
      teamId: 'team-1',
      type: EventType.match,
      category: EventCategory.tournament,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: 'Turnier',
      startAt: DateTime(2026, 9, 12, 15),
      location: 'Teugn',
      attendanceFinalized: false,
      targetTeams: const [],
      attachments: const [
        EventAttachment(
          id: 'attachment-invalid',
          name: meinTurnierplanAttachmentName,
          url: 'https://example.org/not-allowed',
        ),
      ],
      attendance: const [],
      attendanceSummary: const AttendanceSummary(),
      missingAttendance: const [],
      carpoolOffers: const [],
      capabilities: const EventCapabilities(),
      reminderMinutes: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchEventsProvider.overrideWith((ref) async => [tournament]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ParentMatchesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('parent-tournament-plan-tournament-invalid'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

EventModel _match(String id, DateTime startAt, {DateTime? endAt}) => EventModel(
      id: id,
      teamId: 'team-1',
      type: EventType.match,
      category: EventCategory.leagueMatch,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: id,
      startAt: startAt,
      endAt: endAt,
      location: 'Teugn',
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
