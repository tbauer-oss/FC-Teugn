import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File(
    'lib/features/trainer/trainer_matches_page.dart',
  ).readAsStringSync();
  final repository = File('lib/core/data_repository.dart').readAsStringSync();
  final outbox = File('lib/core/offline_outbox.dart').readAsStringSync();

  test('match editor provides opponent pool, quick add and friendly badge', () {
    expect(page, contains("title: 'Gegnerischen Verein hinzufügen'"));
    expect(page, contains('DropdownButtonFormField<String>'));
    expect(page, contains('selectedOpponentClubId'));
    expect(page, contains('selectedTeamDesignation'));
    expect(page, contains("? 'Freundschaftsspiel'"));
  });

  test('match reschedule exposes fixed venue defaults and confirmation choices',
      () {
    expect(page, contains('Stadion am Kreutweg, Teugn'));
    expect(page, contains('Vereinsheim Teugn'));
    expect(page, contains("value: 'RESET_RESPONSES'"));
    expect(page, contains("value: 'RESET_SQUAD'"));
    expect(page, contains("value: 'PUSH'"));
    expect(page, contains('Verlegung verbindlich speichern?'));
  });

  test('destructive lifecycle calls are online-only and never queued', () {
    expect(repository, contains("'requireOnline': true"));
    expect(repository, contains("'/matches/\$eventId/reschedule'"));
    expect(repository, contains("'permanent': 'true'"));
    expect(outbox, contains("request.extra['requireOnline'] == true"));
  });
}
