import 'dart:ui';

import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/competition.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/core/widgets/adaptive_layout.dart';
import 'package:fc_teugn_app/features/trainer/trainer_matches_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _ageGroup = AgeGroupSummary(
  id: 'age-e',
  name: 'E-Jugend',
  code: 'E',
);

const _team = TeamSummary(
  id: 'team-e1',
  name: 'E1',
  ageGroup: _ageGroup,
  seasonName: '2026/27',
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
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2027, 6, 30),
        isActive: true,
      ),
      currentTeam: _team,
      ageGroups: const [_ageGroup],
      teams: const [_team],
      permissions: const {},
      metrics: const OrganizationMetrics(
        players: 0,
        members: 0,
        upcomingEvents: 1,
        pendingApprovals: 0,
      ),
    );

EventModel _tournament() => EventModel(
      id: 'tournament-1',
      teamId: _team.id,
      type: EventType.match,
      category: EventCategory.tournament,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: '3. Hopfenbach-Cup mit langem Turniernamen',
      startAt: DateTime(2026, 9, 12, 15),
      endAt: DateTime(2026, 9, 12, 19),
      location: 'Hopfenbach-Arena mit langem Ortsnamen',
      attendanceFinalized: false,
      targetTeams: const [],
      attachments: const [],
      attendance: const [],
      attendanceSummary: const AttendanceSummary(),
      missingAttendance: const [],
      carpoolOffers: const [],
      capabilities: const EventCapabilities(
        canManage: true,
        canCancel: true,
        canDelete: true,
      ),
      reminderMinutes: const [],
    );

class _TournamentRepository extends DataRepository {
  _TournamentRepository() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<List<OpponentModel>> opponents(String ageGroupId) async => [];

  @override
  Future<List<OpponentClubModel>> opponentClubs() async => [];

  @override
  Future<OpponentClubModel> saveOpponentClub({
    String? id,
    required String name,
    String? shortName,
    String? venue,
    String? address,
  }) async =>
      OpponentClubModel(
        id: id ?? 'club-new',
        name: name,
        teams: const [],
        shortName: shortName,
        venue: venue,
        address: address,
      );

  @override
  Future<OpponentModel> saveOpponent({
    String? id,
    required String ageGroupId,
    String? teamId,
    String? opponentClubId,
    String? clubName,
    required String teamDesignation,
    String? shortName,
    String? venue,
    String? address,
  }) async =>
      OpponentModel(
        id: id ?? 'opponent-new',
        ageGroupId: ageGroupId,
        opponentClubId: opponentClubId ?? 'club-new',
        teamId: teamId,
        clubName: clubName ?? '',
        teamDesignation: teamDesignation,
        displayName: '${clubName ?? ''} $teamDesignation'.trim(),
      );
}

Widget _page({DataRepository? repository}) => ProviderScope(
      overrides: [
        eventsProvider.overrideWith((ref) async => [_tournament()]),
        organizationProvider.overrideWith((ref) async => _organization()),
        if (repository != null)
          repositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: TrainerMatchesPage()),
      ),
    );

void main() {
  for (final width in const [320.0, 360.0, 390.0, 480.0, 599.0]) {
    testWidgets('match overview is compact at ${width.toInt()} px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: const TextScaler.linear(1.2),
          ),
          child: _page(),
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find.byKey(const ValueKey('match-card-tournament-1')),
      );
      expect(card.height, lessThan(230));
      expect(find.text('Planen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('matches-page-actions')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('match overview uses one compact foldable pane', (tester) async {
    const viewport = Size(673, 841);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsProvider.overrideWith((ref) async => [_tournament()]),
          organizationProvider.overrideWith((ref) async => _organization()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: viewport,
              displayFeatures: [
                DisplayFeature(
                  bounds: Rect.fromLTWH(330, 0, 13, 841),
                  type: DisplayFeatureType.hinge,
                  state: DisplayFeatureState.unknown,
                ),
              ],
            ),
            child: AdaptiveHingePane(
              child: Scaffold(body: TrainerMatchesPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(
      find.byKey(const ValueKey('match-card-tournament-1')),
    );
    expect(card.right <= 330 || card.left >= 343, isTrue);
    expect(card.height, lessThan(230));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing tournament opponent can be added in place',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(repository: _TournamentRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Planen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partie'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tournament-opponent-field-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tournament-opponent-picker-add')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('tournament-opponent-club-name')),
      'ATSV Test',
    );
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();

    expect(find.text('ATSV Test E1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
