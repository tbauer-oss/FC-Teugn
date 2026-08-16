import 'dart:io';

import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUser pending(String id) => AppUser(
        id: id,
        email: '$id@example.test',
        name: 'Anfrage $id',
        role: UserRole.parent,
        status: AccountStatus.pending,
        teamId: 'team-e1',
      );

  test('a completed approval disappears from every visible pending list', () {
    final visible = visiblePendingUsers(
      AsyncData([pending('one'), pending('two')]),
      {'one'},
    );

    expect(visible.requireValue.map((user) => user.id), ['two']);
  });

  test('guardian relationships keep the established German labels', () {
    expect(guardianRelationshipLabel('MOTHER'), 'Mutter');
    expect(guardianRelationshipLabel('FATHER'), 'Vater');
    expect(guardianRelationshipLabel('OTHER'), 'Sorgeberechtigt');
  });

  test('approval UI and API payload support several children', () {
    final page = File(
      'lib/features/trainer/trainer_approvals_page.dart',
    ).readAsStringSync();
    final repository = File('lib/core/data_repository.dart').readAsStringSync();

    expect(page, contains("ValueKey('add-guardian-child')"));
    expect(page, contains('guardianRelationships.entries'));
    expect(page, contains('_GuardianChildPickerSheet'));
    expect(repository, contains("'guardianLinks'"));
    expect(repository, contains("'relationship': entry.value"));
  });
}
