import 'dart:typed_data';

import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/communications/communications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CommunicationRepository extends DataRepository {
  _CommunicationRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  bool notificationDeleted = false;
  bool allNotificationsRead = false;
  bool readNotificationsDeleted = false;
  String? sentContactParentId;
  String? sentContactTeamId;
  String? sentContactMessage;

  @override
  Future<FamilyContactInbox> familyContacts() async => FamilyContactInbox(
        retentionDays: 30,
        teamOptions: const [
          FamilyContactTeam(id: 'team-e1', name: 'E1-Jugend'),
        ],
        contactOptions: const [
          FamilyContactRecipient(
            id: 'parent-1',
            name: 'Familie Muster',
            teamId: 'team-e1',
            teamName: 'E1-Jugend',
            playerNames: ['Max'],
          ),
        ],
        messages: [
          FamilyContactMessage(
            id: 'message-1',
            conversationId: 'thread.parent.team-e1',
            teamId: 'team-e1',
            teamName: 'E1-Jugend',
            senderId: 'parent-1',
            senderName: 'Familie Muster',
            senderIsStaff: false,
            sentByMe: true,
            message: 'Max kommt heute etwas später.',
            createdAt: DateTime(2026, 8, 18, 8),
            expiresAt: DateTime(2026, 9, 17, 8),
            isRead: true,
          ),
        ],
      );

  @override
  Future<void> sendFamilyContact({
    required String message,
    String? teamId,
    String? conversationId,
    String? parentId,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentMimeType,
  }) async {
    sentContactMessage = message;
    sentContactTeamId = teamId;
    sentContactParentId = parentId;
  }

  @override
  Future<List<AnnouncementModel>> announcements({
    bool includeDrafts = false,
  }) async =>
      const [];

  @override
  Future<List<AppNotificationModel>> notifications() async => [
        if (!readNotificationsDeleted)
          AppNotificationModel(
            id: 'notification-1',
            category: NotificationCategory.system,
            title: 'Platzinformation',
            body: 'Die Jugendmannschaft hat Vorrang.',
            createdAt: DateTime(2026, 8, 5),
            isRead: allNotificationsRead,
          ),
      ];

  @override
  Future<void> markAllNotificationsRead() async {
    allNotificationsRead = true;
  }

  @override
  Future<int> deleteReadNotifications() async {
    if (!allNotificationsRead) return 0;
    readNotificationsDeleted = true;
    return 1;
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    notificationDeleted = notificationId == 'notification-1';
  }
}

Widget _page({
  required bool staffView,
  _CommunicationRepository? repository,
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(
        repository ?? _CommunicationRepository(),
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(brightness: brightness),
      home: Scaffold(
        body: CommunicationsPage(staffView: staffView),
      ),
    ),
  );
}

void main() {
  testWidgets('Eltern und Spieler sehen keine Platzanfragen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(staffView: false));
    await tester.pumpAndSettle();

    expect(find.text('Mitteilungen'), findsOneWidget);
    expect(find.text('Platzanfragen'), findsNothing);
    expect(find.text('Benachrichtigungen'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });

  testWidgets('Vereinsmitarbeiter sehen Platzanfragen weiterhin',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(staffView: true));
    await tester.pumpAndSettle();

    expect(find.text('Platzanfragen'), findsOneWidget);
  });

  testWidgets('Trainer können eigene Benachrichtigungen bestätigt löschen',
      (tester) async {
    final repository = _CommunicationRepository();
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _page(staffView: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benachrichtigungen'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Benachrichtigung löschen'), findsOneWidget);
    await tester.tap(find.byTooltip('Benachrichtigung löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Benachrichtigung löschen?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.pumpAndSettle();

    expect(repository.notificationDeleted, isTrue);
  });

  testWidgets(
      'gelesene Benachrichtigungen können gesammelt gelöscht werden, ungelesene nicht',
      (tester) async {
    final repository = _CommunicationRepository();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _page(staffView: false, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Benachrichtigungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benachrichtigungen'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('delete-read-notifications')), findsNothing);
    await tester.tap(find.text('Alle als gelesen markieren'));
    await tester.pumpAndSettle();

    expect(repository.allNotificationsRead, isTrue);
    expect(find.byKey(const ValueKey('delete-read-notifications')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-read-notifications')));
    await tester.pumpAndSettle();
    expect(find.text('Gelesene Benachrichtigungen löschen?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Gelesene löschen'));
    await tester.pumpAndSettle();

    expect(repository.readNotificationsDeleted, isTrue);
    expect(find.text('Alles erledigt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parents reach a compact 30 day trainer contact on mobile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(staffView: false));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Direktkontakt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direktkontakt'));
    await tester.pumpAndSettle();

    expect(find.text('Trainerteam schreiben'), findsOneWidget);
    expect(find.textContaining('automatische Löschung nach 30 Tagen'),
        findsOneWidget);
    expect(find.text('Max kommt heute etwas später.'), findsOneWidget);
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('family-contact-thread-thread.parent.team-e1'),
            ),
          )
          .height,
      lessThan(90),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct contact opens a compact messenger with quick replies',
      (tester) async {
    final repository = _CommunicationRepository();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _page(staffView: false, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Direktkontakt'));
    await tester.tap(find.text('Direktkontakt'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('family-contact-thread-thread.parent.team-e1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Vollständige Löschung inkl. Sicherungen nach 30 Tagen'),
      findsOneWidget,
    );
    expect(find.text('Löschung: 17.09.2026, 08:00 Uhr'), findsOneWidget);
    expect(find.text('Alles klar 👍'), findsOneWidget);
    expect(find.byTooltip('Nachricht senden'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('family-contact-message-message-1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Danke für die Info!'));
    await tester.pump();
    await tester.tap(find.byTooltip('Nachricht senden'));
    await tester.pumpAndSettle();

    expect(repository.sentContactTeamId, 'team-e1');
    expect(repository.sentContactMessage, 'Danke für die Info!');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'direct contact message and deletion date stay readable in dark mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _page(staffView: false, brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Direktkontakt'));
    await tester.tap(find.text('Direktkontakt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('family-contact-thread-thread.parent.team-e1'),
      ),
    );
    await tester.pumpAndSettle();

    final bubble = find.byKey(
      const ValueKey('family-contact-message-message-1'),
    );
    final body = tester.widget<Text>(find.descendant(
      of: bubble,
      matching: find.text('Max kommt heute etwas später.'),
    ));
    final deletion = tester.widget<Text>(find.descendant(
      of: bubble,
      matching: find.text('Löschung: 17.09.2026, 08:00 Uhr'),
    ));
    expect(body.style?.color, AppSurfaceColors.dark.text);
    expect(deletion.style?.color, AppSurfaceColors.dark.textMuted);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trainers can start a compact direct contact with team parents',
      (tester) async {
    final repository = _CommunicationRepository();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _page(staffView: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Direktkontakt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direktkontakt'));
    await tester.pumpAndSettle();

    expect(find.text('Eltern kontaktieren'), findsOneWidget);
    await tester.tap(find.text('Eltern kontaktieren'));
    await tester.pumpAndSettle();
    expect(find.text('Familie Muster · Max'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nachricht'),
      'Bitte morgen zehn Minuten früher da sein.',
    );
    await tester.tap(find.text('Sicher senden'));
    await tester.pumpAndSettle();

    expect(repository.sentContactParentId, 'parent-1');
    expect(repository.sentContactTeamId, 'team-e1');
    expect(repository.sentContactMessage,
        'Bitte morgen zehn Minuten früher da sein.');
    expect(tester.takeException(), isNull);
  });
}
