import 'package:fc_teugn_app/core/models/competition_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses import preview counts and conflict details', () {
    final preview = CompetitionImportPreview.fromJson({
      'id': 'import-1',
      'totalRows': 3,
      'createCount': 1,
      'updateCount': 1,
      'skipCount': 0,
      'conflictCount': 1,
      'invalidCount': 0,
      'rows': [
        {
          'id': 'row-2',
          'rowNumber': 2,
          'externalId': 'bfv-123',
          'action': 'CREATE',
          'normalized': {
            'opponent': 'SV Beispiel',
            'startAt': '2026-08-15T08:30:00.000Z',
            'isHome': true,
            'competition': 'Meisterschaften',
            'location': 'Sportanlage Teugn, Platz 2',
            'opponentId': 'opponent-1',
            'opponentClubName': 'SV Beispiel',
            'opponentTeamDesignation': 'E1',
          },
          'messages': [],
        },
        {
          'id': 'row-3',
          'rowNumber': 3,
          'externalId': 'bfv-124',
          'action': 'CONFLICT',
          'normalized': {
            'opponent': 'TSV Muster',
            'startAt': '2026-08-22T09:00:00.000Z',
          },
          'messages': ['Lokale Änderungen erkannt.'],
        },
      ],
    });

    expect(preview.totalRows, 3);
    expect(preview.createCount, 1);
    expect(preview.conflictCount, 1);
    expect(preview.rows.first.action, CompetitionImportAction.create);
    expect(preview.rows.first.id, 'row-2');
    expect(preview.rows.first.canBeSelected, isTrue);
    expect(preview.rows.first.isHome, isTrue);
    expect(preview.rows.first.competition, 'Meisterschaften');
    expect(preview.rows.first.location, 'Sportanlage Teugn, Platz 2');
    expect(preview.rows.first.opponentId, 'opponent-1');
    expect(preview.rows.first.opponentTeamDesignation, 'E1');
    expect(preview.rows.last.action, CompetitionImportAction.conflict);
    expect(preview.rows.last.canBeSelected, isTrue);
    expect(preview.rows.last.messages, isNotEmpty);
  });
}
