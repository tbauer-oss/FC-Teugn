import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_teugn_app/core/models/competition_import.dart';
import 'package:fc_teugn_app/features/imports/competition_import_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects ICS by file name and calendar content', () {
    expect(
      competitionImportFormatForFile('spielplan.ics', 'anything'),
      CompetitionImportFormat.ics,
    );
    expect(
      competitionImportFormatForFile(
        'spielplan.txt',
        '  BEGIN:VCALENDAR\nBEGIN:VEVENT',
      ),
      CompetitionImportFormat.ics,
    );
    expect(
      competitionImportFormatForFile('spielplan.csv', 'Datum;Gegner'),
      CompetitionImportFormat.csv,
    );
  });

  test('decodes UTF-8 files and removes BOM', () {
    final bytes = Uint8List.fromList(
      utf8.encode('\uFEFFBEGIN:VCALENDAR\nSUMMARY:FC Teugn – Gegner'),
    );
    expect(
      decodeCompetitionImportBytes(bytes),
      'BEGIN:VCALENDAR\nSUMMARY:FC Teugn – Gegner',
    );
  });

  test('recognizes a BfV iCalendar export', () {
    expect(
      looksLikeBfvIcs(
        'BEGIN:VCALENDAR\nPRODID:-//Events Calendar//iCal4j 1.0//EN\n'
        'SUMMARY:Meisterschaften',
      ),
      isTrue,
    );
    expect(looksLikeBfvIcs('BEGIN:VCALENDAR\nSUMMARY:Privat'), isFalse);
  });
}
