import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/providers.dart';
import '../../core/push/push_action_route.dart';

/// Kompakter Einstieg in die Benachrichtigungen einer Startseite.
///
/// Mitgliedsfreigaben werden im Trainerbereich weiterhin ausschließlich über
/// die autoritative Anfragen-Karte angezeigt. So kann eine alte Pushmeldung
/// nicht einer bereits erledigten Freigabe widersprechen.
class DashboardNotificationBell extends ConsumerStatefulWidget {
  const DashboardNotificationBell({
    super.key,
    required this.notifications,
    required this.isTrainer,
  });

  final List<AppNotificationModel> notifications;
  final bool isTrainer;

  @override
  ConsumerState<DashboardNotificationBell> createState() =>
      _DashboardNotificationBellState();
}

class _DashboardNotificationBellState
    extends ConsumerState<DashboardNotificationBell> {
  final Set<String> _locallyReadIds = <String>{};

  List<AppNotificationModel> get _visibleNotifications {
    final values = widget.notifications
        .where(
          (item) =>
              !item.isRead &&
              !_locallyReadIds.contains(item.id) &&
              !(widget.isTrainer &&
                  item.category == NotificationCategory.registration),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  int get _unreadCount => _visibleNotifications.length;

  @override
  Widget build(BuildContext context) {
    final unreadCount = _unreadCount;
    final button = SizedBox.square(
      dimension: 52,
      child: IconButton(
        key: const ValueKey('dashboard-notification-bell'),
        tooltip: unreadCount == 0
            ? 'Benachrichtigungen'
            : '$unreadCount ungelesene Benachrichtigungen',
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints.tightFor(width: 52, height: 52),
        onPressed: () => _showNotifications(context),
        icon: Icon(
          unreadCount == 0
              ? Icons.notifications_none_rounded
              : Icons.notifications_rounded,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: unreadCount == 0
          ? 'Benachrichtigungen, keine ungelesen'
          : 'Benachrichtigungen, $unreadCount ungelesen',
      child: unreadCount == 0
          ? button
          : Badge.count(
              count: unreadCount,
              backgroundColor: Theme.of(context).colorScheme.error,
              textColor: Colors.white,
              offset: const Offset(-3, 3),
              child: button,
            ),
    );
  }

  Future<void> _showNotifications(BuildContext pageContext) async {
    final compact = MediaQuery.sizeOf(pageContext).width < 700;
    final panel = DashboardNotificationPanel(
      notifications: _visibleNotifications,
      isTrainer: widget.isTrainer,
      navigationContext: pageContext,
      initiallyReadIds: _locallyReadIds,
      onReadStateChanged: (ids) {
        if (!mounted) return;
        setState(() {
          _locallyReadIds
            ..clear()
            ..addAll(ids);
        });
      },
    );
    if (compact) {
      await showModalBottomSheet<void>(
        context: pageContext,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Theme.of(pageContext).colorScheme.surface,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(pageContext).height * .78,
        ),
        builder: (_) => panel,
      );
      return;
    }
    await showDialog<void>(
      context: pageContext,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 660),
          child: panel,
        ),
      ),
    );
  }
}

class DashboardNotificationPanel extends ConsumerStatefulWidget {
  const DashboardNotificationPanel({
    super.key,
    required this.notifications,
    required this.isTrainer,
    required this.navigationContext,
    required this.initiallyReadIds,
    required this.onReadStateChanged,
  });

  final List<AppNotificationModel> notifications;
  final bool isTrainer;
  final BuildContext navigationContext;
  final Set<String> initiallyReadIds;
  final ValueChanged<Set<String>> onReadStateChanged;

  @override
  ConsumerState<DashboardNotificationPanel> createState() =>
      _DashboardNotificationPanelState();
}

