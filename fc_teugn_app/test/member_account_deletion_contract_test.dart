import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system administration exposes guarded permanent account deletion', () {
    final page = File(
      'lib/features/trainer/trainer_approvals_page.dart',
    ).readAsStringSync();
    final repository = File('lib/core/data_repository.dart').readAsStringSync();

    expect(repository, contains("delete('/admin/members/\$userId')"));
    expect(page, contains('Konto dauerhaft löschen?'));
    expect(page, contains('Zur Bestätigung LÖSCHEN eingeben'));
    expect(page, contains('Konto endgültig löschen'));
    expect(page, contains('user.id != currentUserId'));
    expect(page, contains('UserRole.superAdmin'));
  });

  test('trainer publication uses the clear trainer-team wording', () {
    final matchday =
        File('lib/features/matches/matchday_page.dart').readAsStringSync();
    final help = File('lib/features/help/help_page.dart').readAsStringSync();

    expect(matchday, contains('Mit Trainerteam teilen'));
    expect(matchday, isNot(contains('Intern veröffentlichen')));
    expect(help, contains('Spiel mit Trainerteam teilen'));
  });
}
