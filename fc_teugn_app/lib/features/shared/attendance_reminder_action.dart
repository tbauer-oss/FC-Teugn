import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_repository.dart';
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
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repository = ref.read(repositoryProvider);
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
  if (settings == null) return;

  try {
    final result = await repository.sendAttendanceReminders(
      event.id,
      message: settings.message,
      pushEnabled: settings.pushEnabled,
      includeAll: settings.audience == AttendanceReminderAudience.all,
    );
    final String feedback;
    if (result.confirmationPending) {
      feedback =
          'Der Auftrag wurde einmal übermittelt. Die Serverbestätigung wird '
          'im Hintergrund geprüft; es erfolgt kein Doppelversand.';
    } else if (result.recipients == 0) {
      feedback = 'Für diese Auswahl wurden keine Empfänger gefunden.';
    } else if (!settings.pushEnabled) {
      feedback = 'Erinnerung an ${result.recipients} Konten übermittelt und '
          'in der App bereitgestellt.';
    } else {
      feedback = 'Erinnerung an ${result.recipients} Konten übermittelt. '
          'Die Push-Auslieferung wird im Hintergrund geprüft.';
    }
    _showImmediateReminderFeedback(messenger, feedback);

    if (settings.pushEnabled &&
        (result.recipients > 0 || result.confirmationPending)) {
      unawaited(
        _showAttendanceReminderDeliveryReport(
          messenger: messenger,
          repository: repository,
          event: event,
          initialResult: result,
        ),
      );
    }
  } on DioException catch (error) {
    final deliveryMayHaveStarted = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        true,
      _ => false,
    };
    _showImmediateReminderFeedback(
      messenger,
      deliveryMayHaveStarted
          ? 'Die Verbindung ist gerade nicht stabil. Es wurde kein zweiter '
              'Auftrag ausgelöst.'
          : 'Die Erinnerungen konnten nicht versendet werden.',
    );
  } catch (_) {
    _showImmediateReminderFeedback(
      messenger,
      'Die Erinnerungen konnten nicht versendet werden.',
    );
  }
}

void _showImmediateReminderFeedback(
  ScaffoldMessengerState? messenger,
  String message,
) {
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(message),
      ),
    );
}

Future<void> _showAttendanceReminderDeliveryReport({
  required ScaffoldMessengerState? messenger,
  required DataRepository repository,
  required EventModel event,
  required AttendanceReminderSendResult initialResult,
}) async {
  AttendanceReminderSendResult? checkedResult;
  try {
    checkedResult = await repository.waitForAttendanceReminderDelivery(
      event.id,
      initialResult.trackingKey,
    );
  } catch (_) {
    // Die Erinnerung ist bereits mit einem eindeutigen Schlüssel angenommen.
    // Ein Fehler der rein lesenden Hintergrundprüfung darf weder die App noch
    // einen zweiten Versand auslösen.
  }
  if (messenger == null || !messenger.mounted) return;

  final result = checkedResult ?? initialResult;
  final report = _attendanceReminderDeliveryReport(result);
  final scheme = Theme.of(messenger.context).colorScheme;
  messenger
    ..hideCurrentMaterialBanner()
    ..showMaterialBanner(
      MaterialBanner(
        leading: Icon(
          result.deliveryComplete
              ? Icons.verified_rounded
              : Icons.notifications_active_rounded,
          color: result.deliveryComplete
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Versandbericht',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(report),
          ],
        ),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
}

String _attendanceReminderDeliveryReport(
  AttendanceReminderSendResult result,
) {
  if (!result.accepted) {
    return 'Der Auftrag wurde nur einmal übertragen. Die Serverbestätigung '
        'steht noch aus; ein Doppelversand ist ausgeschlossen.';
  }

  final parts = <String>[
    '${result.notificationRecipients} von ${result.recipients} Konten in der '
        'App informiert',
  ];
  if (result.pushRecipients > 0) {
    parts.add(
      '${result.sentPushRecipients} von ${result.pushRecipients} Push-Konten '
      'vom Push-Dienst angenommen',
    );
  } else if (result.pushDevices == 0) {
    parts.add('kein aktives Push-Gerät registriert');
  }
  if (result.pendingPushRecipients > 0) {
    parts
        .add('${result.pendingPushRecipients} Push-Konten noch in Bearbeitung');
  }
  if (result.unavailablePushRecipients > 0) {
    parts.add(
      '${result.unavailablePushRecipients} Push-Konten derzeit nicht '
      'erreichbar',
    );
  }
  if (result.recipientsWithoutActivePush > 0) {
    parts.add(
      '${result.recipientsWithoutActivePush} Konten ohne aktiven Push-Empfang',
    );
  }
  if (!result.deliveryComplete) {
    parts.add('vollständiger Abschlussstatus steht noch aus');
  }
  return '${parts.join(' · ')}.';
}
