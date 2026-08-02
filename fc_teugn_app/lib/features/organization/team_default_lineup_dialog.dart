import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/lineup_planner.dart';
import '../../core/models/matchday.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';

class TeamDefaultLineupDraft {
  const TeamDefaultLineupDraft({
    required this.formation,
    required this.positions,
  });

  final String formation;
  final List<TeamDefaultLineupPositionInput> positions;
}

class TeamDefaultLineupDialog extends StatefulWidget {
  const TeamDefaultLineupDialog({
    super.key,
    required this.team,
    required this.players,
  });

  final TeamSummary team;
  final List<PlayerModel> players;

  @override
  State<TeamDefaultLineupDialog> createState() =>
      _TeamDefaultLineupDialogState();
}

class _TeamDefaultLineupDialogState extends State<TeamDefaultLineupDialog> {
  late String _formation;
  late List<_EditableSlot> _slots;

  @override
  void initState() {
    super.initState();
    _formation = widget.team.defaultLineup?.formation ??
        widget.team.gameFormat.defaultFormation;
    _slots = _initialSlots();
  }

  List<_EditableSlot> _initialSlots() {
    final saved = widget.team.defaultLineup?.positions ?? const [];
    if (saved.isNotEmpty) {
      final playersById = {
        for (final player in widget.players) player.id: player
      };
      final slots = _baseSlots();
      for (var index = 0;
          index < saved.length && index < slots.length;
          index++) {
        final position = saved[index];
        slots[index] = _EditableSlot(
          player: playersById[position.player.id],
          positionCode: position.positionCode,
          x: position.x,
          y: position.y,
          isGoalkeeper: position.isGoalkeeper,
          isCaptain: position.isCaptain,
        );
      }
      return slots;
    }
    return _plannedSlots();
  }

  List<_EditableSlot> _baseSlots() => lineupSlots(
        widget.team.gameFormat.playerCount,
        formation: _formation,
      )
          .map(
            (slot) => _EditableSlot(
              player: null,
              positionCode: slot.$3,
              x: slot.$1,
              y: slot.$2,
              isGoalkeeper: slot.$3 == 'TW',
              isCaptain: false,
            ),
          )
          .toList();

  MatchPlayer _matchPlayer(PlayerModel player) => MatchPlayer(
        id: player.id,
        name: player.fullName,
        shirtNumber: player.shirtNumber,
        position: player.position,
        secondaryPosition: player.secondaryPosition,
        status: player.status,
      );

  List<_EditableSlot> _plannedSlots() {
    final planned = planInitialLineup(
      players: widget.players.map(_matchPlayer).toList(),
      fieldSize: widget.team.gameFormat.playerCount,
      formation: _formation,
    );
    final playersById = {
      for (final player in widget.players) player.id: player
    };
    final slots = _baseSlots();
    for (var index = 0;
        index < planned.length && index < slots.length;
        index++) {
      final position = planned[index];
      slots[index] = _EditableSlot(
        player: playersById[position.player.id],
        positionCode: position.positionCode,
        x: position.x,
        y: position.y,
        isGoalkeeper: position.isGoalkeeper,
        isCaptain: position.isCaptain,
      );
    }
    return slots;
  }

  void _applyFormation(String formation) {
    setState(() {
      _formation = formation;
      _slots = _plannedSlots();
    });
  }

  void _setCaptain(int index) {
    setState(() {
      for (var slotIndex = 0; slotIndex < _slots.length; slotIndex++) {
        _slots[slotIndex] = _slots[slotIndex].copyWith(
          isCaptain: slotIndex == index && _slots[slotIndex].player != null,
        );
      }
    });
  }

