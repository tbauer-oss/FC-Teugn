import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/features/trainer/member_overview_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const e1 = UserTeamMembership(
    teamId: 'e1',
    teamName: 'E1',
    ageGroupCode: 'E',
    role: UserRole.parent,
    status: AccountStatus.pending,
  );
  const e2 = UserTeamMembership(
    teamId: 'e2',
    teamName: 'E2',
    ageGroupCode: 'E',
    role: UserRole.coach,
    status: AccountStatus.approved,
  );
  const f1Request = UserTeamMembership(
    teamId: 'f1',
    teamName: 'F1',
    ageGroupCode: 'F',
    role: UserRole.coach,
    status: AccountStatus.pending,
  );
  final users = <AppUser>[
    AppUser(
      id: 'parent',
      email: 'maria@example.test',
      name: 'Maria Muster',
      role: UserRole.parent,
      status: AccountStatus.pending,
      teamId: 'e1',
      memberships: [e1],
      createdAt: DateTime(2026, 8, 10),
      parentPlayers: const [
        UserParentPlayerLink(
          playerId: 'child',
          playerName: 'Max Muster',
          teamId: 'e1',
          teamName: 'E1',
          ageGroupCode: 'E',
          relationship: 'MOTHER',
          isLegalGuardian: true,
          canPickup: true,
          receivesCommunication: true,
        ),
      ],
      registrationRequest: const RegistrationRequestInfo(
        id: 'request',
        requestedRole: UserRole.parent,
        reviewStatus: RegistrationReviewStatus.needsInfo,
        requestedTeams: [e1],
        history: [],
        pushOptIn: true,
        childName: 'Max Muster',
      ),
    ),
    AppUser(
      id: 'coach',
      email: 'trainer@example.test',
      name: 'Anton Trainer',
      role: UserRole.coach,
      status: AccountStatus.approved,
      teamId: 'e2',
      memberships: [e2],
      createdAt: DateTime(2026, 8, 1),
      registrationRequest: const RegistrationRequestInfo(
        id: 'old-request',
        requestedRole: UserRole.coach,
        reviewStatus: RegistrationReviewStatus.completed,
        requestedTeams: [f1Request, e2],
        history: [],
        pushOptIn: true,
      ),
    ),
    AppUser(
      id: 'admin',
      email: 'admin@example.test',
      name: 'Zora Admin',
      role: UserRole.superAdmin,
      status: AccountStatus.blocked,
      teamId: '',
      createdAt: DateTime(2026, 7, 1),
    ),
  ];

  test('search includes child and team information', () {
    expect(
      filterMembersForOverview(users, query: 'max muster')
          .map((user) => user.id),
      ['parent'],
    );
    expect(
      filterMembersForOverview(users, query: 'E2').map((user) => user.id),
      ['coach'],
    );
  });

  test('combines youth, member type, status and review filters', () {
    final result = filterMembersForOverview(
      users,
      ageGroupCode: 'E',
      type: MemberTypeFilter.parents,
      status: AccountStatus.pending,
      reviewStatus: RegistrationReviewStatus.needsInfo,
    );
    expect(result.map((user) => user.id), ['parent']);
  });

  test('approved assignments override the original registration request', () {
    expect(
      filterMembersForOverview(users, ageGroupCode: 'F').map((user) => user.id),
      isEmpty,
    );
    expect(
      filterMembersForOverview(users, ageGroupCode: 'E').map((user) => user.id),
      ['coach', 'parent'],
    );
    expect(
      filterMembersForOverview(users, query: 'F1').map((user) => user.id),
      isEmpty,
    );
  });

  test('finds accounts without team or child assignment', () {
    final result = filterMembersForOverview(
      users,
      assignment: MemberAssignmentFilter.withoutAssignment,
    );
    expect(result.map((user) => user.id), ['admin']);
  });

  test('sorts newest accounts first', () {
    final result = filterMembersForOverview(
      users,
      sort: MemberSortOrder.newest,
    );
    expect(result.map((user) => user.id), ['parent', 'coach', 'admin']);
  });
}
