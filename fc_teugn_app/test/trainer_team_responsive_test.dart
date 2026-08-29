import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/core/team_game_format.dart';
import 'package:fc_teugn_app/features/trainer/trainer_team_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ageGroup = AgeGroupSummary(
    id: 'age-e',
    name: 'E-Jugend',
    code: 'E',
  );
  const team = TeamSummary(
    id: 'team-e1',
    name: 'E1',
    apiDisplayName: 'E1-Jugend',
    ageGroup: ageGroup,
    seasonName: '2026/27',
    gameFormat: TeamGameFormat.football7,
  );
  final organization = OrganizationContext(
    club: const ClubSummary(
      id: 'club',
      name: 'FC Teugn',
      shortName: 'FCT',
      primaryColor: '#171918',
      accentColor: '#FFE600',
    ),
    season: SeasonSummary(
      id: 'season',
      name: '2026/27',
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2027, 6, 30),
      isActive: true,
    ),
    currentTeam: team,
    ageGroups: [ageGroup],
    teams: [team],
    permissions: const {},
    metrics: const OrganizationMetrics(
      players: 12,
      members: 24,
      upcomingEvents: 4,
      pendingApprovals: 0,
    ),
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          organizationProvider.overrideWith((ref) async => organization),
          playersProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(body: TrainerTeamPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mobile team tiles show their complete labels without clipping',
      (tester) async {
    await pumpPage(tester, size: const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tile = find.byKey(const ValueKey('team-action-operations'));
    final subtitle = find.text('Organisation im Teamalltag');
    expect(tile, findsOneWidget);
    expect(subtitle, findsOneWidget);
    expect(
        tester.getRect(subtitle).bottom, lessThan(tester.getRect(tile).bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('foldable cover width switches team actions to compact rows',
      (tester) async {
    await pumpPage(tester, size: const Size(280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final players = tester.getRect(
      find.byKey(const ValueKey('team-action-players')),
    );
    final lineup = tester.getRect(
      find.byKey(const ValueKey('team-action-lineup')),
    );
    expect(players.width, greaterThan(240));
    expect(lineup.top, greaterThan(players.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger system text keeps every team tile readable',
      (tester) async {
    await pumpPage(
      tester,
      size: const Size(390, 844),
      textScale: 1.5,
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tile = find.byKey(const ValueKey('team-action-operations'));
    final subtitle = find.text('Organisation im Teamalltag');
    await tester.scrollUntilVisible(tile, 180);
    await tester.pumpAndSettle();
    expect(tester.getRect(tile).width, greaterThan(330));
    expect(
        tester.getRect(subtitle).bottom, lessThan(tester.getRect(tile).bottom));
    expect(tester.takeException(), isNull);
  });
}
