import 'package:fc_teugn_app/core/models/organization.dart';

OrganizationContext auditOrganization({bool twoTeams = false}) {
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
  const secondTeam = TeamSummary(
    id: 'team-e2',
    name: 'E2',
    ageGroup: ageGroup,
    seasonName: '2026/27',
    birthYears: [2016],
    trainingLocation: 'Platz 2 oben',
    trainingTimes: ['Donnerstag 17:00–18:30'],
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
    teams: [team, if (twoTeams) secondTeam],
    permissions: const {'MANAGE_TEAM'},
    metrics: const OrganizationMetrics(
      players: 25,
      members: 25,
      upcomingEvents: 24,
      pendingApprovals: 0,
    ),
    workingContext: WorkingContext(
      ageGroupId: 'age-e',
      teamIds: ['team-e1', if (twoTeams) 'team-e2'],
      includeAllTeams: twoTeams,
    ),
  );
}
