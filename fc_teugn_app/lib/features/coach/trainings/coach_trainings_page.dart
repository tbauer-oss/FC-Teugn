import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/training.dart';
import '../../../core/providers.dart';

class CoachTrainingsPage extends ConsumerStatefulWidget {
  const CoachTrainingsPage({super.key});

  @override
  ConsumerState<CoachTrainingsPage> createState() => _CoachTrainingsPageState();
}

class _CoachTrainingsPageState extends ConsumerState<CoachTrainingsPage> {
  final _location = TextEditingController(text: 'Sportplatz Teugn');
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  TimeOfDay _start = const TimeOfDay(hour: 17, minute: 0);

  @override
  Widget build(BuildContext context) {
    final trainings = ref.watch(_trainingsProvider);
    final repo = ref.watch(repositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trainingsplanung')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(width: 180, child: TextField(controller: _location, decoration: const InputDecoration(labelText: 'Ort'))),
                SizedBox(width: 200, child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'Hinweis'))),
                ElevatedButton(
                  onPressed: () async {
                    final startDate = DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);
                    await repo.createTraining(date: _date, start: startDate, end: startDate.add(const Duration(hours: 1)), location: _location.text, note: _note.text);
                    ref.refresh(_trainingsProvider);
                  },
                  child: const Text('Training anlegen'),
                ),
              ],
            ),
          ),
          Expanded(
            child: trainings.when(
              data: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final t = list[i];
                  return ListTile(
                    title: Text('${_formatDate(t.date)} • ${t.location}'),
                    subtitle: Text(t.note ?? ''),
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

String _formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

final _trainingsProvider = FutureProvider.autoDispose<List<Training>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.trainings();
});
