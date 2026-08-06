import 'dart:io';

import 'package:fc_teugn_app/features/matches/matchday_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final page =
      File('lib/features/matches/matchday_page.dart').readAsStringSync();
  final repository = File('lib/core/data_repository.dart').readAsStringSync();

  test('internal publication dialog supports explicit responsive selection',
      () {
    expect(page, contains('Alle auswählen'));
    expect(page, contains('Alle abwählen'));
    expect(page, contains('Bitte mindestens eine Person auswählen.'));
    expect(page, contains('Zusätzlich als Pushnachricht senden'));
    expect(page, contains('maxHeight: size.height * .88'));
    expect(page, contains("recipient.isSender ? ' (Du)'"));
  });

  test('selected internal recipients are sent to the validating API', () {
    expect(repository, contains("'recipientIds': recipientIds"));
    expect(repository, contains('internal-publish-preview'));
    expect(page, contains('recipientIds: selection.recipientIds'));
  });

  test('family release preview displays the server-side meeting and message',
      () {
    expect(page, contains("preview['meetingSummary']"));
    expect(page, contains("preview['messagePreview']"));
  });

  testWidgets('recipient selection stays usable on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InternalPublicationDialog(
            messagePreview:
                'Kader und Aufstellung wurden intern veröffentlicht.',
            recipients: [
              InternalPublicationRecipient(
                id: '1',
                name: 'Sehr langer Trainername für die schmale Ansicht',
                functions: ['Trainer'],
                teams: ['E1-Jugend'],
                isSender: true,
              ),
              InternalPublicationRecipient(
                id: '2',
                name: 'Co-Trainer Beispiel',
                functions: ['Co-Trainer'],
                teams: ['E1-Jugend'],
                isSender: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Intern veröffentlichen'), findsNWidgets(2));
    expect(find.text('2 von 2 Empfängern'), findsOneWidget);
    expect(find.text('Zusätzlich als Pushnachricht senden'), findsOneWidget);

    await tester.ensureVisible(find.text('Alle abwählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle abwählen'));
    await tester.pump();
    expect(
        find.text('Bitte mindestens eine Person auswählen.'), findsOneWidget);
    await tester.ensureVisible(
      find.text('Bitte mindestens eine Person auswählen.'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
