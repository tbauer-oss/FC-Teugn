import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class ParentPlayersPage extends ConsumerWidget {
  const ParentPlayersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Meine Spieler', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Expanded(
            child: players.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('Noch keine Spieler zugewiesen.'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final player = items[index];
                    return ListTile(
                      title: Text(player.fullName),
                      subtitle: Text(player.position ?? 'Position unbekannt'),
                      trailing: Text(player.shirtNumber != null ? '#${player.shirtNumber}' : ''),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Fehler: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