class _DashboardNotificationPanelState
    extends ConsumerState<DashboardNotificationPanel> {
  late final Set<String> _locallyReadIds = {...widget.initiallyReadIds};
  final Set<String> _markingIds = <String>{};
  bool _markingAll = false;

  bool _isUnread(AppNotificationModel item) =>
      !item.isRead && !_locallyReadIds.contains(item.id);

  @override
  Widget build(BuildContext context) {
    final unreadNotifications =
        widget.notifications.where(_isUnread).toList(growable: false);
    final unreadCount = unreadNotifications.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.appColors.brandSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.notifications_rounded,
                  color: context.appWarning,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Benachrichtigungen',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      unreadCount == 0
                          ? 'Alles gelesen'
                          : '$unreadCount ungelesen',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.appColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Schließen',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (unreadCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('mark-all-notifications-read'),
                onPressed: _markingAll ? null : _markAllRead,
                icon: _markingAll
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all_rounded, size: 19),
                label: const Text('Alle als gelesen markieren'),
              ),
            ),
          ),
        const Divider(height: 1),
        Flexible(
          child: unreadNotifications.isEmpty
              ? const _EmptyNotificationPanel()
              : ListView.separated(
                  key: const ValueKey('dashboard-notification-list'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: unreadNotifications.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 58,
                  ),
                  itemBuilder: (context, index) {
                    final item = unreadNotifications[index];
                    return _NotificationRow(
                      item: item,
                      unread: _isUnread(item),
                      marking: _markingIds.contains(item.id),
                      onOpen: () => _open(item),
                      onMarkRead: () => _markRead(item, confirm: true),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _open(AppNotificationModel item) async {
    await _markRead(item);
    if (!mounted) return;
    final prefix = widget.isTrainer ? '/trainer' : '/parent';
    final route =
        item.category == NotificationCategory.registration && widget.isTrainer
            ? '/trainer/approvals'
            : roleCorrectPushActionRoute(
                item.actionUrl ?? prefix,
                isTrainer: widget.isTrainer,
              );
    Navigator.of(context).pop();
    if (widget.navigationContext.mounted) {
      widget.navigationContext.go(route);
    }
  }

  Future<void> _markRead(
    AppNotificationModel item, {
    bool confirm = false,
  }) async {
    if (!_isUnread(item) || _markingIds.contains(item.id)) return;
    setState(() {
      _locallyReadIds.add(item.id);
      _markingIds.add(item.id);
    });
    widget.onReadStateChanged({..._locallyReadIds});
    try {
      await ref.read(repositoryProvider).markNotificationRead(item.id);
      _invalidateNotificationSources();
    } catch (_) {
      if (!mounted) return;
      setState(() => _locallyReadIds.remove(item.id));
      widget.onReadStateChanged({..._locallyReadIds});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Benachrichtigung konnte nicht gespeichert werden.'),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _markingIds.remove(item.id));
    }
    if (confirm && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Als gelesen markiert.')),
      );
    }
  }

  Future<void> _markAllRead() async {
    final unreadIds =
        widget.notifications.where(_isUnread).map((item) => item.id).toSet();
    if (unreadIds.isEmpty || _markingAll) return;
    setState(() {
      _markingAll = true;
      _locallyReadIds.addAll(unreadIds);
    });
    widget.onReadStateChanged({..._locallyReadIds});
    try {
      await ref.read(repositoryProvider).markAllNotificationsRead();
      _invalidateNotificationSources();
    } catch (_) {
      if (!mounted) return;
      setState(() => _locallyReadIds.removeAll(unreadIds));
      widget.onReadStateChanged({..._locallyReadIds});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Benachrichtigungen konnten nicht gespeichert werden.'),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Benachrichtigungen sind gelesen.')),
      );
    }
  }

  void _invalidateNotificationSources() {
    ref.invalidate(liveNotificationsProvider);
    ref.invalidate(parentDashboardSummaryProvider);
    ref.invalidate(trainerDashboardSummaryProvider);
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.unread,
    required this.marking,
    required this.onOpen,
    required this.onMarkRead,
  });

  final AppNotificationModel item;
  final bool unread;
  final bool marking;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final color = _notificationColor(item.category);
    return Material(
      color: unread ? context.appColors.brandSoft : context.appColors.surface,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 5, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _notificationIcon(item.category),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  unread ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _notificationDate(item.createdAt),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: context.appColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.appColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (unread)
                IconButton(
                  tooltip: 'Ohne Öffnen als gelesen markieren',
                  visualDensity: VisualDensity.compact,
                  onPressed: marking ? null : onMarkRead,
                  icon: marking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_rounded, size: 20),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(11, 11, 11, 0),
                  child: Icon(
                    Icons.done_all_rounded,
                    size: 18,
                    color: context.appColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotificationPanel extends StatelessWidget {
  const _EmptyNotificationPanel();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 38,
              color: context.appColors.textMuted,
            ),
            const SizedBox(height: 10),
            const Text(
              'Keine ungelesenen Benachrichtigungen',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Gelesene Hinweise findest du weiterhin im Mitteilungscenter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textMuted),
            ),
          ],
        ),
      );
}

IconData _notificationIcon(NotificationCategory category) => switch (category) {
      NotificationCategory.event => Icons.event_rounded,
      NotificationCategory.eventReminder => Icons.alarm_rounded,
      NotificationCategory.announcement => Icons.campaign_rounded,
      NotificationCategory.nomination => Icons.groups_rounded,
      NotificationCategory.lineup => Icons.account_tree_rounded,
      NotificationCategory.liveTicker => Icons.sports_soccer_rounded,
      NotificationCategory.match => Icons.emoji_events_rounded,
      NotificationCategory.registration => Icons.person_add_rounded,
      NotificationCategory.urgent => Icons.warning_amber_rounded,
      NotificationCategory.system => Icons.info_outline_rounded,
    };

Color _notificationColor(NotificationCategory category) => switch (category) {
      NotificationCategory.urgent => Colors.red,
      NotificationCategory.liveTicker ||
      NotificationCategory.match =>
        Colors.green,
      NotificationCategory.registration => Colors.blue,
      _ => AppColors.gold,
    };

String _notificationDate(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  String two(int number) => number.toString().padLeft(2, '0');
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${two(local.hour)}:${two(local.minute)}';
  }
  return '${two(local.day)}.${two(local.month)}.';
}

/// Kompatibilitäts-Wrapper für bestehende Einbindungen und Tests.
class DashboardNotifications extends StatelessWidget {
  const DashboardNotifications({
    super.key,
    required this.notifications,
    required this.isTrainer,
  });

  final List<AppNotificationModel> notifications;
  final bool isTrainer;

  @override
  Widget build(BuildContext context) => DashboardNotificationBell(
        notifications: notifications,
        isTrainer: isTrainer,
      );
}
