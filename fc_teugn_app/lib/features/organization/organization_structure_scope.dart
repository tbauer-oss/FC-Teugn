import '../../core/models/organization.dart';
import '../../core/models/user.dart';

class OrganizationStructureScope {
  const OrganizationStructureScope({
    required this.ageGroups,
    required this.teams,
  });

  final List<AgeGroupSummary> ageGroups;
  final List<TeamSummary> teams;
}

bool hasOrganizationWideTeamScope(UserRole? role) => switch (role) {
      UserRole.superAdmin ||
      UserRole.clubAdmin ||
      UserRole.youthDirector =>
        true,
      _ => false,
    };

/// Applies the selected working context again in the client.
///
/// The API is the authorization boundary. This additional filter prevents an
/// old or cached organization response from briefly rendering unrelated youth
/// sections while a newly selected context is loading.
OrganizationStructureScope organizationStructureScope(
  OrganizationContext organization,
  UserRole? role,
) {
  if (hasOrganizationWideTeamScope(role)) {
    return OrganizationStructureScope(
      ageGroups: organization.ageGroups,
      teams: organization.teams,
    );
  }

  final selectedAgeGroupId = organization.workingContext.ageGroupId.isNotEmpty
      ? organization.workingContext.ageGroupId
      : organization.currentTeam.ageGroup.id;
  final selectedTeamIds = organization.workingContext.teamIds.toSet()
    ..add(organization.currentTeam.id);
  final teams = organization.teams
      .where(
        (team) =>
            team.ageGroup.id == selectedAgeGroupId &&
            selectedTeamIds.contains(team.id),
      )
      .toList();
  if (organization.currentTeam.ageGroup.id == selectedAgeGroupId &&
      teams.every((team) => team.id != organization.currentTeam.id)) {
    teams.insert(0, organization.currentTeam);
  }

  final ageGroups = organization.ageGroups
      .where((ageGroup) => ageGroup.id == selectedAgeGroupId)
      .toList();
  if (ageGroups.isEmpty &&
      organization.currentTeam.ageGroup.id == selectedAgeGroupId) {
    ageGroups.add(organization.currentTeam.ageGroup);
  }

  return OrganizationStructureScope(ageGroups: ageGroups, teams: teams);
}
