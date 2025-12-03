import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/match.dart';
import '../../../core/models/player.dart';
import '../../../core/providers.dart';
import '../../../core/models/event.dart';

class ParentMatchesPage extends ConsumerStatefulWidget {
  const ParentMatchesPage({super.key});

  @override
  ConsumerState<ParentMatchesPage> createState() => _ParentMatchesPageState();
}

class _ParentMatchesPageState extends ConsumerState<ParentMatchesPage> {
  PlayerModel? selectedPlayer;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final me = ref.watch(_meProvider);
    final matches = ref.watch(_matchesProvider(repo));

    return Scaffold(
      appBar: AppBar(title: const Text('Spiele & RSVPs')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            me.when(
              data: (details) {
                selectedPlayer ??= details.players.isNotEmpty ? details.players.first : null;
                return Row(
                  children: [
                    const Text('Mein Spieler:'),
                    const SizedBox(width: 8),
                    DropdownButton<PlayerModel>(
                      value: selectedPlayer,
                      onChanged: (p) => setState(() => selectedPlayer = p),
                      items: details.players
                          .map((p) => DropdownMenuItem(value: p, child: Text(p.fullName)))
                          .toList(),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Fehler: $e'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.when(
                data: (list) => ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final match = list[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${match.type == MatchType.league ? 'Pflichtspiel' : 'Testspiel'} - ${match.opponent}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('${_formatDate(match.date)} • ${match.isHome ? 'Heim' : 'Auswärts'} • ${match.location}'),
                            if (match.ourGoals != null && match.theirGoals != null)
                              Text('Ergebnis: ${match.ourGoals}:${match.theirGoals}'),
                            if (match.notes != null) Text(match.notes!),
                            const SizedBox(height: 8),
                            if (selectedPlayer != null)
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: () async {
                                      await repo.setMatchRsvp(match.id, selectedPlayer!.id, RSVPStatus.yes);
                                      ref.refresh(_matchesProvider(repo));
                                    },
                                    child: const Text('Zusage'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      await repo.setMatchRsvp(match.id, selectedPlayer!.id, RSVPStatus.no);
                                      ref.refresh(_matchesProvider(repo));
                                    },
                                    child: const Text('Absage'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      await repo.setMatchRsvp(match.id, selectedPlayer!.id, RSVPStatus.maybe);
                                      ref.refresh(_matchesProvider(repo));
                                    },
                                    child: const Text('Offen'),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Text('Aufstellung', style: Theme.of(context).textTheme.titleSmall),
                            if (match.lineups.isEmpty) const Text('Noch keine Aufstellung hinterlegt'),
                            ...match.lineups.expand((lineup) => lineup.positions.map((pos) => Text(
                                  '${pos.isSubstitute ? 'Bank' : 'Feld'}: ${pos.playerId}',
                                ))),
                            const SizedBox(height: 6),
                            Text('Tore: ${match.goals.length}'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

final _matchesProvider = FutureProvider.autoDispose.family<List<MatchModel>, dynamic>((ref, _) async {
  final repo = ref.watch(repositoryProvider);
  return repo.matches();
});

final _meProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.me();
});
