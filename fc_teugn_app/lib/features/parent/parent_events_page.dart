import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/event.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';

class ParentEventsPage extends ConsumerWidget {
  const ParentEventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final players = ref.watch(playersProvider);
    final repository = ref.watch(repositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Events', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Expanded(
            child: events.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('Keine Events vorhanden.'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final event = items[index];
                    return ListTile(
                      title: Text(event.title),
                      subtitle: Text('${_typeLabel(event.type)} • ${event.location}'),
                      trailing: TextButton(
                        onPressed: () async {
                          final playerList = players.value ?? [];
                          if (playerList.isEmpty) return;
                          final selection = await _openAttendanceSheet(context, playerList);
                          if (selection != null) {
                            await repository.setAttendance(
                              eventId: event.id,
                              playerId: selection.player.id,
                              status: selection.status,
                            );
                            ref.invalidate(eventsProvider);
                          }
                        },
                        child: const Text('Teilnahme setzen'),
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

  Future<_AttendanceSelection?> _openAttendanceSheet(
    BuildContext context,
    List<PlayerModel> players,
  ) async {
    PlayerModel? selectedPlayer = players.first;
    AttendanceStatus status = AttendanceStatus.unknown;

    return showModalBottomSheet<_AttendanceSelection>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PlayerModel>(
                value: selectedPlayer,
                items: [
                  for (final player in players)
                    DropdownMenuItem(
                      value: player,
                      child: Text(player.fullName),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) selectedPlayer = value;
                },
                decoration: const InputDecoration(labelText: 'Spieler'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AttendanceStatus>(
                value: status,
                items: const [
                  DropdownMenuItem(value: AttendanceStatus.yes, child: Text('Ja')),
                  DropdownMenuItem(value: AttendanceStatus.no, child: Text('Nein')),
                  DropdownMenuItem(value: AttendanceStatus.maybe, child: Text('Vielleicht')),
                  DropdownMenuItem(value: AttendanceStatus.unknown, child: Text('Unbekannt')),
                ],
                onChanged: (value) {
                  if (value != null) status = value;
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (selectedPlayer != null) {
                        Navigator.of(context).pop(
                          _AttendanceSelection(player: selectedPlayer!, status: status),
                        );
                      }
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttendanceSelection {
  final PlayerModel player;
  final AttendanceStatus status;

  _AttendanceSelection({required this.player, required this.status});
}