  void _submit() {
    final selected = _slots.where((slot) => slot.player != null).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte mindestens einen Spieler aufstellen.')),
      );
      return;
    }
    Navigator.of(context).pop(
      TeamDefaultLineupDraft(
        formation: _formation,
        positions: selected
            .map(
              (slot) => TeamDefaultLineupPositionInput(
                playerId: slot.player!.id,
                positionCode: slot.positionCode,
                x: slot.x,
                y: slot.y,
                isGoalkeeper: slot.isGoalkeeper,
                isCaptain: slot.isCaptain,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _slots.where((slot) => slot.player != null).length;
    final targetCount = widget.team.gameFormat.playerCount;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.team.displayName} · Kapitän & Startelf'),
          leading: IconButton(
            tooltip: 'Schließen',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 850;
              final controls = _LineupControls(
                formation: _formation,
                formations: widget.team.gameFormat.formations,
                selectedCount: selectedCount,
                targetCount: targetCount,
                onFormationChanged: _applyFormation,
                onAutoAssign: () => setState(() => _slots = _plannedSlots()),
              );
              final pitch = _FormationPitch(
                slots: _slots,
                onMoved: (index, x, y) => setState(
                  () => _slots[index] = _slots[index].copyWith(x: x, y: y),
                ),
              );
              final editor = _SlotEditor(
                slots: _slots,
                players: widget.players,
                onPlayerChanged: (index, player) => setState(() {
                  _slots[index] = _slots[index].copyWith(
                    player: player,
                    clearPlayer: player == null,
                  );
                }),
                onPositionChanged: (index, code) => setState(() {
                  _slots[index] = _slots[index].copyWith(
                    positionCode: code,
                    isGoalkeeper: code == 'TW',
                  );
                }),
                onCaptain: _setCaptain,
              );

              if (compact) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    controls,
                    const SizedBox(height: 12),
                    pitch,
                    const SizedBox(height: 18),
                    editor,
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  children: [
                    controls,
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 6, child: Center(child: pitch)),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 5,
                            child: Card(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: editor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LineupControls extends StatelessWidget {
  const _LineupControls({
    required this.formation,
    required this.formations,
    required this.selectedCount,
    required this.targetCount,
    required this.onFormationChanged,
    required this.onAutoAssign,
  });

  final String formation;
  final List<String> formations;
  final int selectedCount;
  final int targetCount;
  final ValueChanged<String> onFormationChanged;
  final VoidCallback onAutoAssign;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: formation,
                  decoration: const InputDecoration(
                    labelText: 'Grundformation',
                    isDense: true,
                  ),
                  items: formations
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onFormationChanged(value);
                  },
                ),
              ),
              Chip(
                avatar: const Icon(Icons.groups_rounded, size: 18),
                label: Text('$selectedCount von $targetCount besetzt'),
              ),
              OutlinedButton.icon(
                onPressed: onAutoAssign,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Positionsgetreu besetzen'),
              ),
              const SizedBox(
                width: 360,
                child: Text(
                  'Diese Aufstellung wird bei neuen Spielen vorgeschlagen. '
                  'Fehlende Spieler werden automatisch möglichst positionsgetreu ersetzt.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      );
}

class _FormationPitch extends StatelessWidget {
  const _FormationPitch({required this.slots, required this.onMoved});

  final List<_EditableSlot> slots;
  final void Function(int index, double x, double y) onMoved;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: AspectRatio(
          aspectRatio: 1.35,
          child: LayoutBuilder(
            builder: (context, constraints) => DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF18874D),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white70, width: 2),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: constraints.maxWidth / 2 - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.white54),
                  ),
                  Center(
                    child: Container(
                      width: constraints.maxHeight * .28,
                      height: constraints.maxHeight * .28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 2),
                      ),
                    ),
                  ),
                  for (var index = 0; index < slots.length; index++)
                    Positioned(
                      left: slots[index].x * constraints.maxWidth - 42,
                      top: slots[index].y * constraints.maxHeight - 26,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          final x = (slots[index].x +
                                  details.delta.dx / constraints.maxWidth)
                              .clamp(.07, .93);
                          final y = (slots[index].y +
                                  details.delta.dy / constraints.maxHeight)
                              .clamp(.07, .93);
                          onMoved(index, x, y);
                        },
                        child: _PitchMarker(slot: slots[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PitchMarker extends StatelessWidget {
  const _PitchMarker({required this.slot});

  final _EditableSlot slot;

  @override
  Widget build(BuildContext context) => Container(
        width: 84,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: slot.isGoalkeeper ? AppColors.yellow : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${slot.positionCode}${slot.isCaptain ? ' · C' : ''}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            Text(
              slot.player?.displayName ?? 'Offen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
}

class _SlotEditor extends StatelessWidget {
  const _SlotEditor({
    required this.slots,
    required this.players,
    required this.onPlayerChanged,
    required this.onPositionChanged,
    required this.onCaptain,
  });

  final List<_EditableSlot> slots;
  final List<PlayerModel> players;
  final void Function(int index, PlayerModel? player) onPlayerChanged;
  final void Function(int index, String positionCode) onPositionChanged;
  final ValueChanged<int> onCaptain;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Startspieler & Positionen',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Spieler und Rollen können jederzeit individuell angepasst werden. '
            'Markierungen auf dem Feld lassen sich verschieben.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < slots.length; index++) ...[
            _SlotRow(
              index: index,
              slot: slots[index],
              players: players,
              usedPlayerIds: {
                for (final item in slots)
                  if (item.player != null &&
                      item.player?.id != slots[index].player?.id)
                    item.player!.id,
              },
              onPlayerChanged: (player) => onPlayerChanged(index, player),
              onPositionChanged: (code) => onPositionChanged(index, code),
              onCaptain: () => onCaptain(index),
            ),
            if (index != slots.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.index,
    required this.slot,
    required this.players,
    required this.usedPlayerIds,
    required this.onPlayerChanged,
    required this.onPositionChanged,
    required this.onCaptain,
  });

  final int index;
  final _EditableSlot slot;
  final List<PlayerModel> players;
  final Set<String> usedPlayerIds;
  final ValueChanged<PlayerModel?> onPlayerChanged;
  final ValueChanged<String> onPositionChanged;
  final VoidCallback onCaptain;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final playerField = DropdownButtonFormField<PlayerModel?>(
              key: ValueKey('player-$index-${slot.player?.id}'),
              initialValue: slot.player,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '${index + 1}. Spieler',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<PlayerModel?>(
                  value: null,
                  child: Text('Position offen'),
                ),
                for (final player in players)
                  if (!usedPlayerIds.contains(player.id))
                    DropdownMenuItem<PlayerModel?>(
                      value: player,
                      child: Text(
                        '${player.shirtNumber != null ? '#${player.shirtNumber} · ' : ''}'
                        '${player.fullName} · ${player.position ?? 'FLEX'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: onPlayerChanged,
            );
            final positionField = DropdownButtonFormField<String>(
              initialValue: slot.positionCode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Position',
                isDense: true,
              ),
              items: lineupPositionCodes
                  .map(
                    (code) => DropdownMenuItem(value: code, child: Text(code)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onPositionChanged(value);
              },
            );
            final captain = IconButton.filledTonal(
              tooltip: slot.isCaptain ? 'Kapitän' : 'Als Kapitän festlegen',
              onPressed: slot.player == null ? null : onCaptain,
              icon: Text(
                'C',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: slot.isCaptain ? AppColors.black : AppColors.muted,
                ),
              ),
            );
            if (constraints.maxWidth < 450) {
              return Column(
                children: [
                  playerField,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: positionField),
                      const SizedBox(width: 8),
                      captain,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: playerField),
                const SizedBox(width: 8),
                Expanded(child: positionField),
                const SizedBox(width: 8),
                captain,
              ],
            );
          },
        ),
      );
}

class _EditableSlot {
  const _EditableSlot({
    required this.player,
    required this.positionCode,
    required this.x,
    required this.y,
    required this.isGoalkeeper,
    required this.isCaptain,
  });

  final PlayerModel? player;
  final String positionCode;
  final double x;
  final double y;
  final bool isGoalkeeper;
  final bool isCaptain;

  _EditableSlot copyWith({
    PlayerModel? player,
    bool clearPlayer = false,
    String? positionCode,
    double? x,
    double? y,
    bool? isGoalkeeper,
    bool? isCaptain,
  }) =>
      _EditableSlot(
        player: clearPlayer ? null : player ?? this.player,
        positionCode: positionCode ?? this.positionCode,
        x: x ?? this.x,
        y: y ?? this.y,
        isGoalkeeper: isGoalkeeper ?? this.isGoalkeeper,
        isCaptain: isCaptain ?? this.isCaptain,
      );
}
