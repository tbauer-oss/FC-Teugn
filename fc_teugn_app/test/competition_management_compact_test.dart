import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/competition.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/features/matches/competition_management_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opponent clubs use compact rows with editable team chips',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: CompetitionManagementDialog(
          repository: _CompetitionRepository(),
          organization: _organization,
          isSystemAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ATSV Kelheim'), findsOneWidget);
    expect(find.text('E1'), findsOneWidget);
    expect(find.text('E2'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(find.byType(ExpansionTile), findsNothing);

    final size = tester.getSize(
      find.byKey(const ValueKey('opponent-club-club-1')),
    );
    expect(size.height, lessThan(70));
  });

  testWidgets('compact opponent rows wrap safely on phones', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: CompetitionManagementDialog(
          repository: _CompetitionRepository(),
          organization: _organization,
          isSystemAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ATSV Kelheim'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const ValueKey('opponent-club-club-1'))).height,
      lessThan(115),
    );
    expect(tester.takeException(), isNull);
  });
}

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

final _organization = OrganizationContext(
  club: const ClubSummary(
    id: 'club-fct',
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
  ageGroups: [_ageGroup],
  teams: [_team],
  permissions: const {},
  metrics: const OrganizationMetrics(
    players: 0,
    members: 0,
    upcomingEvents: 0,
    pendingApprovals: 0,
  ),
  workingContext: const WorkingContext(
    ageGroupId: 'age-e',
    teamIds: ['team-e1'],
    includeAllTeams: false,
  ),
);

class _CompetitionRepository extends DataRepository {
  _CompetitionRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  @override
  Future<List<OpponentClubModel>> opponentClubs() async => const [
        OpponentClubModel(
          id: 'club-1',
          name: 'ATSV Kelheim',
          venue: 'Sportzentrum Kelheim',
          address: 'Rennweg 66, Kelheim',
          teams: [],
        ),
      ];

  @override
  Future<List<OpponentModel>> opponents(String ageGroupId) async => const [
        OpponentModel(
          id: 'opponent-e1',
          ageGroupId: 'age-e',
          opponentClubId: 'club-1',
          clubName: 'ATSV Kelheim',
          teamDesignation: 'E1',
          displayName: 'ATSV Kelheim E1',
        ),
        OpponentModel(
          id: 'opponent-e2',
          ageGroupId: 'age-e',
          opponentClubId: 'club-1',
          clubName: 'ATSV Kelheim',
          teamDesignation: 'E2',
          displayName: 'ATSV Kelheim E2',
        ),
      ];

  @override
  Future<List<LeagueModel>> leagues(String ageGroupId) async => const [];
}
