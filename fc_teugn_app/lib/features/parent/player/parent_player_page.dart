import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/player.dart';
import '../../../core/providers.dart';

class ParentPlayerPage extends ConsumerWidget {
  const ParentPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mein Spieler')), 
      body: me.when(
        data: (details) {
          if (details.players.isEmpty) {
            return const Center(child: Text('Kein Spieler verknüpft.')); 
          }
          final player = details.players.first;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 32, child: Text(player.firstName[0])),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(player.fullName, style: Theme.of(context).textTheme.titleLarge),
                      Text('Team: ${player.team ?? 'E2/E3'}'),
                      Text('Position: ${player.position ?? 'flexibel'}'),
                    ]),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Geburtstag: ${player.birthDate.day}.${player.birthDate.month}.${player.birthDate.year}'),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatTile(label: 'Spiele', value: player.stats?.games ?? 0),
                        _StatTile(label: 'Tore', value: player.stats?.goals ?? 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value.toString(), style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ],
    );
  }
}

final _meProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.me();
});
