import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/push/native_push_service.dart';
import '../../core/push/push_client.dart';
import '../shared/page_scaffold.dart';

class CommunicationsPage extends ConsumerStatefulWidget {
  const CommunicationsPage({super.key, required this.staffView});

  final bool staffView;

  @override
  ConsumerState<CommunicationsPage> createState() => _CommunicationsPageState();
}

class _CommunicationsPageState extends ConsumerState<CommunicationsPage> {
  int _tab = 0;
  int _revision = 0;

  void _reload() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Mitteilungen',
      'Platzanfragen',
      'Benachrichtigungen',
      'Einstellungen',
    ];
    return PageScaffold(
      title: 'Team-Nachrichten',
      subtitle:
          'Mitteilungen, wichtige Hinweise und persönliche Benachrichtigungen an einem Ort.',
      action: widget.staffView && _tab == 0
          ? FilledButton.icon(
              onPressed: _compose,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Neue Mitteilung'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: [
                for (var index = 0; index < labels.length; index++)
                  ButtonSegment(value: index, label: Text(labels[index])),
              ],
              selected: {_tab},
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
          const SizedBox(height: 20),
          if (_tab == 0)
            _AnnouncementList(
              key: ValueKey('announcements-$_revision'),
              staffView: widget.staffView,
              onChanged: _reload,
            )
          else if (_tab == 1)
            _PitchConflictRequestList(
              key: ValueKey('pitch-conflicts-$_revision'),
              onChanged: _reload,
            )
          else if (_tab == 2)
            _NotificationList(
              key: ValueKey('notifications-$_revision'),
              onChanged: _reload,
            )
          else
            _NotificationSettings(key: ValueKey('settings-$_revision')),
        ],
      ),
    );
  }

  Future<void> _compose() async {
    final organization = await ref.read(organizationProvider.future);
    if (!mounted) return;
    final draft = await showDialog<_AnnouncementDraft>(
      context: context,
      builder: (context) => _ComposeAnnouncementDialog(
        organization: organization,
      ),
    );
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).saveAnnouncement(
            title: draft.title,
            body: draft.body,
            teamIds: draft.teamIds,
            audience: draft.audience,
            priority: draft.priority,
            status: draft.status,
            publishAt: draft.publishAt,
            requireReadReceipt: draft.requireReadReceipt,
            pushEnabled: draft.pushEnabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.status == AnnouncementStatus.draft
                ? 'Entwurf gespeichert.'
                : draft.status == AnnouncementStatus.scheduled
                    ? 'Mitteilung wurde eingeplant.'
                    : 'Mitteilung wurde veröffentlicht.',
          ),
        ),
      );
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mitteilung konnte nicht gespeichert werden.')),
      );
    }
  }
}

