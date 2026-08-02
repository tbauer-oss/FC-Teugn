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
  int? _selectedSlotIndex;

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

  String? get _captainId {
    for (final slot in _slots) {
      if (slot.isCaptain && slot.player != null) return slot.player!.id;
    }
    return null;
  }

  List<_EditableSlot> _plannedSlots({
    Iterable<PlayerModel>? players,
    String? captainId,
  }) {
    final candidates = (players ?? widget.players).toList();
    final planned = planInitialLineup(
      players: candidates.map(_matchPlayer).toList(),
      fieldSize: widget.team.gameFormat.playerCount,
      formation: _formation,
      playerPriority: captainId == null ? const {} : {captainId: -10000},
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
        isCaptain: position.player.id == captainId,
      );
    }
    return slots;
  }

  void _applyFormation(String formation) {
    final starters =
        _slots.map((slot) => slot.player).whereType<PlayerModel>().toList();
    final captainId = _captainId;
    setState(() {
      _formation = formation;
      _slots = _plannedSlots(
        players: starters.isEmpty ? widget.players : starters,
        captainId: captainId,
      );
      _selectedSlotIndex = null;
    });
  }

  void _autoAssign() {
    final captainId = _captainId;
    final starters =
        _slots.map((slot) => slot.player).whereType<PlayerModel>().toList();
    setState(() {
      _slots = _plannedSlots(
        players: starters.isEmpty ? widget.players : starters,
        captainId: captainId,
      );
      _selectedSlotIndex = null;
    });
  }

  void _selectOrSwapSlot(int index) {
    final selectedIndex = _selectedSlotIndex;
    if (selectedIndex == null || selectedIndex == index) {
      setState(
          () => _selectedSlotIndex = selectedIndex == index ? null : index);
      return;
    }
    setState(() {
      final selected = _slots[selectedIndex];
      final target = _slots[index];
      _slots[selectedIndex] = selected.copyWith(
        player: target.player,
        clearPlayer: target.player == null,
        isCaptain: target.isCaptain,
      );
      _slots[index] = target.copyWith(
        player: selected.player,
        clearPlayer: selected.player == null,
        isCaptain: selected.isCaptain,
      );
      _selectedSlotIndex = index;
    });
  }

  void _assignPoolPlayer(PlayerModel player) {
    final index = _selectedSlotIndex;
    if (index == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst eine Position auf dem Spielfeld wählen.'),
        ),
      );
      return;
    }
    setState(() {
      _slots[index] = _slots[index].copyWith(player: player, isCaptain: false);
    });
  }

  void _clearSelectedSlot() {
    final index = _selectedSlotIndex;
    if (index == null) return;
    setState(() {
      _slots[index] = _slots[index].copyWith(
        clearPlayer: true,
        isCaptain: false,
      );
    });
  }

  void _changeSelectedPosition(String code) {
    final index = _selectedSlotIndex;
    if (index == null) return;
    setState(() {
      _slots[index] = _slots[index].copyWith(
        positionCode: code,
        isGoalkeeper: code == 'TW',
      );
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
          title: Text('${widget.team.displayName} · Team-Management'),
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
              final compact = constraints.maxWidth < 1000;
              final captain = _slots
                  .where((slot) => slot.isCaptain && slot.player != null)
                  .map((slot) => slot.player!)
                  .firstOrNull;
              final controls = _LineupControls(
                formation: _formation,
                formations: widget.team.gameFormat.formations,
                selectedCount: selectedCount,
                targetCount: targetCount,
                onFormationChanged: _applyFormation,
                onAutoAssign: _autoAssign,
              );
              final pitch = _FormationPitch(
                slots: _slots,
                selectedIndex: _selectedSlotIndex,
                onSelected: _selectOrSwapSlot,
                onMoved: (index, x, y) => setState(
                  () => _slots[index] = _slots[index].copyWith(x: x, y: y),
                ),
              );
              final manager = _TeamManagerPanel(
                slots: _slots,
                players: widget.players,
                selectedIndex: _selectedSlotIndex,
                compact: compact,
                onPoolPlayerSelected: _assignPoolPlayer,
                onPositionChanged: _changeSelectedPosition,
                onCaptain: () {
                  final index = _selectedSlotIndex;
                  if (index != null) _setCaptain(index);
                },
                onClear: _clearSelectedSlot,
              );

              if (compact) {
                return ListView(
                  key: const ValueKey('team-manager-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    controls,
                    const SizedBox(height: 12),
                    pitch,
                    const SizedBox(height: 12),
                    manager,
                  ],
                );
              }
              return Padding(
                key: const ValueKey('desktop-team-management'),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Container(
                        decoration: _desktopPanelDecoration(),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _DesktopTacticsHeader(
                              teamName: widget.team.displayName,
                              selectedCount: selectedCount,
                              targetCount: targetCount,
                              captainName: captain?.displayName,
                            ),
                            const SizedBox(height: 12),
                            controls,
                            const SizedBox(height: 14),
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE9EBE4),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.line),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Center(child: pitch),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const _DesktopPitchHint(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 4,
                      child: Container(
                        decoration: _desktopPanelDecoration(),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _DesktopManagerHeader(
                              selectedSlot: _selectedSlotIndex == null
                                  ? null
                                  : _slots[_selectedSlotIndex!],
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(18),
                                child: manager,
                              ),
                            ),
                          ],
                        ),
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

BoxDecoration _desktopPanelDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    );

class _DesktopTacticsHeader extends StatelessWidget {
  const _DesktopTacticsHeader({
    required this.teamName,
    required this.selectedCount,
    required this.targetCount,
    required this.captainName,
  });

  final String teamName;
  final int selectedCount;
  final int targetCount;
  final String? captainName;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(15),
            ),
            child:
                const Icon(Icons.sports_soccer_rounded, color: AppColors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TAKTIKBOARD · STANDARD-AUFSTELLUNG',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          _DesktopStatusBadge(
            icon: Icons.groups_rounded,
            label: '$selectedCount/$targetCount',
            hint: 'Startelf',
          ),
          const SizedBox(width: 8),
          _DesktopStatusBadge(
            icon: Icons.workspace_premium_rounded,
            label: captainName ?? 'Offen',
            hint: 'Kapitän',
          ),
        ],
      );
}

