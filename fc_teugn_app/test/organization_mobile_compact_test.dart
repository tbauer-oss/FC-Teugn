import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/organization/organization_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in const [320.0, 390.0, 480.0, 673.0]) {
    testWidgets('organization stays compact at ${width.toInt()} px',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            organizationProvider.overrideWith((ref) async => _organization()),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: OrganizationPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hero = tester.getRect(
        find.byKey(const ValueKey('organization-club-hero')),
      );
      final teamCard = tester.getRect(
        find.byKey(const ValueKey('compact-team-card-team-e1')),
      );
      expect(hero.height, lessThan(150));
      expect(teamCard.height, lessThan(390));
      expect(find.text('Team-Management'), findsOneWidget);
      expect(find.text('Weitere Mannschaftsdaten'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

OrganizationContext _organization() {
  const ageGroup = AgeGroupSummary(
    id: 'age-e',
    name: 'E-Jugend',
    code: 'E',
  );
  final team = TeamSummary(
    id: 'team-e1',
    name: 'E1',
    ageGroup: ageGroup,
    seasonName: '2026/27',
    birthYears: const [2015, 2016],
    trainingLocation: 'Platz 1 unten',
    trainingTimes: const ['Mittwoch 17:00–18:30'],
    seasonStartDate: DateTime(2026, 7, 1),
    seasonEndDate: DateTime(2027, 6, 30),
    staff: const [
      TeamStaffMember(
        id: 'coach-1',
        name: 'Max Trainer',
        role: 'COACH',
      ),
    ],
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
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2027, 6, 30),
      isActive: true,
    ),
    currentTeam: team,
    ageGroups: const [ageGroup],
    teams: [team],
    permissions: const {'MANAGE_TEAM'},
    metrics: const OrganizationMetrics(
      players: 25,
      members: 25,
      upcomingEvents: 24,
      pendingApprovals: 0,
    ),
  );
}
