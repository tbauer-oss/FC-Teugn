import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/features/calendar/tournament_plan_browser_page.dart';
import 'package:flutter/material.dart';
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

    testWidgets('opens above the app shell on the root navigator',
        (tester) async {
      final rootNavigatorKey = GlobalKey<NavigatorState>();
      final shellNavigatorKey = GlobalKey<NavigatorState>();
      late BuildContext shellContext;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Navigator(
            key: shellNavigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) {
                shellContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final browserClosed = openTournamentPlanBrowser(
        shellContext,
        url: 'https://www.meinturnierplan.de/showit.php?id=2acei7shc3',
        tournamentName: 'Sommerturnier',
      );

      expect(rootNavigatorKey.currentState!.canPop(), isTrue);
      expect(shellNavigatorKey.currentState!.canPop(), isFalse);

      rootNavigatorKey.currentState!.pop();
      await browserClosed;
      await tester.pumpAndSettle();
    });
  });
}
