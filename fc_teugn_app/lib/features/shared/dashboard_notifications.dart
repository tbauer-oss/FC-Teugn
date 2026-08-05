import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/providers.dart';

class DashboardNotifications extends ConsumerWidget {
  const DashboardNotifications({
    super.key,
    required this.notifications,
    required this.isTrainer,
  });

  final List<AppNotificationModel> notifications;
  final bool isTrainer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = notifications.where((item) => !item.isRead).toList();
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
        onTap: () => _open(context, ref, latest),
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
    WidgetRef ref,
    AppNotificationModel item,
  ) async {
    try {
      await ref.read(repositoryProvider).markNotificationRead(item.id);
      ref.invalidate(liveNotificationsProvider);
    } catch (_) {
      // Die Zielseite bleibt auch bei einer kurzzeitig fehlenden Verbindung
      // erreichbar; gelesen wird beim nächsten Versuch synchronisiert.
    }
    if (!context.mounted) return;
    final prefix = isTrainer ? '/trainer' : '/parent';
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
      NotificationCategory.registration when isTrainer => '/trainer/approvals',
      NotificationCategory.event ||
      NotificationCategory.eventReminder =>
        '$prefix/events',
      _ => prefix,
    };
    context.go(route);
  }
}