class _DesktopStatusBadge extends StatelessWidget {
  const _DesktopStatusBadge({
    required this.icon,
    required this.label,
    required this.hint,
  });

  final IconData icon;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 90, maxWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.gold),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    hint,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DesktopManagerHeader extends StatelessWidget {
  const _DesktopManagerHeader({required this.selectedSlot});

  final _EditableSlot? selectedSlot;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.black, Color(0xFF35321B)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.manage_accounts_rounded,
                color: AppColors.yellow, size: 28),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SPIELER & ROLLEN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selectedSlot == null
                        ? 'Position auf dem Feld auswählen'
                        : '${selectedSlot!.positionCode} · ${selectedSlot!.player?.displayName ?? 'noch offen'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DesktopPitchHint extends StatelessWidget {
  const _DesktopPitchHint();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_rounded, size: 17, color: AppColors.gold),
          SizedBox(width: 7),
          Flexible(
            child: Text(
              'Spieler auswählen, direkt tauschen oder frei auf dem Feld verschieben.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schema_rounded,
                    color: AppColors.yellow, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'FORMATION',
                    style: TextStyle(
                      color: AppColors.yellow,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                Text(
                  '$selectedCount/$targetCount Spieler',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final value in formations) ...[
                          ChoiceChip(
                            key: ValueKey('formation-$value'),
                            label: Text(value),
                            selected: value == formation,
                            onSelected: (_) => onFormationChanged(value),
                            selectedColor: AppColors.yellow,
                            backgroundColor: Colors.white12,
                            side: BorderSide(
                              color: value == formation
                                  ? AppColors.yellow
                                  : Colors.white24,
                            ),
                            labelStyle: TextStyle(
                              color: value == formation
                                  ? AppColors.black
                                  : Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Aktuelle Startelf positionsgerecht sortieren',
                  onPressed: onAutoAssign,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.yellow,
                    foregroundColor: AppColors.black,
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                ),
              ],
            ),
          ],
        ),
      );
}

