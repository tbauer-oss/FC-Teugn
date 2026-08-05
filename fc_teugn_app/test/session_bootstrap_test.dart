import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/pitch_occupancy.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap preloads only universal core resources', () async {
    final calls = <String, int>{};
    int called(String resource) => calls.update(
          resource,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
    final organization = OrganizationContext.fromJson({
      'club': {
        'id': 'club-1',
        'name': 'FC Teugn',
        'shortName': 'FCT',
      },
      'season': {
        'id': 'season-1',
        'name': '2026/27',
        'startDate': '2026-07-01T00:00:00.000Z',
        'endDate': '2027-06-30T00:00:00.000Z',
        'isActive': true,
      },
      'currentTeam': {
        'id': 'team-1',
        'name': 'E1',
        'ageGroup': {'id': 'age-e', 'name': 'E-Jugend', 'code': 'E'},
        'season': {'name': '2026/27'},
      },
      'ageGroups': <Object>[],
      'teams': <Object>[],
      'permissions': <Object>[],
      'metrics': <String, Object>{},
    });
    const occupancy = PitchOccupancyPlan(
      seasonId: 'season-1',
      clubName: 'FC Teugn',
      seasonName: '2026/27',
      teams: [],
    );
    final container = ProviderContainer(
      overrides: [
        organizationProvider.overrideWith((ref) async {
          called('organization');
          return organization;
        }),
        playersProvider.overrideWith((ref) async {
          called('players');
          return [];
        }),
        eventsProvider.overrideWith((ref) async {
          called('events');
          return [];
        }),
        trainingsProvider.overrideWith((ref) async {
          called('trainings');
          return [];
        }),
        outdoorPitchOccupancyProvider.overrideWith((ref) async {
          called('outdoor');
          return occupancy;
        }),
        indoorPitchOccupancyProvider.overrideWith((ref) async {
          called('indoor');
          return occupancy;
        }),
        pendingUsersProvider.overrideWith((ref) async {
          called('pending');
          return [];
        }),
        membersProvider.overrideWith((ref) async {
          called('members');
          return [];
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(
      sessionBootstrapProvider(
        (userId: 'admin-1', role: UserRole.superAdmin),
      ).future,
    );

    expect(calls, {
      'organization': 1,
      'players': 1,
      'events': 1,
    });
  });
}
