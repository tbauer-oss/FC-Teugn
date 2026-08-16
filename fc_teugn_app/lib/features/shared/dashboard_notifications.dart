import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/providers.dart';

class DashboardNotifications extends ConsumerStatefulWidget {
  const DashboardNotifications({
    super.key,
    required this.notifications,
    required this.isTrainer,
  });

  final List<AppNotificationModel> notifications;
  final bool isTrainer;

  @override
  ConsumerState<DashboardNotifications> createState() =>
      _DashboardNotificationsState();
}

class _DashboardNotificationsState
    extends ConsumerState<DashboardNotifications> {
  final Set<String> _locallyReadIds = <String>{};
  final Set<String> _markingIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final unread = widget.notifications
        .where(
          (item) =>
              !item.isRead &&
              !_locallyReadIds.contains(item.id) &&
              // Für Trainer ist die Mitgliedsanfragen-Karte direkt darunter
              // die autoritative Anzeige. Eine zweite, möglicherweise alte
              // Registrierungsbenachrichtigung darf ihr nicht widersprechen.
              !(widget.isTrainer &&
                  item.category == NotificationCategory.registration),
        )
        .toList();
    if (unread.isEmpty) return const SizedBox.shrink();
    final latest = unread.first;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.yellowSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: .35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(context, latest),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Badge.count(
                count: unread.length,
                child: const CircleAvatar(
                  backgroundColor: AppColors.yellow,
                  foregroundColor: AppColors.black,
                  child: Icon(Icons.notifications_active_rounded),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      latest.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      latest.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Ohne Öffnen als gelesen markieren',
                child: IconButton.filledTonal(
                  onPressed: _markingIds.contains(latest.id)
                      ? null
                      : () => _markRead(latest, showConfirmation: true),
                  icon: _markingIds.contains(latest.id)
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_rounded),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unread.length == 1 ? 'Öffnen' : '+${unread.length - 1}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    AppNotificationModel item,
  ) async {
    await _markRead(item);
    if (!context.mounted) return;
    final prefix = widget.isTrainer ? '/trainer' : '/parent';
    final id = Uri.tryParse(item.actionUrl ?? '')?.pathSegments.lastOrNull;
    final route = switch (item.category) {
      NotificationCategory.announcement ||
      NotificationCategory.urgent =>
        '$prefix/messages',
      NotificationCategory.nomination ||
      NotificationCategory.lineup ||
      NotificationCategory.liveTicker ||
      NotificationCategory.match =>
        id == null ? '$prefix/matches' : '$prefix/matches/$id',
      NotificationCategory.registration when widget.isTrainer =>
        '/trainer/approvals',
      NotificationCategory.event ||
      NotificationCategory.eventReminder =>
        '$prefix/events',
      _ => prefix,
    };
    context.go(route);
  }

  Future<void> _markRead(
    AppNotificationModel item, {
    bool showConfirmation = false,
  }) async {
    if (_locallyReadIds.contains(item.id) || _markingIds.contains(item.id)) {
      return;
    }
    setState(() {
      _locallyReadIds.add(item.id);
      _markingIds.add(item.id);
    });
    try {
      await ref.read(repositoryProvider).markNotificationRead(item.id);
      ref.invalidate(liveNotificationsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _locallyReadIds.remove(item.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Benachrichtigung konnte noch nicht quittiert werden.'),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _markingIds.remove(item.id));
    }
    if (showConfirmation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Als gelesen markiert.')),
      );
    }
  }
}