class _PitchConflictRequestList extends ConsumerWidget {
  const _PitchConflictRequestList({
    super.key,
    required this.onChanged,
  });

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<PitchConflictRequestModel>>(
      future: ref.read(repositoryProvider).pitchConflictRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _ErrorCard(onRetry: onChanged);
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_rounded,
            title: 'Keine offenen Platzabstimmungen',
            message:
                'Anfragen wegen Überschneidungen mit Trainings erscheinen hier.',
          );
        }
        return Column(
          children: [
            for (final item in items) ...[
              _PitchConflictRequestCard(
                request: item,
                onRespond: item.canRespond
                    ? (status) => _respond(context, ref, item, status)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    PitchConflictRequestModel request,
    PitchConflictRequestStatus status,
  ) async {
    final controller = TextEditingController();
    final label = switch (status) {
      PitchConflictRequestStatus.approved => 'Freigeben',
      PitchConflictRequestStatus.declined => 'Ablehnen',
      PitchConflictRequestStatus.callbackRequested => 'Rückruf anfordern',
      _ => 'Bestätigen',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.eventTitle} auf ${request.pitch}\n'
              'Konflikt: ${request.trainingScheduleValue}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Antwort (optional)',
                hintText: 'Hinweis zur Abstimmung',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      controller.dispose();
      return;
    }
    try {
      await ref.read(repositoryProvider).respondToPitchConflictRequest(
            requestId: request.id,
            status: status,
            responseMessage:
                controller.text.trim().isEmpty ? null : controller.text.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Platzanfrage: $label wurde übermittelt.')),
      );
      onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Antwort konnte nicht übermittelt werden.'),
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _PitchConflictRequestCard extends StatelessWidget {
  const _PitchConflictRequestCard({
    required this.request,
    required this.onRespond,
  });

  final PitchConflictRequestModel request;
  final ValueChanged<PitchConflictRequestStatus>? onRespond;

  @override
  Widget build(BuildContext context) {
    final incoming = request.direction == 'INCOMING';
    final color = switch (request.status) {
      PitchConflictRequestStatus.pending => AppColors.orange,
      PitchConflictRequestStatus.approved => Colors.green,
      PitchConflictRequestStatus.declined =>
        Theme.of(context).colorScheme.error,
      PitchConflictRequestStatus.callbackRequested => AppColors.blue,
      PitchConflictRequestStatus.cancelled => AppColors.muted,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  child: Icon(Icons.stadium_rounded, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            request.eventTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Chip(
                            label: Text(_pitchRequestStatus(request.status)),
                            side: BorderSide(color: color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_dateTime(request.eventStartAt)} · ${request.pitch}',
                      ),
                      Text(
                        'Betroffen: ${request.trainingTeamName} · '
                        '${request.trainingScheduleValue}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              incoming
                  ? 'Anfrage von ${request.requesterName}'
                  : 'Anfrage an ${request.recipientName}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (request.message?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(request.message!),
            ],
            if (request.responseMessage?.isNotEmpty == true) ...[
              const Divider(height: 24),
              Text('Antwort: ${request.responseMessage!}'),
            ],
            if (request.status ==
                    PitchConflictRequestStatus.callbackRequested &&
                request.recipientPhone?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri(scheme: 'tel', path: request.recipientPhone),
                ),
                icon: const Icon(Icons.phone_rounded),
                label: Text('${request.recipientName} zurückrufen'),
              ),
            ],
            if (onRespond != null) ...[
              const Divider(height: 28),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        onRespond!(PitchConflictRequestStatus.approved),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Freigeben'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        onRespond!(PitchConflictRequestStatus.declined),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Ablehnen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: request.recipientPhone?.isNotEmpty == true
                        ? () => onRespond!(
                              PitchConflictRequestStatus.callbackRequested,
                            )
                        : null,
                    icon: const Icon(Icons.phone_callback_rounded),
                    label: Text(
                      request.recipientPhone?.isNotEmpty == true
                          ? 'Bitte um Rückruf'
                          : 'Keine Telefonnummer hinterlegt',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnnouncementList extends ConsumerWidget {
  const _AnnouncementList({
    super.key,
    required this.staffView,
    required this.onChanged,
  });

  final bool staffView;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<AnnouncementModel>>(
      future:
          ref.read(repositoryProvider).announcements(includeDrafts: staffView),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorCard(onRetry: onChanged);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_outlined,
            title: 'Noch keine Mitteilungen',
            message: 'Neue Team-Nachrichten erscheinen automatisch hier.',
          );
        }
        return Column(
          children: [
            for (final item in items) ...[
              _AnnouncementCard(
                announcement: item,
                staffView: staffView,
                onOpened: () async {
                  if (!item.isRead &&
                      item.status == AnnouncementStatus.published) {
                    await ref
                        .read(repositoryProvider)
                        .markAnnouncementRead(item.id);
                    onChanged();
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.staffView,
    required this.onOpened,
  });

  final AnnouncementModel announcement;
  final bool staffView;
  final Future<void> Function() onOpened;

  @override
  Widget build(BuildContext context) {
    final color = switch (announcement.priority) {
      AnnouncementPriority.urgent => Colors.redAccent,
      AnnouncementPriority.important => AppColors.orange,
      AnnouncementPriority.normal => AppColors.blue,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(announcement.title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(announcement.body),
                      if (announcement.attachments.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Anhänge',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final attachment in announcement.attachments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file_rounded),
                            title: Text(attachment.name),
                            subtitle: Text(attachment.url),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Gelesen'),
                ),
              ],
            ),
          );
          await onOpened();
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.campaign_rounded, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          announcement.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (!announcement.isRead &&
                            announcement.status == AnnouncementStatus.published)
                          const Badge(label: Text('Neu')),
                        if (staffView)
                          Chip(label: Text(_status(announcement.status))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      announcement.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${announcement.authorName} · ${announcement.teamNames.join(', ')}'
                      '${staffView && announcement.readCount != null ? ' · ${announcement.readCount} gelesen' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<AppNotificationModel>>(
      future: ref.read(repositoryProvider).notifications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _ErrorCard(onRetry: onChanged);
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Alles erledigt',
            message: 'Aktuell gibt es keine Benachrichtigungen.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () async {
                await ref.read(repositoryProvider).markAllNotificationsRead();
                onChanged();
              },
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Alle als gelesen markieren'),
            ),
            for (final item in items)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(
                    backgroundColor:
                        (item.isRead ? AppColors.muted : AppColors.blue)
                            .withValues(alpha: .12),
                    child: Icon(
                      Icons.notifications_rounded,
                      color: item.isRead ? AppColors.muted : AppColors.blue,
                    ),
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.body),
                  trailing: item.isRead
                      ? null
                      : const Icon(Icons.circle,
                          size: 10, color: AppColors.orange),
                  onTap: item.isRead
                      ? null
                      : () async {
                          await ref
                              .read(repositoryProvider)
                              .markNotificationRead(item.id);
                          onChanged();
                        },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings({super.key});

  @override
  ConsumerState<_NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  List<NotificationPreferenceModel>? _items;
  PushConfiguration? _configuration;
  bool _subscribing = false;
  bool _nativePushEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(repositoryProvider);
    final results = await Future.wait<Object?>([
      repository.notificationPreferences(),
      repository.pushConfiguration(),
      nativePushService.currentTokenIfEnabled(),
    ]);
    if (mounted) {
      setState(() {
        _items = results[0] as List<NotificationPreferenceModel>;
        _configuration = results[1] as PushConfiguration;
        _nativePushEnabled = results[2] != null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benachrichtigungen steuern',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Lege für jede Kategorie fest, was in der App und per Push erscheinen soll.',
            ),
            const SizedBox(height: 16),
            _PushRegistrationCard(
              configuration: _configuration,
              subscribing: _subscribing,
              enabled: _nativePushEnabled,
              onSubscribe: _subscribe,
            ),
            const Divider(height: 32),
            for (var index = 0; index < items.length; index++)
              _PreferenceRow(
                value: items[index],
                onChanged: (value) => setState(() => _items![index] = value),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final saved = await ref
                    .read(repositoryProvider)
                    .saveNotificationPreferences(items);
                if (!mounted) return;
                setState(() => _items = saved);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Einstellungen gespeichert.')),
                );
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Einstellungen speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    setState(() => _subscribing = true);
    try {
      final repository = ref.read(repositoryProvider);
      if (nativePushService.supported) {
        if (_configuration?.androidConfigured != true) return;
        await repository.grantPushConsent();
        final token = await nativePushService.enable();
        if (token == null) {
          throw StateError('NOTIFICATION_PERMISSION_DENIED');
        }
        await repository.registerAndroidPushSubscription(token);
        if (mounted) setState(() => _nativePushEnabled = true);
      } else {
        final key = _configuration?.vapidPublicKey;
        if (key == null || !webPushSupported) return;
        final subscription = await subscribeToWebPush(key);
        await repository.registerWebPushSubscription(subscription);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Push-Benachrichtigungen sind jetzt aktiviert.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().contains('NOTIFICATION_PERMISSION_DENIED')
                ? 'Bitte erlaube Benachrichtigungen in den Android-Einstellungen.'
                : 'Push konnte nicht aktiviert werden. Bitte Gerätefreigabe und Verbindung prüfen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }
}

class _PushRegistrationCard extends StatelessWidget {
  const _PushRegistrationCard({
    required this.configuration,
    required this.subscribing,
    required this.enabled,
    required this.onSubscribe,
  });

  final PushConfiguration? configuration;
  final bool subscribing;
  final bool enabled;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final native = nativePushService.supported;
    final configured = native
        ? configuration?.androidConfigured == true
        : configuration?.webPushConfigured == true;
    final supported = native || webPushSupported;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = configured && supported
              ? enabled
                  ? 'Wichtige Hinweise werden auf diesem Android-Gerät zugestellt.'
                  : 'Erhalte wichtige Hinweise auch bei geschlossener App.'
              : native
                  ? 'Android-Push muss für diese Umgebung noch eingerichtet werden.'
                  : 'Web-Push muss für diese Umgebung noch eingerichtet werden.';
          final information = Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.blue,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Push auf diesem Gerät',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(description),
                  ],
                ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: configured && supported && !subscribing && !enabled
                ? onSubscribe
                : null,
            icon: Icon(
                enabled ? Icons.check_rounded : Icons.notifications_rounded),
            label: Text(
              enabled
                  ? 'Aktiv'
                  : subscribing
                      ? 'Aktiviere …'
                      : 'Aktivieren',
            ),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                information,
                const SizedBox(height: 14),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: information),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.value, required this.onChanged});

  final NotificationPreferenceModel value;
  final ValueChanged<NotificationPreferenceModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(_category(value.category))),
        const Text('In-App'),
        Switch(
          value: value.inApp,
          onChanged: (enabled) => onChanged(
            NotificationPreferenceModel(
              category: value.category,
              inApp: enabled,
              push: value.push,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text('Push'),
        Switch(
          value: value.push,
          onChanged: (enabled) => onChanged(
            NotificationPreferenceModel(
              category: value.category,
              inApp: value.inApp,
              push: enabled,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposeAnnouncementDialog extends StatefulWidget {
  const _ComposeAnnouncementDialog({required this.organization});

  final OrganizationContext organization;

  @override
  State<_ComposeAnnouncementDialog> createState() =>
      _ComposeAnnouncementDialogState();
}

class _ComposeAnnouncementDialogState
    extends State<_ComposeAnnouncementDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final Set<String> _teamIds = {widget.organization.currentTeam.id};
  AnnouncementAudience _audience = AnnouncementAudience.allMembers;
  AnnouncementPriority _priority = AnnouncementPriority.normal;
  AnnouncementStatus _status = AnnouncementStatus.published;
  bool _requireReadReceipt = false;
  bool _pushEnabled = true;
  DateTime? _publishAt;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Mitteilung'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                onChanged: (_) => setState(() {}),
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Titel'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                onChanged: (_) => setState(() {}),
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Nachricht'),
              ),
              const SizedBox(height: 16),
              Text('Mannschaften',
                  style: Theme.of(context).textTheme.titleLarge),
              for (final team in widget.organization.teams)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(team.displayName),
                  value: _teamIds.contains(team.id),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _teamIds.add(team.id);
                    } else if (_teamIds.length > 1) {
                      _teamIds.remove(team.id);
                    }
                  }),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AnnouncementAudience>(
                initialValue: _audience,
                decoration: const InputDecoration(labelText: 'Zielgruppe'),
                items: AnnouncementAudience.values
                    .where((item) => item != AnnouncementAudience.individuals)
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_audienceLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _audience = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AnnouncementPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priorität'),
                items: AnnouncementPriority.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_priorityLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _priority = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AnnouncementStatus>(
                initialValue: _status,
                decoration:
                    const InputDecoration(labelText: 'Veröffentlichung'),
                items: const [
                  DropdownMenuItem(
                    value: AnnouncementStatus.published,
                    child: Text('Sofort veröffentlichen'),
                  ),
                  DropdownMenuItem(
                    value: AnnouncementStatus.scheduled,
                    child: Text('Zeitgesteuert veröffentlichen'),
                  ),
                  DropdownMenuItem(
                    value: AnnouncementStatus.draft,
                    child: Text('Als Entwurf speichern'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
              if (_status == AnnouncementStatus.scheduled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickPublishTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(
                    _publishAt == null
                        ? 'Zeitpunkt auswählen'
                        : _dateTime(_publishAt!),
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lesebestätigung erfassen'),
                value: _requireReadReceipt,
                onChanged: (value) =>
                    setState(() => _requireReadReceipt = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Push-Benachrichtigung senden'),
                value: _pushEnabled,
                onChanged: (value) => setState(() => _pushEnabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _canSubmit
              ? () => Navigator.pop(
                    context,
                    _AnnouncementDraft(
                      title: _title.text.trim(),
                      body: _body.text.trim(),
                      teamIds: _teamIds.toList(),
                      audience: _audience,
                      priority: _priority,
                      status: _status,
                      publishAt: _publishAt,
                      requireReadReceipt: _requireReadReceipt,
                      pushEnabled: _pushEnabled,
                    ),
                  )
              : null,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty &&
      _teamIds.isNotEmpty &&
      (_status != AnnouncementStatus.scheduled || _publishAt != null);

  Future<void> _pickPublishTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      _publishAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }
}

class _AnnouncementDraft {
  const _AnnouncementDraft({
    required this.title,
    required this.body,
    required this.teamIds,
    required this.audience,
    required this.priority,
    required this.status,
    required this.publishAt,
    required this.requireReadReceipt,
    required this.pushEnabled,
  });

  final String title;
  final String body;
  final List<String> teamIds;
  final AnnouncementAudience audience;
  final AnnouncementPriority priority;
  final AnnouncementStatus status;
  final DateTime? publishAt;
  final bool requireReadReceipt;
  final bool pushEnabled;
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Daten konnten nicht geladen werden',
        message: 'Bitte prüfe die Verbindung und versuche es erneut.',
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut versuchen'),
        ),
      );
}

String _status(AnnouncementStatus value) => switch (value) {
      AnnouncementStatus.draft => 'Entwurf',
      AnnouncementStatus.scheduled => 'Geplant',
      AnnouncementStatus.published => 'Veröffentlicht',
      AnnouncementStatus.archived => 'Archiviert',
    };

String _audienceLabel(AnnouncementAudience value) => switch (value) {
      AnnouncementAudience.allMembers => 'Alle Mitglieder',
      AnnouncementAudience.parents => 'Eltern',
      AnnouncementAudience.players => 'Spieler',
      AnnouncementAudience.staff => 'Trainer & Organisation',
      AnnouncementAudience.individuals => 'Einzelne Personen',
    };

String _priorityLabel(AnnouncementPriority value) => switch (value) {
      AnnouncementPriority.normal => 'Normal',
      AnnouncementPriority.important => 'Wichtig',
      AnnouncementPriority.urgent => 'Dringend',
    };

String _category(NotificationCategory value) => switch (value) {
      NotificationCategory.event => 'Termine',
      NotificationCategory.eventReminder => 'Terminerinnerungen',
      NotificationCategory.announcement => 'Mitteilungen',
      NotificationCategory.nomination => 'Nominierungen',
      NotificationCategory.lineup => 'Aufstellungen',
      NotificationCategory.liveTicker => 'Live-Ticker',
      NotificationCategory.match => 'Spiele',
      NotificationCategory.registration => 'Registrierung',
      NotificationCategory.urgent => 'Dringende Hinweise',
      NotificationCategory.system => 'System',
    };

String _pitchRequestStatus(PitchConflictRequestStatus value) => switch (value) {
      PitchConflictRequestStatus.pending => 'Offen',
      PitchConflictRequestStatus.approved => 'Freigegeben',
      PitchConflictRequestStatus.declined => 'Abgelehnt',
      PitchConflictRequestStatus.callbackRequested => 'Rückruf gewünscht',
      PitchConflictRequestStatus.cancelled => 'Erledigt',
    };

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} Uhr';
