import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/models/event.dart';
import '../../core/providers.dart';

enum AttendanceReminderAudience { open, all }

typedef _AttendanceReminderSettings = ({
  AttendanceReminderAudience audience,
  bool pushEnabled,
  String? message,
});

Future<void> showEventAttendanceReminder(
  BuildContext context,
  WidgetRef ref,
  EventModel event,
) async {
  final openCount = event.missingAttendance.isNotEmpty
      ? event.missingAttendance.length
      : event.attendanceSummary.unknown;
  var audience = openCount > 0
      ? AttendanceReminderAudience.open
      : AttendanceReminderAudience.all;
  var pushEnabled = true;
  final messageController = TextEditingController();
  final isTraining = event.category == EventCategory.training;

  final settings = await showDialog<_AttendanceReminderSettings>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(isTraining ? 'Training erinnern' : 'Termin erinnern'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isTraining
                    ? 'Wähle, wer die manuelle Trainingserinnerung erhalten soll.'
                    : 'Wähle, wer die manuelle Erinnerung erhalten soll.',
              ),
              const SizedBox(height: 10),
              RadioGroup<AttendanceReminderAudience>(
                groupValue: audience,
                onChanged: (value) {
                  if (value == null ||
                      (value == AttendanceReminderAudience.open &&
                          openCount == 0)) {
                    return;
                  }
                  setDialogState(() => audience = value);
                },
                child: Column(
                  children: [
                    RadioListTile<AttendanceReminderAudience>(
                      contentPadding: EdgeInsets.zero,
                      value: AttendanceReminderAudience.open,
                      enabled: openCount > 0,
                      title: const Text('Nur offene Rückmeldungen'),
                      subtitle: Text(
                        openCount == 0
                            ? 'Aktuell fehlt keine Rückmeldung.'
                            : '$openCount Rückmeldung(en) fehlen noch.',
                      ),
                    ),
                    RadioListTile<AttendanceReminderAudience>(
                      contentPadding: EdgeInsets.zero,
                      value: AttendanceReminderAudience.all,
                      title: Text(
                        isTraining
                            ? 'Alle zum Training erinnern'
                            : 'Alle zum Termin erinnern',
                      ),
                      subtitle: const Text(
                        'Alle relevanten Spieler und Sorgeberechtigten erhalten die Nachricht.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                maxLength: 240,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Individuelle Nachricht (optional)',
                  hintText:
                      'Ohne Eingabe wird ein passender Standardtext gesendet.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Zusätzlich als Push-Nachricht senden'),
                subtitle: const Text(
                  'Die Erinnerung erscheint immer auch in der App.',
                ),
                value: pushEnabled,
                onChanged: (value) => setDialogState(() => pushEnabled = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () {
              final message = messageController.text.trim();
              Navigator.pop(
                dialogContext,
                (
                  audience: audience,
                  pushEnabled: pushEnabled,
                  message: message.isEmpty ? null : message,
                ),
              );
            },
            icon: Icon(
              pushEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
            ),
            label: const Text('Jetzt erinnern'),
          ),
        ],
      ),
    ),
  );
  messageController.dispose();
  if (settings == null || !context.mounted) return;

  try {
    final result = await ref.read(repositoryProvider).sendAttendanceReminders(
          event.id,
          message: settings.message,
          pushEnabled: settings.pushEnabled,
          includeAll: settings.audience == AttendanceReminderAudience.all,
        );
    if (!context.mounted) return;
    final audienceText = settings.audience == AttendanceReminderAudience.all
        ? 'Alle relevanten Personen'
        : '${result.missingPlayers} offene Rückmeldung(en)';
    final String feedback;
    if (result.confirmationPending) {
      feedback =
          'Der Auftrag wurde genau einmal übertragen. Die Serverbestätigung '
          'wird noch geprüft; es erfolgt kein automatischer Doppelversand.';
    } else if (result.recipients == 0) {
      feedback = 'Für diese Auswahl wurden keine Empfänger gefunden.';
    } else if (!settings.pushEnabled) {
      feedback = '$audienceText: ${result.notificationRecipients} von '
          '${result.recipients} Konten wurden in der App informiert.';
    } else if (!result.deliveryStatusConfirmed) {
      feedback = 'Erinnerungsauftrag sicher angenommen: $audienceText, '
          '${result.recipients} Konten. Die Push-Übergabe läuft im Hintergrund.';
    } else {
      final parts = <String>[
        '$audienceText: ${result.notificationRecipients} von '
            '${result.recipients} Konten wurden informiert',
      ];
      if (result.pushRecipients > 0) {
        parts.add(
          'Push-Dienst: ${result.sentPushRecipients} von '
          '${result.pushRecipients} erreichbaren Konten angenommen',
        );
      }
      if (result.pendingPushRecipients > 0) {
        parts.add('${result.pendingPushRecipients} noch in Bearbeitung');
      }
      if (result.unavailablePushRecipients > 0) {
        parts.add(
          '${result.unavailablePushRecipients} derzeit nicht erreichbar',
        );
      }
      if (result.recipientsWithoutActivePush > 0) {
        parts.add(
          '${result.recipientsWithoutActivePush} ohne aktiven Push-Empfang',
        );
      }
      if (result.pushDevices == 0) {
        parts.add('kein aktives Push-Gerät registriert');
      }
      feedback = '${parts.join(' · ')}.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(feedback),
      ),
    );
  } on DioException catch (error) {
    if (!context.mounted) return;
    final deliveryMayHaveStarted = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        true,
      _ => false,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deliveryMayHaveStarted
              ? 'Die Verbindung ist gerade nicht stabil. Es wurde kein '
                  'zweiter Auftrag ausgelöst.'
              : 'Die Erinnerungen konnten nicht versendet werden.',
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Die Erinnerungen konnten nicht versendet werden.'),
      ),
    );
  }
}
