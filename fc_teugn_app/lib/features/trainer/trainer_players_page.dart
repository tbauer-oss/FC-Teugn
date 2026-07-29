import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/football_options.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class TrainerPlayersPage extends ConsumerWidget {
  const TrainerPlayersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider);

    return PageScaffold(
      title: 'Mannschaft',
      subtitle:
          'Spielerprofile, Entwicklung, Kontakte und Einwilligungen sicher verwalten.',
      action: FilledButton.icon(
        onPressed: () => _createPlayer(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Spieler anlegen'),
      ),
      child: players.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Mannschaft nicht erreichbar',
          message: 'Die Spielerdaten konnten nicht geladen werden.',
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(playersProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut laden'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.groups_rounded,
              title: 'Noch keine Spieler angelegt',
              message:
                  'Lege das erste Spielerprofil mit Stammdaten und Mannschaftszuordnung an.',
              action: FilledButton.icon(
                onPressed: () => _createPlayer(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Erstes Profil anlegen'),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980
                  ? 3
                  : constraints.maxWidth >= 620
                      ? 2
                      : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns == 1 ? 2.9 : 2.15,
                ),
                itemBuilder: (context, index) => _PlayerCard(
                  player: items[index],
                  onTap: () =>
                      context.go('/trainer/players/${items[index].id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createPlayer(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_PlayerDraft>(
      context: context,
      builder: (context) => const _CreatePlayerDialog(),
    );
    if (draft == null) return;
    try {
      final player = await ref.read(repositoryProvider).createPlayer(
            firstName: draft.firstName,
            lastName: draft.lastName,
            preferredName: draft.preferredName,
            birthDate: draft.birthDate,
            nationality: draft.nationality,
            position: draft.position,
            secondaryPosition: draft.secondaryPosition,
            dominantFoot: draft.dominantFoot,
            shirtNumber: draft.shirtNumber,
            joinedAt: draft.joinedAt,
          );
      ref.invalidate(playersProvider);
      if (context.mounted) {
        context.go('/trainer/players/${player.id}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Spielerprofil konnte nicht angelegt werden.'),
          ),
        );
      }
    }
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player, required this.onTap});

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(player.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.blue.withValues(alpha: .1),
                child: Text(
                  '${player.firstName[0]}${player.lastName[0]}'.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            player.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (player.shirtNumber != null)
                          Text(
                            '#${player.shirtNumber}',
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (player.position?.isNotEmpty == true)
                          player.position!,
                        if (player.age != null) '${player.age} Jahre',
                      ].join(' · ').isEmpty
                          ? 'Profil vervollständigen'
                          : [
                              if (player.position?.isNotEmpty == true)
                                player.position!,
                              if (player.age != null) '${player.age} Jahre',
                            ].join(' · '),
                    ),
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: status.$2.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.$1,
                        style: TextStyle(
                          color: status.$2,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _statusStyle(PlayerStatus status) => switch (status) {
        PlayerStatus.active => ('Aktiv', AppColors.teal),
        PlayerStatus.injured => ('Verletzt', Colors.redAccent),
        PlayerStatus.paused => ('Pausiert', AppColors.orange),
        PlayerStatus.left => ('Ausgetreten', AppColors.muted),
      };
}

class _CreatePlayerDialog extends StatefulWidget {
  const _CreatePlayerDialog();

  @override
  State<_CreatePlayerDialog> createState() => _CreatePlayerDialogState();
}

class _CreatePlayerDialogState extends State<_CreatePlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _preferredName = TextEditingController();
  final _nationality = TextEditingController();
  final _shirtNumber = TextEditingController();
  DateTime? _birthDate;
  DateTime? _joinedAt;
  String? _position;
  String? _secondaryPosition;
  DominantFoot _dominantFoot = DominantFoot.unknown;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _preferredName.dispose();
    _nationality.dispose();
    _shirtNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spielerprofil anlegen'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstName,
                        decoration:
                            const InputDecoration(labelText: 'Vorname *'),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastName,
                        decoration:
                            const InputDecoration(labelText: 'Nachname *'),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _preferredName,
                        decoration:
                            const InputDecoration(labelText: 'Rufname'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _nationality,
                        decoration:
                            const InputDecoration(labelText: 'Nationalität'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Geburtsdatum',
                        value: _birthDate,
                        onChanged: (value) =>
                            setState(() => _birthDate = value),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Im Verein seit',
                        value: _joinedAt,
                        onChanged: (value) =>
                            setState(() => _joinedAt = value),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _position,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Hauptposition',
                        ),
                        items: footballOptionItems(
                          options: footballPositions,
                          emptyLabel: 'Noch offen',
                          showCode: true,
                        ),
                        onChanged: (value) =>
                            setState(() => _position = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _secondaryPosition,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Nebenposition',
                        ),
                        items: footballOptionItems(
                          options: footballPositions,
                          emptyLabel: 'Keine Nebenposition',
                          showCode: true,
                        ),
                        onChanged: (value) =>
                            setState(() => _secondaryPosition = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<DominantFoot>(
                        initialValue: _dominantFoot,
                        decoration:
                            const InputDecoration(labelText: 'Starker Fuß'),
                        items: const [
                          DropdownMenuItem(
                            value: DominantFoot.unknown,
                            child: Text('Noch offen'),
                          ),
                          DropdownMenuItem(
                            value: DominantFoot.right,
                            child: Text('Rechts'),
                          ),
                          DropdownMenuItem(
                            value: DominantFoot.left,
                            child: Text('Links'),
                          ),
                          DropdownMenuItem(
                            value: DominantFoot.both,
                            child: Text('Beidfüßig'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _dominantFoot =
                              value ?? DominantFoot.unknown,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _shirtNumber,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Trikotnummer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PlayerDraft(
                firstName: _firstName.text.trim(),
                lastName: _lastName.text.trim(),
                preferredName: _optional(_preferredName),
                nationality: _optional(_nationality),
                position: _position,
                secondaryPosition: _secondaryPosition,
                dominantFoot: _dominantFoot,
                shirtNumber: int.tryParse(_shirtNumber.text),
                birthDate: _birthDate,
                joinedAt: _joinedAt,
              ),
            );
          },
          child: const Text('Profil anlegen'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;

  String? _optional(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          firstDate: firstDate,
          lastDate: lastDate,
          initialDate: value ?? lastDate,
        );
        if (selected != null) onChanged(selected);
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value == null
              ? 'Auswählen'
              : '${value!.day.toString().padLeft(2, '0')}.${value!.month.toString().padLeft(2, '0')}.${value!.year}',
        ),
      ),
    );
  }
}

class _PlayerDraft {
  const _PlayerDraft({
    required this.firstName,
    required this.lastName,
    required this.dominantFoot,
    this.preferredName,
    this.nationality,
    this.birthDate,
    this.position,
    this.secondaryPosition,
    this.shirtNumber,
    this.joinedAt,
  });

  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? nationality;
  final DateTime? birthDate;
  final String? position;
  final String? secondaryPosition;
  final DominantFoot dominantFoot;
  final int? shirtNumber;
  final DateTime? joinedAt;
}
