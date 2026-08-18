import 'package:fc_teugn_app/core/api_client.dart';
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

  @override
  Future<FamilyContactInbox> familyContacts() async => FamilyContactInbox(
        retentionDays: 30,
        teamOptions: const [
          FamilyContactTeam(id: 'team-e1', name: 'E1-Jugend'),
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
  Future<List<AnnouncementModel>> announcements({
    bool includeDrafts = false,
  }) async =>
      const [];

  @override
  Future<List<AppNotificationModel>> notifications() async => [
        AppNotificationModel(
          id: 'notification-1',
          category: NotificationCategory.system,
          title: 'Platzinformation',
          body: 'Die Jugendmannschaft hat Vorrang.',
          createdAt: DateTime(2026, 8, 5),
          isRead: false,
        ),
      ];

  @override
  Future<void> deleteNotification(String notificationId) async {
    notificationDeleted = notificationId == 'notification-1';
  }
}

Widget _page({
  required bool staffView,
  _CommunicationRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(
        repository ?? _CommunicationRepository(),
      ),
    ],
    child: MaterialApp(
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
    expect(tester.takeException(), isNull);
  });
}
