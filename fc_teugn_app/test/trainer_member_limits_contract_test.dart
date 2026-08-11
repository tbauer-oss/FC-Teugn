import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('limited trainer UI exposes approvals and parent links only', () {
    final page = File(
      'lib/features/trainer/trainer_approvals_page.dart',
    ).readAsStringSync();

    expect(page, contains("organization?.can('MANAGE_ORGANIZATION')"));
    expect(page, contains('action: fullMemberAdministration'));
    expect(page, contains('if (limitedManager)'));
    expect(
        page,
        contains(
            'Die beantragte Rolle, der Kontostatus und die Mannschaften können von Trainern nicht geändert werden.'));
    expect(page, contains('Sperren, Deaktivieren, Löschen'));
    expect(page, contains('Eltern-Kind-Zuordnung'));
  });
}
