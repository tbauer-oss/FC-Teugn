import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class ParentMatchesPage extends ConsumerWidget {
  const ParentMatchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    return PageScaffold(
      title: 'Spiele',
      subtitle: 'Spielplan, Treffpunkt und Ergebnisse der Mannschaft.',
      child: events.when(
        data: (items) {
          final matches = items.where((event) => event.type == EventType.match).toList()
            ..sort((a, b) => b.startAt.compareTo(a.startAt));
          if (matches.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_soccer_rounded,
              title: 'Noch keine Spiele',
              message: 'Sobald das Trainerteam einen Spieltag plant, erscheint er hier.',
            );
          }
          return Column(
            children: [
              for (final match in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _PublicMatchCard(event: match),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Spielplan nicht erreichbar',
          message: 'Bitte versuche es in einem Moment erneut.',
        ),
      ),
    );
  }
}

class _PublicMatchCard extends StatelessWidget {
  const _PublicMatchCard({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final details = event.matchDetails;
    final date = event.startAt.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Chip(label: Text(details?.competition ?? 'Spiel')),
                const Spacer(),
                Text('${date.day}.${date.month}.${date.year}'),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text('FC Teugn', textAlign: TextAlign.center, style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  )),
                ),
                Text(
                  details?.ourGoals != null && details?.theirGoals != null
                      ? '${details!.ourGoals} : ${details.theirGoals}'
                      : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Expanded(
                  child: Text(
                    details?.opponent ?? event.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(event.location),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
