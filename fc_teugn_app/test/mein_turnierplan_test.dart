import 'package:fc_teugn_app/core/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeinTurnierplan links', () {
    test('accepts the public showit link format', () {
      expect(
        isMeinTurnierplanUrl(
          'https://www.meinturnierplan.de/showit.php?id=2acei7shc3',
        ),
        isTrue,
      );
    });

    test('rejects foreign, insecure and malformed links', () {
      expect(
        isMeinTurnierplanUrl(
          'http://www.meinturnierplan.de/showit.php?id=2acei7shc3',
        ),
        isFalse,
      );
      expect(
        isMeinTurnierplanUrl(
          'https://example.org/showit.php?id=2acei7shc3',
        ),
        isFalse,
      );
      expect(
        isMeinTurnierplanUrl(
          'https://www.meinturnierplan.de/showit.php?id=<script>',
        ),
        isFalse,
      );
    });

    test('serializes the live plan as a dedicated event attachment', () {
      final data = EventWriteData(
        category: EventCategory.tournament,
        title: 'Sommerturnier',
        startAt: DateTime.utc(2026, 9, 12, 13),
        location: 'Kelheim',
        teamIds: const ['team-e1'],
        meinTurnierplanUrl:
            'https://www.meinturnierplan.de/showit.php?id=2acei7shc3',
      );

      final attachments = data.toJson()['attachments'] as List<dynamic>;
      expect(attachments, hasLength(1));
      expect(attachments.single, {
        'name': meinTurnierplanAttachmentName,
        'url': 'https://www.meinturnierplan.de/showit.php?id=2acei7shc3',
        'mimeType': 'text/html',
      });
    });
  });
}
