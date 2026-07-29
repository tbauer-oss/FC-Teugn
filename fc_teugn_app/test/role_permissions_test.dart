import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/role_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system administration always receives every catalog permission', () {
    final superAdmin = permissionsForUserRole(UserRole.superAdmin);
    final clubAdmin = permissionsForUserRole(UserRole.clubAdmin);

    expect(superAdmin.length, clubAdmin.length);
    expect(
      superAdmin.any((permission) => permission.code == 'MANAGE_ORGANIZATION'),
      isTrue,
    );
    expect(
      superAdmin.any((permission) => permission.code == 'MANAGE_PLAYERS'),
      isTrue,
    );
  });

  test('parent preset contains view and attendance but no player editing', () {
    final codes = permissionsForUserRole(
      UserRole.parent,
    ).map((permission) => permission.code);

    expect(codes, contains('VIEW_TEAM'));
    expect(codes, contains('RESPOND_ATTENDANCE'));
    expect(codes, isNot(contains('MANAGE_PLAYERS')));
  });

  test('statistics team selection is limited to administrator roles', () {
    expect(canSelectStatisticsTeam(UserRole.superAdmin), isTrue);
    expect(canSelectStatisticsTeam(UserRole.clubAdmin), isTrue);
    expect(canSelectStatisticsTeam(UserRole.trainerAdmin), isTrue);
    expect(canSelectStatisticsTeam(UserRole.youthDirector), isTrue);
    expect(canSelectStatisticsTeam(UserRole.coach), isFalse);
    expect(canSelectStatisticsTeam(UserRole.trainer), isFalse);
    expect(canSelectStatisticsTeam(UserRole.parent), isFalse);
    expect(canSelectStatisticsTeam(UserRole.player), isFalse);
  });
}
