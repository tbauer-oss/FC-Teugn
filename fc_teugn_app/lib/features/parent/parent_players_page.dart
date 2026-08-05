import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
          Text('Meine Spieler',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Expanded(
            child: players.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                      child: Text('Noch keine Spieler zugewiesen.'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final player = items[index];
                    return ListTile(
                      onTap: () => context.push('/parent/players/${player.id}'),
                      leading: CircleAvatar(
                        child: Text(
                          player.initials,
                        ),
                      ),
                      title: Text(player.fullName),
                      subtitle: Text(
                        [
                          player.position ?? 'Position unbekannt',
                          '${player.goals} Tore',
                          '${player.assists} Assists',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: LogoLoadingPanel(message: 'Kinder werden geladen …'),
              ),
              error: (err, _) => Center(child: Text('Fehler: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
