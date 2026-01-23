import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';

class TrainerEventsPage extends ConsumerWidget {
  const TrainerEventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final repository = ref.watch(repositoryProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Events', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () async {
                    final draft = await _openCreateDialog(context);
                    if (draft != null) {
                      await repository.createEvent(
                        type: draft.type,
                        title: draft.title,
                        startAt: draft.startAt,
                        endAt: draft.endAt,
                        location: draft.location,
                        description: draft.description,
                      );
                      ref.invalidate(eventsProvider);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: events.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('Noch keine Events angelegt.'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final event = items[index];
                      return ListTile(
                        title: Text(event.title),
                        subtitle: Text('${_typeLabel(event.type)} • ${event.location}'),
                        trailing: event.attendanceFinalized
                            ? const Chip(label: Text('Final'))
                            : TextButton(
                                onPressed: () async {
                                  await repository.finalizeAttendance(event.id);
                                  ref.invalidate(eventsProvider);
                                },
                                child: const Text('Attendance finalisieren'),
                              ),
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
      ),
    );
  }

  String _typeLabel(EventType type) {
    switch (type) {
      case EventType.match:
        return 'Spiel';
      case EventType.event:
        return 'Event';
      case EventType.training:
        return 'Training';
    }
  }

  Future<_EventDraft?> _openCreateDialog(BuildContext context) async {
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    EventType type = EventType.training;
    DateTime startAt = DateTime.now().add(const Duration(days: 1));
    DateTime? endAt;

    final result = await showDialog<_EventDraft>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Event anlegen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<EventType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Typ'),
                  items: const [
                    DropdownMenuItem(value: EventType.training, child: Text('Training')),
                    DropdownMenuItem(value: EventType.match, child: Text('Spiel')),
                    DropdownMenuItem(value: EventType.event, child: Text('Event')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      type = value;
                    }
                  },
                ),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Ort'),
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Start'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDate: startAt,
                        );
                        if (picked != null) {
                          startAt = picked;
                        }
                      },
                      child: const Text('Datum'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Ende'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDate: startAt,
                        );
                        if (picked != null) {
                          endAt = picked;
                        }
                      },
                      child: const Text('Optional'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty ||
                    locationController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  _EventDraft(
                    type: type,
                    title: titleController.text.trim(),
                    location: locationController.text.trim(),
                    description: descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim(),
                    startAt: startAt,
                    endAt: endAt,
                  ),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    locationController.dispose();
    descriptionController.dispose();

    return result;
  }
}

class _EventDraft {
  final EventType type;
  final String title;
  final String location;
  final String? description;
  final DateTime startAt;
  final DateTime? endAt;

  _EventDraft({
    required this.type,
    required this.title,
    required this.location,
    this.description,
    required this.startAt,
    this.endAt,
  });
}
