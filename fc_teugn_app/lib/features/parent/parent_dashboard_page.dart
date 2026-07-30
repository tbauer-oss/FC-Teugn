import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class ParentDashboardPage extends ConsumerWidget {
  const ParentDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final players = ref.watch(playersProvider).value ?? [];
    final events = [...(ref.watch(eventsProvider).value ?? <EventModel>[])];
    events.sort((a, b) => a.startAt.compareTo(b.startAt));
    final nextEvents = events
        .where((event) => event.startAt.isAfter(DateTime.now()))
        .take(3)
        .toList();

    return PageScaffold(
      title: 'Hallo ${_firstName(user?.name)}!',
      subtitle: 'Alle Termine und Rückmeldungen deiner Kinder auf einen Blick.',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.navy, AppColors.blue],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gemeinsam am Ball.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${players.length} ${players.length == 1 ? 'Kind ist' : 'Kinder sind'} deinem Konto zugeordnet.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ],
                );
                final button = OutlinedButton(
                  onPressed: () => context.go('/parent/players'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .35),
                    ),
                  ),
                  child: const Text('Meine Kinder'),
                );
                return Padding(
                  padding: EdgeInsets.all(compact ? 18 : 24),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.sports_soccer_rounded,
                                  color: AppColors.orange,
                                  size: 38,
                                ),
                                const SizedBox(width: 14),
                                Expanded(child: copy),
                              ],
                            ),
                            const SizedBox(height: 16),
                            button,
                          ],
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.sports_soccer_rounded,
                              color: AppColors.orange,
                              size: 44,
                            ),
                            const SizedBox(width: 22),
                            Expanded(child: copy),
                            const SizedBox(width: 22),
                            button,
                          ],
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Nächste Termine',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/parent/events'),
                          child: const Text('Alle ansehen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (nextEvents.isEmpty)
                      const EmptyState(
                        icon: Icons.calendar_today_rounded,
                        title: 'Alles erledigt',
                        message: 'Aktuell stehen keine weiteren Termine an.',
                      )
                    else
                      for (var i = 0; i < nextEvents.length; i++) ...[
                        _ParentEventRow(event: nextEvents[i]),
                        if (i < nextEvents.length - 1)
                          const Divider(height: 26),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _firstName(String? name) =>
      name == null || name.trim().isEmpty
          ? 'Fußballfamilie'
          : name.trim().split(' ').first;
}

class _ParentEventRow extends StatelessWidget {
  const _ParentEventRow({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final date = event.startAt.toLocal();
    final route = event.type == EventType.match
        ? '/parent/matches/${event.id}'
        : '/parent/events';
    final details = [
      '${date.day}.${date.month}.${date.year}',
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} Uhr',
      if (event.location.trim().isNotEmpty) event.location,
    ].join(' · ');
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.teal.withValues(alpha: .12),
              foregroundColor: AppColors.teal,
              child: Icon(
                event.type == EventType.match
                    ? Icons.sports_soccer_rounded
                    : Icons.sports_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