class _FormationPitch extends StatelessWidget {
  const _FormationPitch({
    required this.slots,
    required this.selectedIndex,
    required this.onSelected,
    required this.onMoved,
  });

  final List<_EditableSlot> slots;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final void Function(int index, double x, double y) onMoved;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
      child: AspectRatio(
        aspectRatio: compact ? .84 : 1.35,
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
                  left: 0,
                  right: 0,
                  top: constraints.maxHeight / 2 - 1,
                  child: Container(height: 2, color: Colors.white54),
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
                _PenaltyArea(top: 0, width: constraints.maxWidth),
                _PenaltyArea(
                  bottom: 0,
                  width: constraints.maxWidth,
                ),
                for (var index = 0; index < slots.length; index++)
                  Positioned(
                    left: slots[index].x * constraints.maxWidth -
                        (compact ? 34 : 42),
                    top: slots[index].y * constraints.maxHeight -
                        (compact ? 25 : 27),
                    child: GestureDetector(
                      onTap: () => onSelected(index),
                      onPanUpdate: (details) {
                        final x = (slots[index].x +
                                details.delta.dx / constraints.maxWidth)
                            .clamp(.07, .93);
                        final y = (slots[index].y +
                                details.delta.dy / constraints.maxHeight)
                            .clamp(.07, .93);
                        onMoved(index, x, y);
                      },
                      child: _PitchMarker(
                        key: ValueKey(
                          'slot-marker-$index-${slots[index].positionCode}',
                        ),
                        slot: slots[index],
                        selected: selectedIndex == index,
                        compact: compact,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PenaltyArea extends StatelessWidget {
  const _PenaltyArea({this.top, this.bottom, required this.width});

  final double? top;
  final double? bottom;
  final double width;

  @override
  Widget build(BuildContext context) => Positioned(
        top: top,
        bottom: bottom,
        left: width * .25,
        width: width * .5,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white54, width: 2),
          ),
        ),
      );
}

class _PitchMarker extends StatelessWidget {
  const _PitchMarker({
    super.key,
    required this.slot,
    required this.selected,
    required this.compact,
  });

  final _EditableSlot slot;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fit = slot.player == null
        ? 1000
        : lineupFitScore(
            slot.player!.position,
            slot.player!.secondaryPosition,
            slot.positionCode,
          );
    final outOfPosition = slot.player != null && fit <= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: compact ? 68 : 84,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: slot.isGoalkeeper ? AppColors.yellow : Colors.white,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(
          color: selected
              ? AppColors.yellow
              : outOfPosition
                  ? Colors.orange
                  : Colors.transparent,
          width: selected ? 3 : 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (outOfPosition)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(Icons.warning_amber_rounded,
                      size: 11, color: Colors.orange),
                ),
              Flexible(
                child: Text(
                  '${slot.positionCode}${slot.isCaptain ? ' · C' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 9 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          Text(
            slot.player?.displayName ?? 'Offen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 9 : 11),
          ),
        ],
      ),
    );
  }
}

class _TeamManagerPanel extends StatelessWidget {
  const _TeamManagerPanel({
    required this.slots,
    required this.players,
    required this.selectedIndex,
    required this.compact,
    required this.onPoolPlayerSelected,
    required this.onPositionChanged,
    required this.onCaptain,
    required this.onClear,
  });

