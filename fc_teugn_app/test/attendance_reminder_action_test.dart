import 'dart:async';

import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/shared/attendance_reminder_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceReminderSendResult _result({
  required bool deliveryComplete,
  required bool deliveryStatusConfirmed,
  int sentPushRecipients = 0,
  int pendingPushRecipients = 2,
}) =>
    (
      accepted: true,
      confirmationPending: false,
      deliveryComplete: deliveryComplete,
      deliveryStatusConfirmed: deliveryStatusConfirmed,
      trackingKey: 'reminder-key',
      recipients: 2,
      targetedPlayers: 2,
      missingPlayers: 2,
      notificationRecipients: 2,
      pushRecipients: 2,
      sentPushRecipients: sentPushRecipients,
      pendingPushRecipients: pendingPushRecipients,
      unavailablePushRecipients: 0,
      recipientsWithoutActivePush: 0,
      pushDevices: 2,
      sentPushDevices: sentPushRecipients,
      pendingPushDevices: pendingPushRecipients,
      unavailablePushDevices: 0,
    );

final _training = EventModel(
  id: 'training-1',
  teamId: 'team-e1',
  type: EventType.training,
  category: EventCategory.training,
  status: EventStatus.scheduled,
  visibility: EventVisibility.team,
  title: 'Training',
  startAt: DateTime(2026, 8, 18, 17, 15),
  location: 'Platz 1 unten',
  attendanceFinalized: false,
  targetTeams: const [],
  attachments: const [],
  attendance: const [],
  attendanceSummary: const AttendanceSummary(unknown: 2),
  missingAttendance: const [
    MissingAttendance(id: 'player-1', name: 'Spieler Eins'),
    MissingAttendance(id: 'player-2', name: 'Spieler Zwei'),
  ],
  carpoolOffers: const [],
  capabilities: const EventCapabilities(canManage: true),
  reminderMinutes: const [],
);

class _ReminderRepository extends DataRepository {
  _ReminderRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  final delivery = Completer<AttendanceReminderSendResult?>();

  @override
  Future<AttendanceReminderSendResult> sendAttendanceReminders(
    String eventId, {
    String? message,
    bool pushEnabled = true,
    bool includeAll = false,
  }) async =>
      _result(
        deliveryComplete: false,
        deliveryStatusConfirmed: false,
      );

  @override
  Future<AttendanceReminderSendResult?> waitForAttendanceReminderDelivery(
    String eventId,
    String trackingKey,
  ) =>
      delivery.future;
}

void main() {
  testWidgets(
      'reminder confirms immediately and later shows a persistent report',
      (tester) async {
    final repository = _ReminderRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => showEventAttendanceReminder(
                  context,
                  ref,
                  _training,
                ),
                child: const Text('Erinnern'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jetzt erinnern'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Erinnerung an 2 Konten übermittelt. Die Push-Auslieferung wird im '
        'Hintergrund geprüft.',
      ),
      findsOneWidget,
    );
    expect(find.text('Versandbericht'), findsNothing);

    repository.delivery.complete(
      _result(
        deliveryComplete: true,
        deliveryStatusConfirmed: true,
        sentPushRecipients: 2,
        pendingPushRecipients: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Versandbericht'), findsOneWidget);
    expect(
      find.textContaining('2 von 2 Push-Konten vom Push-Dienst angenommen'),
      findsOneWidget,
    );
    expect(find.text('Schließen'), findsOneWidget);
  });
}
