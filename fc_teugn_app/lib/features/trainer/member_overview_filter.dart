import '../../core/models/user.dart';

enum MemberTypeFilter {
  all,
  administration,
  trainerTeam,
  parents,
  players,
  readOnly,
}

enum MemberAssignmentFilter {
  all,
  team,
  child,
  withoutAssignment,
}

enum MemberSortOrder {
  nameAscending,
  nameDescending,
  newest,
  oldest,
  role,
  status,
}

List<AppUser> filterMembersForOverview(
  Iterable<AppUser> users, {
  String query = '',
  String? ageGroupCode,
  String? teamId,
  MemberTypeFilter type = MemberTypeFilter.all,
  AccountStatus? status,
  RegistrationReviewStatus? reviewStatus,
  MemberAssignmentFilter assignment = MemberAssignmentFilter.all,
  MemberSortOrder sort = MemberSortOrder.nameAscending,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = users.where((user) {
    final assignedTeams = user.assignedTeams;
    final searchable = <String>[
      user.name,
      user.email,
      user.phone ?? '',
      user.roleLabel,
      user.registrationRequest?.childName ?? '',
      ...assignedTeams.expand(
        (membership) => [
          membership.ageGroupCode,
          membership.teamName,
        ],
      ),
      ...user.parentPlayers.expand(
        (link) => [
          link.playerName,
          link.ageGroupCode,
          link.teamName,
        ],
      ),
    ].join(' ').toLowerCase();

    final matchesQuery =
        normalizedQuery.isEmpty || searchable.contains(normalizedQuery);
    final matchesAgeGroup = ageGroupCode == null ||
        assignedTeams.any((team) => team.ageGroupCode == ageGroupCode) ||
        user.parentPlayers.any((link) => link.ageGroupCode == ageGroupCode);
    final matchesTeam = teamId == null ||
        assignedTeams.any((team) => team.teamId == teamId) ||
        user.parentPlayers.any((link) => link.teamId == teamId);
    final matchesType = switch (type) {
      MemberTypeFilter.all => true,
      MemberTypeFilter.administration => switch (user.role) {
          UserRole.superAdmin ||
          UserRole.clubAdmin ||
          UserRole.youthDirector =>
            true,
          _ => false,
        },
      MemberTypeFilter.trainerTeam => switch (user.role) {
          UserRole.coach ||
          UserRole.trainer ||
          UserRole.assistantCoach ||
          UserRole.teamManager ||
          UserRole.trainerAdmin =>
            true,
          _ => false,
        },
      MemberTypeFilter.parents => user.role == UserRole.parent,
      MemberTypeFilter.players => user.role == UserRole.player,
      MemberTypeFilter.readOnly => user.role == UserRole.readOnly,
    };
    final matchesStatus = status == null || user.status == status;
    final matchesReviewStatus = reviewStatus == null ||
        user.registrationRequest?.reviewStatus == reviewStatus;
    final hasTeam = assignedTeams.isNotEmpty;
    final hasChild = user.parentPlayers.isNotEmpty;
    final matchesAssignment = switch (assignment) {
      MemberAssignmentFilter.all => true,
      MemberAssignmentFilter.team => hasTeam,
      MemberAssignmentFilter.child => hasChild,
      MemberAssignmentFilter.withoutAssignment => !hasTeam && !hasChild,
    };

    return matchesQuery &&
        matchesAgeGroup &&
        matchesTeam &&
        matchesType &&
        matchesStatus &&
        matchesReviewStatus &&
        matchesAssignment;
  }).toList();

  int compareNullableDates(DateTime? left, DateTime? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  filtered.sort((left, right) => switch (sort) {
        MemberSortOrder.nameAscending =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        MemberSortOrder.nameDescending =>
          right.name.toLowerCase().compareTo(left.name.toLowerCase()),
        MemberSortOrder.newest =>
          compareNullableDates(right.createdAt, left.createdAt),
        MemberSortOrder.oldest =>
          compareNullableDates(left.createdAt, right.createdAt),
        MemberSortOrder.role => left.roleLabel.compareTo(right.roleLabel),
        MemberSortOrder.status =>
          left.status.index.compareTo(right.status.index),
      });
  return filtered;
}
