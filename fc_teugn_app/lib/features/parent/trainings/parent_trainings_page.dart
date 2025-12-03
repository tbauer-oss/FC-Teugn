import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/training.dart';
import '../../../core/providers.dart';

class ParentTrainingsPage extends ConsumerWidget {
  const ParentTrainingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainings = ref.watch(_trainingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Training')),
      body: trainings.when(
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final t = list[i];
            return Card(
              child: ListTile(
                title: Text('${_formatDate(t.date)} • ${t.location}'),
                subtitle: Text(
                  'Start: ${_time(t.startTime)}' + (t.note != null ? '\n${t.note}' : ''),
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }
}

String _formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';
String _time(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

final _trainingsProvider = FutureProvider.autoDispose<List<Training>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.trainings();
});
