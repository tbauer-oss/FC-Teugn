import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/event.dart';
import '../../../core/providers.dart';

class CoachEventsPage extends ConsumerStatefulWidget {
  const CoachEventsPage({super.key});

  @override
  ConsumerState<CoachEventsPage> createState() => _CoachEventsPageState();
}

class _CoachEventsPageState extends ConsumerState<CoachEventsPage> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(_eventsProvider);
    final repo = ref.watch(repositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Events verwalten')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(width: 150, child: TextField(controller: _title, decoration: const InputDecoration(labelText: 'Titel'))),
                SizedBox(width: 150, child: TextField(controller: _location, decoration: const InputDecoration(labelText: 'Ort'))),
                SizedBox(width: 220, child: TextField(controller: _description, decoration: const InputDecoration(labelText: 'Beschreibung'))),
                ElevatedButton(
                  onPressed: () async {
                    await repo.createEvent(
                      title: _title.text,
                      date: _date,
                      location: _location.text,
                      description: _description.text,
                    );
                    ref.refresh(_eventsProvider);
                  },
                  child: const Text('Event anlegen'),
                ),
              ],
            ),
          ),
          Expanded(
            child: events.when(
              data: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final e = list[i];
                  return ListTile(
                    title: Text(e.title),
                    subtitle: Text('${_formatDate(e.date)} • ${e.location}'),
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

final _eventsProvider = FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.events();
});
