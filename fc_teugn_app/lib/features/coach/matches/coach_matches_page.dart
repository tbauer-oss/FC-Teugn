import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/match.dart';
import '../../../core/models/player.dart';
import '../../../core/providers.dart';

class CoachMatchesPage extends ConsumerStatefulWidget {
  const CoachMatchesPage({super.key});

  @override
  ConsumerState<CoachMatchesPage> createState() => _CoachMatchesPageState();
}

class _CoachMatchesPageState extends ConsumerState<CoachMatchesPage> {
  final _opponent = TextEditingController();
  final _location = TextEditingController();
  MatchType _type = MatchType.league;
  bool _isHome = true;
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final matches = ref.watch(_matchesProvider);
    final players = ref.watch(_playersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Spiele & Live-Modus')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<MatchType>(
                value: _type,
                onChanged: (v) => setState(() => _type = v ?? MatchType.league),
                items: const [
                  DropdownMenuItem(value: MatchType.league, child: Text('Pflichtspiel')),
                  DropdownMenuItem(value: MatchType.friendly, child: Text('Freundschaft')),
                ],
              ),
              SizedBox(
                width: 140,
                child: TextField(controller: _opponent, decoration: const InputDecoration(labelText: 'Gegner')),
              ),
              SizedBox(
                width: 140,
                child: TextField(controller: _location, decoration: const InputDecoration(labelText: 'Ort')),
              ),
              SwitchListTile(
                value: _isHome,
                onChanged: (v) => setState(() => _isHome = v),
                title: const Text('Heim'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await repo.createMatch(
                    type: _type,
                    date: _date,
                    kickOff: _date.add(const Duration(hours: 15)),
                    location: _location.text,
                    opponent: _opponent.text,
                    isHome: _isHome,
                    competition: _type == MatchType.league ? 'Liga' : 'Test',
                  );
                  ref.refresh(_matchesProvider);
                },
                child: const Text('Spiel anlegen'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          matches.when(
            data: (list) => Column(
              children: list
                  .map(
                    (m) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${m.type == MatchType.league ? 'Pflichtspiel' : 'Test'} vs ${m.opponent}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('${m.location} • ${m.isHome ? 'Heim' : 'Auswärts'} • ${_formatDate(m.date)}'),
                            const SizedBox(height: 8),
                            players.when(
                              data: (plist) => Wrap(
                                spacing: 6,
                                children: plist
                                    .take(8)
                                    .map((p) => ElevatedButton(
                                          onPressed: () async {
                                            await repo.toggleGoal(matchId: m.id, playerId: p.id);
                                            ref.refresh(_matchesProvider);
                                          },
                                          child: Text('Tor ${p.firstName}'),
                                        ))
                                    .toList(),
                              ),
                              loading: () => const Text('Lade Spieler...'),
                              error: (e, _) => Text('Spieler Fehler: $e'),
                            ),
                            const SizedBox(height: 8),
                            Text('Tore gesamt: ${m.goals.length}'),
                            const SizedBox(height: 8),
                            if (players.hasValue)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.tonal(
                                  onPressed: () async {
                                    final plist = players.value ?? [];
                                    final positions = plist.take(6).toList().asMap().entries.map((entry) {
                                      final idx = entry.key;
                                      final player = entry.value;
                                      return {
                                        'playerId': player.id,
                                        'posX': 0.2 + idx * 0.1,
                                        'posY': 0.2 + (idx % 2) * 0.2,
                                      };
                                    }).toList();
                                    await repo.saveLineup(matchId: m.id, formation: '2-3-1', positions: positions);
                                    ref.refresh(_matchesProvider);
                                  },
                                  child: const Text('Standard-Aufstellung speichern'),
                                ),
                              ),
                            const SizedBox(height: 8),
                            _CoachTimer(),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler: $e'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

final _matchesProvider = FutureProvider.autoDispose<List<MatchModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.matches();
});

final _playersProvider = FutureProvider.autoDispose<List<PlayerModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.players();
});

class _CoachTimer extends StatefulWidget {
  @override
  State<_CoachTimer> createState() => _CoachTimerState();
}

class _CoachTimerState extends State<_CoachTimer> {
  Duration elapsed = Duration.zero;
  bool running = false;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker((delta) {
      if (running) {
        setState(() => elapsed += delta);
      }
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Spielzeit: ${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}'),
        IconButton(
          onPressed: () => setState(() => running = !running),
          icon: Icon(running ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          onPressed: () => setState(() => elapsed = Duration.zero),
          icon: const Icon(Icons.stop),
        ),
      ],
    );
  }
}

class Ticker {
  final void Function(Duration) onTick;
  late final Stopwatch _stopwatch;
  late final Duration _interval;
  bool _active = false;

  Ticker(this.onTick) {
    _stopwatch = Stopwatch();
    _interval = const Duration(milliseconds: 500);
  }

  void start() async {
    _active = true;
    _stopwatch.start();
    Duration lastElapsed = Duration.zero;
    while (_active) {
      await Future.delayed(_interval);
      final current = _stopwatch.elapsed;
      onTick(current - lastElapsed);
      lastElapsed = current;
    }
  }

  void dispose() {
    _active = false;
  }
}
