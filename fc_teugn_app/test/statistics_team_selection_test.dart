import 'package:fc_teugn_app/features/statistics/statistics_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all-team context queries the same registered team shown in the filter',
      () {
    final teamId = resolveStatisticsPageTeamId(
      registeredTeamId: 'e2',
      currentTeamId: 'e1',
      workingTeamIds: const ['e1', 'e2'],
      includeAllTeams: true,
    );

    expect(teamId, 'e2');
  });

  test('single-team context follows the selected working team', () {
    final teamId = resolveStatisticsPageTeamId(
      registeredTeamId: 'e2',
      currentTeamId: 'e1',
      workingTeamIds: const ['e1'],
      includeAllTeams: false,
    );

    expect(teamId, 'e1');
  });

  test('explicit statistics selection has priority', () {
    final teamId = resolveStatisticsPageTeamId(
      registeredTeamId: 'e2',
      currentTeamId: 'e1',
      workingTeamIds: const ['e1', 'e2'],
      includeAllTeams: true,
      selectedTeamId: 'f1',
    );

    expect(teamId, 'f1');
  });
}
