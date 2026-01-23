import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';

class TrainerPlayersPage extends ConsumerWidget {
  const TrainerPlayersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider);
    final repository = ref.watch(repositoryProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Spieler',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await _openCreateDialog(context);
                    if (created != null) {
                      await repository.createPlayer(
                        firstName: created.firstName,
                        lastName: created.lastName,
                        birthDate: created.birthDate,
                        position: created.position,
                        shirtNumber: created.shirtNumber,
                      );
                      ref.invalidate(playersProvider);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: players.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('Noch keine Spieler angelegt.'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final player = items[index];
                      return ListTile(
                        title: Text(player.fullName),
                        subtitle: Text(_subtitle(player)),
                        trailing: Text(player.shirtNumber != null ? '#${player.shirtNumber}' : ''),
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

  String _subtitle(PlayerModel player) {
    final buffer = StringBuffer();
    if (player.position != null && player.position!.isNotEmpty) {
      buffer.write(player.position);
    }
    if (player.birthDate != null) {
      if (buffer.isNotEmpty) buffer.write(' • ');
      buffer.write('${player.birthDate!.year}');
    }
    return buffer.isEmpty ? 'Keine Details' : buffer.toString();
  }

  Future<_PlayerDraft?> _openCreateDialog(BuildContext context) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final positionController = TextEditingController();
    final numberController = TextEditingController();
    DateTime? birthDate;

    final result = await showDialog<_PlayerDraft>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Spieler anlegen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(labelText: 'Vorname'),
                ),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(labelText: 'Nachname'),
                ),
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(labelText: 'Position'),
                ),
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Trikotnummer'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      birthDate == null
                          ? 'Geburtsjahr wählen'
                          : 'Jahr: ${birthDate!.year}',
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDate: DateTime(2015),
                        );
                        if (picked != null) {
                          birthDate = picked;
                        }
                      },
                      child: const Text('Datum'),
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
                if (firstNameController.text.trim().isEmpty ||
                    lastNameController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  _PlayerDraft(
                    firstName: firstNameController.text.trim(),
                    lastName: lastNameController.text.trim(),
                    position: positionController.text.trim().isEmpty
                        ? null
                        : positionController.text.trim(),
                    shirtNumber: int.tryParse(numberController.text.trim()),
                    birthDate: birthDate,
                  ),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    firstNameController.dispose();
    lastNameController.dispose();
    positionController.dispose();
    numberController.dispose();

    return result;
  }
}

class _PlayerDraft {
  final String firstName;
  final String lastName;
  final String? position;
  final int? shirtNumber;
  final DateTime? birthDate;

  _PlayerDraft({
    required this.firstName,
    required this.lastName,
    this.position,
    this.shirtNumber,
    this.birthDate,
  });
}
