import 'package:fc_teugn_app/core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser user({
  required UserRole role,
  List<UserParentPlayerLink> parentPlayers = const [],
}) =>
    AppUser(
      id: 'user-1',
      email: 'user@fc-teugn.de',
      name: 'Test User',
      role: role,
      status: AccountStatus.approved,
      teamId: 'team-1',
      parentPlayers: parentPlayers,
    );

void main() {
  test('staff family inbox does not depend on cached parent links', () {
    expect(
      user(role: UserRole.superAdmin).canUsePersonalResponses,
      isTrue,
    );
    expect(
      user(role: UserRole.coach).canUsePersonalResponses,
      isTrue,
    );
  });

  test('a real guardian link enables the inbox for every account type', () {
    const link = UserParentPlayerLink(
      playerId: 'player-1',
      playerName: 'Kind Teugn',
      teamId: 'team-1',
      teamName: 'E1',
      ageGroupCode: 'E',
      relationship: 'FATHER',
      isLegalGuardian: true,
      canPickup: true,
      receivesCommunication: true,
    );

    expect(
      user(role: UserRole.readOnly, parentPlayers: const [link])
          .canUsePersonalResponses,
      isTrue,
    );
    expect(
      user(role: UserRole.readOnly).canUsePersonalResponses,
      isFalse,
    );
  });
}
