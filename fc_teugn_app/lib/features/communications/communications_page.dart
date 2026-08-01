import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/models/organization.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/push/native_push_service.dart';
import '../../core/push/push_client.dart';
import '../auth/auth_controller.dart';
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
    const destinations = [
      _CommunicationDestination(
        label: 'Mitteilungen',
        description: 'Team-Infos verfassen und verwalten',
        icon: Icons.campaign_rounded,
      ),
      _CommunicationDestination(
        label: 'Platzanfragen',
        description: 'Überschneidungen gemeinsam klären',
        icon: Icons.stadium_rounded,
      ),
      _CommunicationDestination(
        label: 'Benachrichtigungen',
        description: 'Persönliche Hinweise im Blick behalten',
        icon: Icons.notifications_rounded,
      ),
      _CommunicationDestination(
        label: 'Einstellungen',
        description: 'Push-Nachrichten und Geräte verwalten',
        icon: Icons.tune_rounded,
      ),
    ];
    return PageScaffold(
      title: 'Mitteilungscenter',
      subtitle:
          'Alle Informationen, Abstimmungen und Benachrichtigungen zentral organisiert.',
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
          _CommunicationNavigation(
            destinations: destinations,
            selectedIndex: _tab,
            onSelected: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 24),
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

class _CommunicationDestination {
  const _CommunicationDestination({
    required this.label,
    required this.description,
    required this.icon,
  });

  final String label;
  final String description;
  final IconData icon;
}

class _CommunicationNavigation extends StatelessWidget {
  const _CommunicationNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_CommunicationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++) ...[
                  ChoiceChip(
                    avatar: Icon(destinations[index].icon, size: 18),
                    label: Text(destinations[index].label),
                    selected: selectedIndex == index,
                    onSelected: (_) => onSelected(index),
                  ),
                  if (index != destinations.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _CommunicationNavigationItem(
                    destination: destinations[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CommunicationNavigationItem extends StatelessWidget {
  const _CommunicationNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _CommunicationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.yellow.withValues(alpha: .2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? AppColors.yellow : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(destination.icon, size: 21, color: AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class _AnnouncementList extends ConsumerStatefulWidget {
  const _AnnouncementList({
    super.key,
    required this.staffView,
    required this.onChanged,
  });

  final bool staffView;
  final VoidCallback onChanged;

  @override
  ConsumerState<_AnnouncementList> createState() => _AnnouncementListState();
}

class _AnnouncementListState extends ConsumerState<_AnnouncementList> {
  String _query = '';
  AnnouncementStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final canDelete = ref.watch(authProvider).user?.role == UserRole.superAdmin;
    return FutureBuilder<List<AnnouncementModel>>(
      future: ref
          .read(repositoryProvider)
          .announcements(includeDrafts: widget.staffView),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorCard(onRetry: widget.onChanged);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_outlined,
            title: 'Noch keine Mitteilungen',
            message: 'Neue Team-Nachrichten erscheinen automatisch hier.',
          );
        }
        final normalizedQuery = _query.trim().toLowerCase();
        final filtered = items.where((item) {
          final matchesText = normalizedQuery.isEmpty ||
              item.title.toLowerCase().contains(normalizedQuery) ||
              item.body.toLowerCase().contains(normalizedQuery) ||
              item.teamNames.any(
                (name) => name.toLowerCase().contains(normalizedQuery),
              );
          return matchesText &&
              (_statusFilter == null || item.status == _statusFilter);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AnnouncementToolbar(
              itemCount: items.length,
              staffView: widget.staffView,
              statusFilter: _statusFilter,
              onSearchChanged: (value) => setState(() => _query = value),
              onStatusChanged: (value) => setState(() => _statusFilter = value),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Keine passenden Mitteilungen',
                message: 'Passe die Suche oder den Statusfilter an.',
                action: TextButton.icon(
                  onPressed: () => setState(() {
                    _query = '';
                    _statusFilter = null;
                  }),
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Filter zurücksetzen'),
                ),
              )
            else
              for (final item in filtered) ...[
                _AnnouncementCard(
                  announcement: item,
                  staffView: widget.staffView,
                  onDelete: canDelete
                      ? () => _deletePermanently(context, ref, item)
                      : null,
                  onOpened: () async {
                    if (!item.isRead &&
                        item.status == AnnouncementStatus.published) {
                      await ref
                          .read(repositoryProvider)
                          .markAnnouncementRead(item.id);
                      widget.onChanged();
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

  Future<void> _deletePermanently(
    BuildContext context,
    WidgetRef ref,
    AnnouncementModel announcement,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Mitteilung endgültig löschen?'),
        content: Text(
          '„${announcement.title}“ wird für alle Empfänger gelöscht. '
          'Auch die zugehörigen Benachrichtigungen und Lesebestätigungen '
          'werden entfernt. Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .deleteAnnouncementPermanently(announcement.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mitteilung wurde endgültig gelöscht.')),
      );
      widget.onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mitteilung konnte nicht gelöscht werden.'),
        ),
      );
    }
  }
}

class _AnnouncementToolbar extends StatelessWidget {
  const _AnnouncementToolbar({
    required this.itemCount,
    required this.staffView,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onStatusChanged,
  });

  final int itemCount;
  final bool staffView;
  final AnnouncementStatus? statusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AnnouncementStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final search = TextField(
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Mitteilungen durchsuchen',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          );
          final status = DropdownButtonFormField<AnnouncementStatus?>(
            initialValue: statusFilter,
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.filter_list_rounded),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<AnnouncementStatus?>(
                value: null,
                child: Text('Alle Status'),
              ),
              ...AnnouncementStatus.values.map(
                (value) => DropdownMenuItem<AnnouncementStatus?>(
                  value: value,
                  child: Text(_status(value)),
                ),
              ),
            ],
            onChanged: onStatusChanged,
          );
          final count = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$itemCount ${itemCount == 1 ? 'Mitteilung' : 'Mitteilungen'}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                if (staffView) ...[
                  const SizedBox(height: 10),
                  status,
                ],
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: count),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: search),
              if (staffView) ...[
                const SizedBox(width: 12),
                SizedBox(width: 220, child: status),
              ],
              const SizedBox(width: 12),
              count,
            ],
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.staffView,
    required this.onOpened,
    this.onDelete,
  });

  final AnnouncementModel announcement;
  final bool staffView;
  final Future<void> Function() onOpened;
  final Future<void> Function()? onDelete;

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
              if (onDelete != null)
                IconButton(
                  tooltip: 'Mitteilung endgültig löschen',
                  onPressed: onDelete,
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_forever_rounded),
                )
              else
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
  WebPushStatus? _webPushStatus;
  bool _subscribing = false;
  bool _nativePushEnabled = false;
  bool _testingPush = false;
  AdminPushTestResult? _pushTestResult;

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
    final configuration = results[1] as PushConfiguration;
    final webStatus = await getWebPushStatus(configuration.vapidPublicKey);
    if (mounted) {
      setState(() {
        _items = results[0] as List<NotificationPreferenceModel>;
        _configuration = results[1] as PushConfiguration;
        _nativePushEnabled = results[2] != null;
        _webPushStatus = webStatus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final isSuperAdmin =
        ref.watch(authProvider).user?.role == UserRole.superAdmin;
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
              nativeEnabled: _nativePushEnabled,
              webStatus: _webPushStatus,
              onSubscribe: _subscribe,
            ),
            if (isSuperAdmin) ...[
              const SizedBox(height: 14),
              _AdminPushTestCard(
                testing: _testingPush,
                result: _pushTestResult,
                onTest: _testPushBroadcast,
              ),
            ],
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

  Future<void> _testPushBroadcast() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.campaign_rounded),
        title: const Text('Test-Push an alle senden?'),
        content: const Text(
          'Alle freigegebenen Benutzer mit einem aktiv registrierten '
          'Push-Gerät erhalten eine klar gekennzeichnete Testnachricht. '
          'Danach wird das Zustellergebnis angezeigt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Test senden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _testingPush = true;
      _pushTestResult = null;
    });
    try {
      final result = await ref.read(repositoryProvider).sendAdminPushTest();
      if (!mounted) return;
      setState(() => _pushTestResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.subscriptions == 0
                ? 'Es ist noch kein aktives Push-Gerät registriert.'
                : '${result.sent} von ${result.subscriptions} Test-Pushnachrichten wurden vom Push-Dienst angenommen.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Der globale Push-Test konnte nicht ausgeführt werden.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _testingPush = false);
    }
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
        await repository.grantPushConsent();
        await repository.registerWebPushSubscription(subscription);
        final status = await getWebPushStatus(key);
        if (mounted) setState(() => _webPushStatus = status);
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
            _pushErrorMessage(error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  String _pushErrorMessage(Object error) {
    final value = error.toString();
    if (value.contains('IOS_HOME_SCREEN_REQUIRED')) {
      return 'Öffne die Seite in Safari, wähle „Teilen“ und „Zum Home-Bildschirm“. '
          'Starte danach FC Teugn Talents über das neue App-Symbol.';
    }
    if (value.contains('PUSH_PERMISSION_DENIED')) {
      return 'Benachrichtigungen wurden abgelehnt. Bitte erlaube sie in den '
          'Browser- beziehungsweise Systemeinstellungen.';
    }
    if (value.contains('NOTIFICATION_PERMISSION_DENIED')) {
      return 'Bitte erlaube Benachrichtigungen in den Android-Einstellungen.';
    }
    if (value.contains('WEB_PUSH_UNSUPPORTED')) {
      return 'Dieser Browser unterstützt Web-Push auf diesem Gerät nicht.';
    }
    return 'Push konnte nicht aktiviert werden. Bitte Gerätefreigabe und Verbindung prüfen.';
  }
}

class _AdminPushTestCard extends StatelessWidget {
  const _AdminPushTestCard({
    required this.testing,
    required this.result,
    required this.onTest,
  });

  final bool testing;
  final AdminPushTestResult? result;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final value = result;
    final color = value == null
        ? AppColors.blue
        : value.allSent
            ? Colors.green
            : value.subscriptions == 0
                ? AppColors.orange
                : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: color),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Systemweiter Push-Test',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
              final button = FilledButton.icon(
                onPressed: testing ? null : onTest,
                icon: testing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(testing ? 'Sende …' : 'An alle testen'),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    button,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  button,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Nur die Systemadministration kann eine Testnachricht an alle aktiv registrierten Geräte senden.',
          ),
          if (value != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${value.recipients} Empfänger')),
                Chip(
                    label:
                        Text('${value.sent}/${value.subscriptions} versendet')),
                Chip(label: Text('${value.webSubscriptions} Web')),
                Chip(label: Text('${value.androidSubscriptions} Android')),
                if (value.failed > 0)
                  Chip(label: Text('${value.failed} fehlgeschlagen')),
                if (value.pending > 0)
                  Chip(label: Text('${value.pending} ausstehend')),
              ],
            ),
            if (value.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Diagnose: ${value.errors.entries.map((item) => '${item.key} (${item.value})').join(', ')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PushRegistrationCard extends StatelessWidget {
  const _PushRegistrationCard({
    required this.configuration,
    required this.subscribing,
    required this.nativeEnabled,
    required this.webStatus,
    required this.onSubscribe,
  });

  final PushConfiguration? configuration;
  final bool subscribing;
  final bool nativeEnabled;
  final WebPushStatus? webStatus;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final native = nativePushService.supported;
    final configured = native
        ? configuration?.androidConfigured == true
        : configuration?.webPushConfigured == true;
    final status = webStatus ?? const WebPushStatus.unavailable();
    final enabled = native ? nativeEnabled : status.subscribed;
    final supported = native || status.supported;
    final canSubscribe = native || status.canSubscribe;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = _pushDescription(
            native: native,
            configured: configured,
            enabled: enabled,
            status: status,
          );
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
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Push auf diesem Gerät',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!native && status.isIos)
                          const Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('iOS Web-App'),
                          ),
                      ],
                    ),
                    Text(description),
                  ],
                ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: configured &&
                    supported &&
                    canSubscribe &&
                    !subscribing &&
                    !enabled
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

  String _pushDescription({
    required bool native,
    required bool configured,
    required bool enabled,
    required WebPushStatus status,
  }) {
    if (!configured) {
      return native
          ? 'Android-Push muss für diese Umgebung noch eingerichtet werden.'
          : 'Web-Push muss für diese Umgebung noch eingerichtet werden.';
    }
    if (native) {
      return enabled
          ? 'Wichtige Hinweise werden auf diesem Android-Gerät zugestellt.'
          : 'Erhalte wichtige Hinweise auch bei geschlossener App.';
    }
    if (status.requiresHomeScreen) {
      return 'iPhone/iPad: Öffne „Teilen“ und wähle „Zum Home-Bildschirm“. '
          'Starte anschließend die installierte FC-Teugn-Web-App und aktiviere Push hier.';
    }
    if (!status.supported) {
      return 'Dieser Browser unterstützt Web-Push auf diesem Gerät nicht.';
    }
    if (status.permission == WebPushPermission.denied) {
      return 'Benachrichtigungen sind in den Browser- oder Systemeinstellungen blockiert.';
    }
    if (status.keyMismatch) {
      return 'Der Sicherheitsschlüssel wurde aktualisiert. Aktiviere Push auf diesem Gerät bitte erneut.';
    }
    if (enabled) {
      return 'Web-Push ist aktiv – Hinweise erscheinen auch bei geschlossener Web-App.';
    }
    return 'Erhalte wichtige Hinweise auch bei geschlossener Web-App.';
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
  final _teamSearch = TextEditingController();
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
    _teamSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screen.width < 700 ? 12 : 32,
        vertical: screen.height < 700 ? 12 : 28,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 840),
        child: SizedBox(
          width: 980,
          child: Column(
            children: [
              _buildHeader(context),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    if (compact) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMessageEditor(context),
                            const SizedBox(height: 24),
                            _buildRecipientPanel(context, compact: true),
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: _buildMessageEditor(context),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildRecipientPanel(context),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.edit_notifications_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Neue Mitteilung',
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  'Nachricht verfassen, Empfänger wählen und Versand planen',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Schließen',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          step: '1',
          title: 'Mitteilung verfassen',
          subtitle: 'Formuliere die Information kurz und eindeutig.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _title,
          onChanged: (_) => setState(() {}),
          maxLength: 160,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Titel',
            hintText: 'Worum geht es?',
            prefixIcon: Icon(Icons.title_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          onChanged: (_) => setState(() {}),
          minLines: 7,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Nachricht',
            hintText: 'Alle wichtigen Informationen für die Empfänger …',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 22),
        Text('Versandoptionen', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 520;
            final fields = [
              DropdownButtonFormField<AnnouncementPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priorität',
                  prefixIcon: Icon(Icons.flag_rounded),
                ),
                items: AnnouncementPriority.values
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(_priorityLabel(item)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _priority = value!),
              ),
              DropdownButtonFormField<AnnouncementStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Veröffentlichung',
                  prefixIcon: Icon(Icons.schedule_send_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AnnouncementStatus.published,
                    child: Text('Sofort veröffentlichen'),
                  ),
                  DropdownMenuItem(
                    value: AnnouncementStatus.scheduled,
                    child: Text('Zeitgesteuert'),
                  ),
                  DropdownMenuItem(
                    value: AnnouncementStatus.draft,
                    child: Text('Als Entwurf'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
            ];
            return stack
                ? Column(children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1]
                  ])
                : Row(children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 12),
                    Expanded(child: fields[1])
                  ]);
          },
        ),
        if (_status == AnnouncementStatus.scheduled) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickPublishTime,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                _publishAt == null
                    ? 'Veröffentlichungszeit wählen'
                    : 'Geplant für ${_dateTime(_publishAt!)}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _OptionSwitch(
          icon: Icons.mark_email_read_rounded,
          title: 'Lesebestätigung erfassen',
          subtitle: 'Zeigt, wie viele Empfänger die Mitteilung geöffnet haben.',
          value: _requireReadReceipt,
          onChanged: (value) => setState(() => _requireReadReceipt = value),
        ),
        const SizedBox(height: 8),
        _OptionSwitch(
          icon: Icons.notifications_active_rounded,
          title: 'Push-Benachrichtigung senden',
          subtitle:
              'Informiert die ausgewählten Empfänger direkt auf ihren Geräten.',
          value: _pushEnabled,
          onChanged: (value) => setState(() => _pushEnabled = value),
        ),
      ],
    );
  }

  Widget _buildRecipientPanel(BuildContext context, {bool compact = false}) {
    final query = _teamSearch.text.trim().toLowerCase();
    final teams = widget.organization.teams
        .where((team) => team.displayName.toLowerCase().contains(query))
        .toList();
    final list = Column(
      children: [
        for (final team in teams)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _TeamSelectionTile(
              name: team.displayName,
              selected: _teamIds.contains(team.id),
              onChanged: (selected) => setState(() {
                if (selected) {
                  _teamIds.add(team.id);
                } else {
                  _teamIds.remove(team.id);
                }
              }),
            ),
          ),
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          step: '2',
          title: 'Empfänger auswählen',
          subtitle: 'Bestimme Mannschaften und Zielgruppe.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _teamSearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Mannschaft suchen',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Suche löschen',
                    onPressed: () => setState(_teamSearch.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _teamIds
                    .addAll(widget.organization.teams.map((team) => team.id));
              }),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Alle'),
            ),
            TextButton.icon(
              onPressed:
                  _teamIds.isEmpty ? null : () => setState(_teamIds.clear),
              icon: const Icon(Icons.remove_done_rounded, size: 18),
              label: const Text('Keine'),
            ),
            const Spacer(),
            Text(
              '${_teamIds.length} gewählt',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (teams.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Keine Mannschaft gefunden.')),
          )
        else if (compact)
          list
        else
          Expanded(child: SingleChildScrollView(child: list)),
        const SizedBox(height: 12),
        DropdownButtonFormField<AnnouncementAudience>(
          initialValue: _audience,
          decoration: const InputDecoration(
            labelText: 'Zielgruppe',
            prefixIcon: Icon(Icons.groups_rounded),
          ),
          items: AnnouncementAudience.values
              .where((item) => item != AnnouncementAudience.individuals)
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(_audienceLabel(item)),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _audience = value!),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.yellow.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.yellow.withValues(alpha: .55)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.outgoing_mail, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _teamIds.isEmpty
                      ? 'Wähle mindestens eine Mannschaft aus.'
                      : '${_teamIds.length} ${_teamIds.length == 1 ? 'Mannschaft' : 'Mannschaften'} · ${_audienceLabel(_audience)}${_pushEnabled ? ' · mit Push' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return compact ? content : SizedBox.expand(child: content);
  }

  Widget _buildFooter(BuildContext context) {
    final actionLabel = switch (_status) {
      AnnouncementStatus.draft => 'Entwurf speichern',
      AnnouncementStatus.scheduled => 'Mitteilung einplanen',
      _ => 'Jetzt veröffentlichen',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 700)
            Expanded(
              child: Text(
                'Pflichtfelder: Titel, Nachricht und mindestens eine Mannschaft',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            )
          else
            const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: Icon(_status == AnnouncementStatus.draft
                ? Icons.save_outlined
                : Icons.send_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  void _submit() => Navigator.pop(
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
      );

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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final String step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        secondary: Icon(icon, color: AppColors.gold),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _TeamSelectionTile extends StatelessWidget {
  const _TeamSelectionTile({
    required this.name,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.yellow.withValues(alpha: .16)
          : AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.yellow : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.groups_rounded, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ],
          ),
        ),
      ),
    );
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
