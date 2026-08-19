import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/dashboard_summary.dart';

enum ParentConsentPromptAction { later, review }

class ParentConsentReminderCard extends StatelessWidget {
  const ParentConsentReminderCard({
    super.key,
    required this.items,
  });

  final List<ParentConsentAttention> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final openCount = items.fold<int>(0, (sum, item) => sum + item.openCount);
    return Card(
      color: AppColors.yellow.withValues(alpha: .14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Einwilligungen prüfen',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  openCount == 1
                      ? 'Eine freiwillige Entscheidung ist noch offen.'
                      : '$openCount freiwillige Entscheidungen sind noch offen.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            );
            final action = FilledButton.icon(
              onPressed: () => context.go(
                '/parent/players/${items.first.playerId}?consents=1',
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Jetzt prüfen'),
            );
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_outlined),
                      const SizedBox(width: 12),
                      Expanded(child: copy),
                    ],
                  ),
                  const SizedBox(height: 12),
                  action,
                ],
              );
            }
            return Row(
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 12),
                Expanded(child: copy),
                const SizedBox(width: 12),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class ParentConsentPromptDialog extends StatelessWidget {
  const ParentConsentPromptDialog({
    super.key,
    required this.items,
  });

  final List<ParentConsentAttention> items;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final openCount = items.fold<int>(0, (sum, item) => sum + item.openCount);
    return AlertDialog(
      icon: const Icon(
        Icons.verified_user_outlined,
        color: AppColors.gold,
        size: 34,
      ),
      title: const Text('Einwilligungen gemeinsam prüfen'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openCount == 1
                    ? 'Für dein Kind ist noch eine Einwilligungsentscheidung offen.'
                    : 'Für deine Kinder sind noch $openCount Einwilligungsentscheidungen offen.',
              ),
              const SizedBox(height: 10),
              const Text(
                'Bitte prüfe jeden Bereich einzeln. Jede Einwilligung ist '
                'freiwillig und kann erteilt oder ausdrücklich abgelehnt '
                'werden. Eine erteilte Einwilligung lässt sich später jederzeit '
                'für die Zukunft widerrufen.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        Row(
                          children: [
                            const Icon(Icons.child_care_rounded, size: 21),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                items[index].playerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${items[index].openCount} offen',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (index < items.length - 1) const Divider(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: compact
          ? [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    ParentConsentPromptAction.review,
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Jetzt prüfen'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    ParentConsentPromptAction.later,
                  ),
                  child: const Text('Später erinnern'),
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  ParentConsentPromptAction.later,
                ),
                child: const Text('Später erinnern'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  ParentConsentPromptAction.review,
                ),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Jetzt prüfen'),
              ),
            ],
    );
  }
}
