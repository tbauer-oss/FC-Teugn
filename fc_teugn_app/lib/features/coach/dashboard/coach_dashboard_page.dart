import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';

class CoachDashboardPage extends ConsumerWidget {
  const CoachDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final players = ref.watch(FutureProvider((ref) => repo.players()));
    final matches = ref.watch(FutureProvider((ref) => repo.matches()));
    final trainings = ref.watch(FutureProvider((ref) => repo.trainings()));
    final events = ref.watch(FutureProvider((ref) => repo.events()));

    return Scaffold(
      appBar: AppBar(title: const Text('Trainer Cockpit')),
      body: GridView.count(
        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
        padding: const EdgeInsets.all(12),
        children: [
          players.when(
            data: (data) => _StatCard(label: 'Kader', value: data.length.toString()),
            loading: () => const _StatCard(label: 'Kader', value: '…'),
            error: (e, _) => _StatCard(label: 'Kader', value: 'Fehler'),
          ),
          matches.when(
            data: (data) => _StatCard(label: 'Spiele', value: data.length.toString()),
            loading: () => const _StatCard(label: 'Spiele', value: '…'),
            error: (e, _) => _StatCard(label: 'Spiele', value: 'Fehler'),
          ),
          trainings.when(
            data: (data) => _StatCard(label: 'Trainings', value: data.length.toString()),
            loading: () => const _StatCard(label: 'Trainings', value: '…'),
            error: (e, _) => _StatCard(label: 'Trainings', value: 'Fehler'),
          ),
          events.when(
            data: (data) => _StatCard(label: 'Events', value: data.length.toString()),
            loading: () => const _StatCard(label: 'Events', value: '…'),
            error: (e, _) => _StatCard(label: 'Events', value: 'Fehler'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    );
  }
}
