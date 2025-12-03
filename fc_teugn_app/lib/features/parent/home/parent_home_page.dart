import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/models/match.dart';
import '../../../core/models/event.dart';
import '../../../core/models/training.dart';

class ParentHomePage extends ConsumerWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);

    final meFuture = ref.watch(_meProvider);
    final matchesFuture = ref.watch(_matchesProvider(repo));
    final eventsFuture = ref.watch(_eventsProvider(repo));
    final trainingsFuture = ref.watch(_trainingsProvider(repo));

    return Scaffold(
      appBar: AppBar(title: const Text('Übersicht')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Hallo, schön dass du da bist!', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          meFuture.when(
            data: (me) => Card(
              child: ListTile(
                title: Text(me.user.name),
                subtitle: Text('Deine Spieler*innen: ${me.players.map((p) => p.fullName).join(', ')}'),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler beim Laden: $e'),
          ),
          const SizedBox(height: 16),
          Text('Nächste Termine', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          trainingsFuture.when(
            data: (list) => _UpcomingCard(
              title: 'Training',
              items: list.take(2).toList(),
              builder: (item) => Text(
                '${_formatDate(item.date)} • ${item.location}',
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Fehler Trainings: $e'),
          ),
          matchesFuture.when(
            data: (list) => _UpcomingCard(
              title: 'Spiele',
              items: list.take(2).toList(),
              builder: (MatchModel m) => Text(
                '${_formatDate(m.date)} • ${m.isHome ? 'Heim' : 'Auswärts'} vs. ${m.opponent}',
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Fehler Spiele: $e'),
          ),
          eventsFuture.when(
            data: (list) => _UpcomingCard(
              title: 'Events',
              items: list.take(2).toList(),
              builder: (EventModel e) => Text('${_formatDate(e.date)} • ${e.title}'),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Fehler Events: $e'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day}.${date.month}.${date.year}';
}

final _meProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.me();
});

final _matchesProvider = FutureProvider.autoDispose.family<List<MatchModel>, dynamic>((ref, _) async {
  final repo = ref.watch(repositoryProvider);
  return repo.matches();
});

final _eventsProvider = FutureProvider.autoDispose.family<List<EventModel>, dynamic>((ref, _) async {
  final repo = ref.watch(repositoryProvider);
  return repo.events();
});

final _trainingsProvider = FutureProvider.autoDispose.family<List<Training>, dynamic>((ref, _) async {
  final repo = ref.watch(repositoryProvider);
  return repo.trainings();
});

class _UpcomingCard<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(T) builder;

  const _UpcomingCard({required this.title, required this.items, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (items.isEmpty) const Text('Keine Einträge'),
            ...items.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: builder(e))).toList(),
          ],
        ),
      ),
    );
  }
}
