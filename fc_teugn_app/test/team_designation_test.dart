import 'package:fc_teugn_app/core/models/competition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy E7 labels are always presented as E teams', () {
    expect(canonicalYouthTeamDesignation('E7'), 'E1');
    expect(canonicalYouthTeamDesignation('E7 1'), 'E1');
    expect(canonicalYouthTeamDesignation('E7 2'), 'E2');
    expect(canonicalYouthTeamDesignation('E1'), 'E1');
  });

  test('opponent models never expose legacy E7 labels', () {
    final opponent = OpponentModel.fromJson({
      'id': 'opponent-1',
      'ageGroupId': 'age-e',
      'clubName': 'ATSV Kelheim',
      'teamDesignation': 'E7 1',
      'displayName': 'ATSV Kelheim E7 1',
    });
    final team = OpponentClubTeamModel.fromJson({
      'id': 'team-1',
      'ageGroupId': 'age-e',
      'teamDesignation': 'E7 2',
      'ageGroup': {'code': 'E'},
    });

    expect(opponent.teamDesignation, 'E1');
    expect(opponent.displayName, 'ATSV Kelheim E1');
    expect(team.teamDesignation, 'E2');
  });
}
