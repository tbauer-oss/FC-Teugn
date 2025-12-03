import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/event.dart';
import '../../../core/providers.dart';

class ParentEventsPage extends ConsumerWidget {
  const ParentEventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(_eventsProvider);
    final me = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Events & Feiern')),
      body: events.when(
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final event = list[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: Theme.of(context).textTheme.titleMedium),
                    Text('${_formatDate(event.date)} • ${event.location}'),
                    if (event.description != null) Text(event.description!),
                    const SizedBox(height: 8),
                    if (event.rsvpEnabled)
                      me.when(
                        data: (details) => Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () async {
                                await ref.read(repositoryProvider).setEventRsvp(event.id, details.user.id, RSVPStatus.yes);
                                ref.refresh(_eventsProvider);
                              },
                              child: const Text('Zusage'),
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                await ref.read(repositoryProvider).setEventRsvp(event.id, details.user.id, RSVPStatus.no);
                                ref.refresh(_eventsProvider);
                              },
                              child: const Text('Absage'),
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                await ref.read(repositoryProvider).setEventRsvp(event.id, details.user.id, RSVPStatus.maybe);
                                ref.refresh(_eventsProvider);
                              },
                              child: const Text('Offen'),
                            ),
                          ],
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (e, _) => Text('Fehler: $e'),
                      ),
                  ],
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

final _eventsProvider = FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.events();
});

final _meProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.me();
});
