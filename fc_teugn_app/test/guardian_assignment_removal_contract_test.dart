import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guardian removal is exposed to system admins without deleting data',
      () {
    final repository = File('lib/core/data_repository.dart').readAsStringSync();
    final members = File(
      'lib/features/trainer/trainer_approvals_page.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/players/player_profile_page.dart',
    ).readAsStringSync();

    expect(repository, contains('Future<void> removeParentPlayer'));
    expect(
      repository,
      contains('/admin/parent-player-links/\$parentId/\$playerId'),
    );
    expect(members, contains('actorIsSuperAdmin'));
    expect(members, contains('onRemoveParentPlayer: actorIsSuperAdmin'));
    expect(members, contains('Sorgeberechtigten-Zuordnung entfernen'));
    expect(profile, contains('UserRole.superAdmin'));
    expect(profile, contains('guardian.userId == member.id'));
    expect(profile, contains('Sorgeberechtigten-Zuordnung entfernen'));
    expect(
      members,
      contains(
          'Beide Konten und alle Spieler- bzw. Vereinsdaten bleiben erhalten.'),
    );
  });
}
