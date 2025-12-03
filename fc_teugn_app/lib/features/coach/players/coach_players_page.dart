import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/player.dart';
import '../../../core/providers.dart';

class CoachPlayersPage extends ConsumerStatefulWidget {
  const CoachPlayersPage({super.key});

  @override
  ConsumerState<CoachPlayersPage> createState() => _CoachPlayersPageState();
}

class _CoachPlayersPageState extends ConsumerState<CoachPlayersPage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _team = TextEditingController(text: 'E2');
  final _position = TextEditingController();
  final _shirt = TextEditingController();
  DateTime _birthDate = DateTime(2014, 1, 1);

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(_playersProvider);
    final repo = ref.watch(repositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Spieler verwalten')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'Vorname')),
                ),
                SizedBox(
                  width: 150,
                  child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Nachname')),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _position,
                    decoration: const InputDecoration(labelText: 'Position'),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _shirt,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nr.'),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(controller: _team, decoration: const InputDecoration(labelText: 'Team')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await repo.createPlayer(
                      firstName: _first.text,
                      lastName: _last.text,
                      birthDate: _birthDate,
                      gender: 'n/a',
                      position: _position.text,
                      shirtNumber: int.tryParse(_shirt.text),
                      team: _team.text,
                    );
                    ref.refresh(_playersProvider);
                  },
                  child: const Text('Spieler anlegen'),
                ),
              ],
            ),
          ),
          Expanded(
            child: players.when(
              data: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final p = list[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text(p.firstName[0])),
                    title: Text(p.fullName),
                    subtitle: Text('Team ${p.team ?? ''}'),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

final _playersProvider = FutureProvider.autoDispose<List<PlayerModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.players();
});