  final List<_EditableSlot> slots;
  final List<PlayerModel> players;
  final int? selectedIndex;
  final bool compact;
  final ValueChanged<PlayerModel> onPoolPlayerSelected;
  final ValueChanged<String> onPositionChanged;
  final VoidCallback onCaptain;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selectedPlayerIds = {
      for (final slot in slots)
        if (slot.player != null) slot.player!.id,
    };
    final pool = players
        .where((player) => !selectedPlayerIds.contains(player.id))
        .toList()
      ..sort((a, b) {
        final position = (a.position ?? '').compareTo(b.position ?? '');
        if (position != 0) return position;
        return a.fullName.compareTo(b.fullName);
      });
    final selected = selectedIndex == null ? null : slots[selectedIndex!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelectedSlotPanel(
          slot: selected,
          onPositionChanged: onPositionChanged,
          onCaptain: onCaptain,
          onClear: onClear,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Spielerpool',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${pool.length} verfügbar',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          selected == null
              ? 'Position auf dem Feld wählen, danach einen Spieler einsetzen.'
              : 'Spieler antippen, um ${selected.positionCode} neu zu besetzen.',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        if (pool.isEmpty)
          const _EmptyPlayerPool()
        else if (compact)
          SizedBox(
            height: 122,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pool.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _PlayerPoolCard(
                player: pool[index],
                onTap: () => onPoolPlayerSelected(pool[index]),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final player in pool)
                _PlayerPoolCard(
                  player: player,
                  onTap: () => onPoolPlayerSelected(player),
                ),
            ],
          ),
        const SizedBox(height: 12),
        const _ManagerHint(),
      ],
    );
  }
}

class _SelectedSlotPanel extends StatelessWidget {
  const _SelectedSlotPanel({
    required this.slot,
    required this.onPositionChanged,
    required this.onCaptain,
    required this.onClear,
  });

  final _EditableSlot? slot;
  final ValueChanged<String> onPositionChanged;
  final VoidCallback onCaptain;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (slot == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.yellow.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.yellow.withValues(alpha: .5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app_rounded, color: AppColors.blue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Spieler auf dem Feld antippen. Zweiten Feldspieler antippen, '
                'um beide direkt zu tauschen.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final player = slot!.player;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.yellow, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PlayerAvatar(player: player),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player?.fullName ?? 'Position offen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      player == null
                          ? 'Jetzt aus dem Spielerpool besetzen'
                          : '#${player.shirtNumber ?? '–'} · '
                              '${player.position ?? 'FLEX'}'
                              '${player.secondaryPosition == null ? '' : ' / ${player.secondaryPosition}'}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: slot!.isCaptain
                    ? 'Ist Mannschaftskapitän'
                    : 'Als Kapitän festlegen',
                onPressed: player == null ? null : onCaptain,
                icon: Text(
                  'C',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: slot!.isCaptain ? AppColors.black : AppColors.muted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Aus Startelf entfernen',
                onPressed: player == null ? null : onClear,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('selected-position-${slot!.positionCode}'),
            initialValue: slot!.positionCode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Position in dieser Formation',
              isDense: true,
              prefixIcon: Icon(Icons.place_rounded),
            ),
            items: lineupPositionCodes
                .map(
                  (code) => DropdownMenuItem(
                    value: code,
                    child: Text(code),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onPositionChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

class _PlayerPoolCard extends StatelessWidget {
  const _PlayerPoolCard({required this.player, required this.onTap});

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 104,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PlayerAvatar(player: player, small: true),
                  const SizedBox(height: 6),
                  Text(
                    player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '#${player.shirtNumber ?? '–'} · ${player.position ?? 'FLEX'}',
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.player, this.small = false});

  final PlayerModel? player;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final initials = player == null
        ? '?'
        : '${player!.firstName.isEmpty ? '' : player!.firstName[0]}'
            '${player!.lastName.isEmpty ? '' : player!.lastName[0]}';
    return CircleAvatar(
      radius: small ? 20 : 23,
      backgroundColor: AppColors.yellow.withValues(alpha: .25),
      foregroundColor: AppColors.black,
      child: Text(
        initials.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _EmptyPlayerPool extends StatelessWidget {
  const _EmptyPlayerPool();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: const Text(
          'Alle verfügbaren Spieler stehen bereits in der Startelf.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      );
}

class _ManagerHint extends StatelessWidget {
  const _ManagerHint();

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Formationswechsel sortieren die aktuelle Startelf automatisch '
              'positionsgerecht neu. Orange markierte Spieler stehen auf einer '
              'unpassenden Position. Verschieben bleibt jederzeit möglich.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
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
