import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api_client.dart';
import '../../auth/auth_controller.dart';

class MatchLivePage extends ConsumerStatefulWidget {
  final String matchId;
  final List<Map<String, dynamic>> players;

  const MatchLivePage({
    super.key,
    required this.matchId,
    required this.players,
  });

  @override
  ConsumerState<MatchLivePage> createState() => _MatchLivePageState();
}

class _MatchLivePageState extends ConsumerState<MatchLivePage> {
  late ApiClient _client;
  Timer? _timer;
  int _remainingSeconds = 0;
  int _halfCount = 2;
  int _currentHalf = 1;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _client = auth.client;
  }

  void _startTimer() {
    if (_remainingSeconds <= 0) return;
    setState(() => _running = true);
    _timer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _timer = null;
        setState(() {
          _running = false;
          if (_currentHalf < _halfCount) {
            _currentHalf++;
          }
        });
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _timer = null;
    setState(() => _running = false);
  }

  void _resetTimer(int minutesPerHalf) {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _remainingSeconds = minutesPerHalf * 60;
      _currentHalf = 1;
      _running = false;
    });
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleGoal(String playerId) async {
    try {
      await _client.dio.post('/matches/${widget.matchId}/goals/toggle', data: {
        'playerId': playerId,
      });
      setState(() {
        final idx = widget.players.indexWhere((p) => p['id'] == playerId);
        if (idx != -1) {
          final current = widget.players[idx]['goals'] as int? ?? 0;
          widget.players[idx]['goals'] = current == 0 ? 1 : 0;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final minutesPerHalfController = TextEditingController(text: '25');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live-Spiel'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minutesPerHalfController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minuten pro Halbzeit',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _halfCount,
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 Halbzeiten')),
                    DropdownMenuItem(value: 3, child: Text('3 Halbzeiten')),
                    DropdownMenuItem(value: 4, child: Text('4 Halbzeiten')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _halfCount = value);
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final m = int.tryParse(minutesPerHalfController.text) ?? 25;
                    _resetTimer(m);
                  },
                  child: const Text('Zeit setzen'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Halbzeit: $_currentHalf / $_halfCount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _formatTime(_remainingSeconds),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: _running ? null : _startTimer,
                  child: const Text('Start'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _running ? _pauseTimer : null,
                  child: const Text('Pause'),
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 3.0,
                children: [
                  for (final p in widget.players)
                    Card(
                      child: InkWell(
                        onTap: () => _toggleGoal(p['id'] as String),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  p['name'] as String,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              CircleAvatar(
                                child: Text((p['goals'] ?? 0).toString()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
