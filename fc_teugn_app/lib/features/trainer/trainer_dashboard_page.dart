import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class TrainerDashboardPage extends ConsumerWidget {
  const TrainerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final players = ref.watch(playersProvider);
    final events = ref.watch(eventsProvider);
    final approvals = ref.watch(pendingUsersProvider);
    final upcoming = [...(events.value ?? <EventModel>[])]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final nextEvents = upcoming
        .where((event) => event.startAt.isAfter(DateTime.now()))
        .take(4)
        .toList();

    return PageScaffold(
      title: 'Hallo ${_firstName(user?.name)}!',
      subtitle: 'Hier ist der aktuelle Stand deiner Jugendmannschaft.',
      action: FilledButton.icon(
        onPressed: () => context.go('/trainer/events'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Termin planen'),
      ),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 1100 ? 3 : 1,
            childAspectRatio: MediaQuery.sizeOf(context).width >= 1100 ? 1.65 : 2.5,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              MetricCard(
                label: 'Spieler im Team',
                value: '${players.value?.length ?? '–'}',
                icon: Icons.groups_rounded,
                color: AppColors.blue,
                caption: players.isLoading ? 'Wird geladen …' : 'Aktueller Kader',
              ),
              MetricCard(
                label: 'Nächste Termine',
                value: '${nextEvents.length}',
                icon: Icons.calendar_month_rounded,
                color: AppColors.teal,
                caption: 'In den kommenden Wochen',
              ),
              MetricCard(
                label: 'Offene Freigaben',
                value: '${approvals.value?.length ?? '–'}',
                icon: Icons.person_add_alt_1_rounded,
                color: AppColors.orange,
                caption: 'Neue Vereinsmitglieder',
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final schedule = _ScheduleCard(events: nextEvents);
              const shortcuts = _ShortcutCard();
              if (!wide) {
                return Column(children: [schedule, const SizedBox(height: 18), shortcuts]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: schedule),
                  const SizedBox(width: 18),
                  const Expanded(flex: 2, child: _ShortcutCard()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _firstName(String? name) {
    if (name == null || name.trim().isEmpty) return 'Trainerteam';
    return name.trim().split(RegExp(r'\s+')).first;
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.events});

  final List<EventModel> events;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Als Nächstes', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/trainer/events'),
                  child: const Text('Alle Termine'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (events.isEmpty)
              const EmptyState(
                icon: Icons.event_available_rounded,
                title: 'Noch keine Termine',
                message: 'Plane das nächste Training oder Spiel für dein Team.',
              )
            else
              for (var index = 0; index < events.length; index++) ...[
                _EventRow(event: events[index]),
                if (index < events.length - 1) const Divider(height: 24),
              ],
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final date = event.startAt.toLocal();
    return Row(
      children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                _month(date.month),
                style: const TextStyle(
                  color: AppColors.blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
              Text(
                '${date.day}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 3),
              Text('${_time(date)} Uhr · ${event.location}'),
            ],
          ),
        ),
        Icon(
          event.type == EventType.match
              ? Icons.sports_soccer_rounded
              : event.type == EventType.training
                  ? Icons.sports_rounded
                  : Icons.celebration_rounded,
          color: AppColors.muted,
        ),
      ],
    );
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _month(int value) => const [
    'JAN', 'FEB', 'MÄR', 'APR', 'MAI', 'JUN',
    'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEZ',
  ][value - 1];
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard();

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Spieler verwalten', Icons.groups_rounded, '/trainer/players'),
      ('Freigaben prüfen', Icons.verified_user_rounded, '/trainer/approvals'),
      ('Spieltag planen', Icons.sports_soccer_rounded, '/trainer/matches'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schnellzugriff', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => context.go(action.$3),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(action.$2, color: AppColors.blue, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(action.$1, style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ))),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
