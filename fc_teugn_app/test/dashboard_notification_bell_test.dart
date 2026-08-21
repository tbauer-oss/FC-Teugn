import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/shared/dashboard_notifications.dart';
import 'package:fc_teugn_app/features/shared/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotificationRepository extends DataRepository {
  _NotificationRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  bool markedAllRead = false;

  @override
  Future<void> markAllNotificationsRead() async {
    markedAllRead = true;
  }
}

void main() {
  final notifications = [
    AppNotificationModel(
      id: 'notification-1',
      category: NotificationCategory.eventReminder,
      title: 'Rückmeldung fehlt',
      body: 'Bitte gib eine Rückmeldung zum nächsten Training ab.',
      createdAt: DateTime(2026, 8, 21, 8, 30),
      isRead: false,
      actionUrl: '/parent/family',
    ),
    AppNotificationModel(
      id: 'notification-2',
      category: NotificationCategory.nomination,
      title: 'Neue Nominierung',
      body: 'Der Kader für das nächste Spiel wurde freigegeben.',
      createdAt: DateTime(2026, 8, 21, 7, 15),
      isRead: false,
      actionUrl: '/parent/matches',
    ),
    AppNotificationModel(
      id: 'notification-3',
      category: NotificationCategory.announcement,
      title: 'Vereinsinformation',
      body: 'Es gibt eine neue Nachricht vom Trainerteam.',
      createdAt: DateTime(2026, 8, 20, 18),
      isRead: false,
      actionUrl: '/parent/messages',
    ),
    AppNotificationModel(
      id: 'notification-4',
      category: NotificationCategory.system,
      title: 'Bereits gelesen',
      body: 'Dieser Hinweis gehört nur in das Mitteilungscenter.',
      createdAt: DateTime(2026, 8, 20, 12),
      isRead: true,
      actionUrl: '/parent/messages',
    ),
  ];

  for (final size in const [
    Size(320, 700),
    Size(480, 820),
    Size(800, 800),
  ]) {
    testWidgets(
      'bell and notification overview fit ${size.width.toInt()} px',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repository = _NotificationRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: PageScaffold(
                  title: 'Hallo Fußballfamilie!',
                  subtitle: 'Nur das, was jetzt wichtig ist.',
                  denseMobileHeader: true,
                  headerAction: DashboardNotificationBell(
                    notifications: notifications,
                    isTrainer: false,
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );

        expect(find.byKey(const ValueKey('dashboard-notification-bell')),
            findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Rückmeldung fehlt'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('dashboard-notification-bell')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Benachrichtigungen'), findsOneWidget);
        expect(find.text('3 ungelesen'), findsOneWidget);
        expect(find.text('Alle als gelesen markieren'), findsOneWidget);
        expect(find.text('Rückmeldung fehlt'), findsOneWidget);
        expect(find.text('Bereits gelesen'), findsNothing);

        await tester.tap(find.text('Alle als gelesen markieren'));
        await tester.pumpAndSettle();

        expect(repository.markedAllRead, isTrue);
        expect(find.text('Rückmeldung fehlt'), findsNothing);
        expect(find.text('Neue Nominierung'), findsNothing);
        expect(find.text('Vereinsinformation'), findsNothing);
        expect(
            find.text('Keine ungelesenen Benachrichtigungen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
