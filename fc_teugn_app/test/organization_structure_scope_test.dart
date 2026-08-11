import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/features/organization/organization_structure_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trainer roles see only teams from the selected youth', () {
    for (final role in [
      UserRole.trainerAdmin,
      UserRole.coach,
      UserRole.trainer,
      UserRole.assistantCoach,
      UserRole.teamManager,
    ]) {
      final scope = organizationStructureScope(_organization(), role);
      expect(scope.ageGroups.map((group) => group.code), ['E']);
      expect(scope.teams.map((team) => team.id), ['e-1', 'e-2']);
    }
  });

  test('single-team context hides the other squad in the selected youth', () {
    final scope = organizationStructureScope(
      _organization(teamIds: const ['e-1'], includeAllTeams: false),
      UserRole.assistantCoach,
    );

    expect(scope.ageGroups.map((group) => group.code), ['E']);
    expect(scope.teams.map((team) => team.id), ['e-1']);
  });

  test('club-wide roles retain the complete organization structure', () {
    for (final role in [
      UserRole.superAdmin,
      UserRole.clubAdmin,
      UserRole.youthDirector,
    ]) {
      final scope = organizationStructureScope(_organization(), role);
      expect(scope.ageGroups.map((group) => group.code), ['G', 'F', 'E']);
      expect(scope.teams.map((team) => team.id), ['g-1', 'f-1', 'e-1', 'e-2']);
    }
  });
}

const _ageG = AgeGroupSummary(id: 'age-g', name: 'G-Jugend', code: 'G');
const _ageF = AgeGroupSummary(id: 'age-f', name: 'F-Jugend', code: 'F');
const _ageE = AgeGroupSummary(id: 'age-e', name: 'E-Jugend', code: 'E');

OrganizationContext _organization({
  List<String> teamIds = const ['e-1', 'e-2'],
  bool includeAllTeams = true,
}) {
  const teams = [
    TeamSummary(id: 'g-1', name: 'G1', ageGroup: _ageG, seasonName: '2026/27'),
    TeamSummary(id: 'f-1', name: 'F1', ageGroup: _ageF, seasonName: '2026/27'),
    TeamSummary(id: 'e-1', name: 'E1', ageGroup: _ageE, seasonName: '2026/27'),
    TeamSummary(id: 'e-2', name: 'E2', ageGroup: _ageE, seasonName: '2026/27'),
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
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2027, 6, 30),
      isActive: true,
    ),
    currentTeam: teams[2],
    ageGroups: const [_ageG, _ageF, _ageE],
    teams: teams,
    permissions: const {'VIEW_TEAM'},
    metrics: const OrganizationMetrics(
      players: 20,
      members: 30,
      upcomingEvents: 4,
      pendingApprovals: 0,
    ),
    workingContext: WorkingContext(
      ageGroupId: 'age-e',
      teamIds: teamIds,
      includeAllTeams: includeAllTeams,
    ),
  );
}
