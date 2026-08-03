import 'models/matchday.dart';

const lineupPositionCodes = <String>[
  'TW',
  'LV',
  'IV',
  'RV',
  'DM',
  'ZM',
  'LM',
  'RM',
  'OM',
  'LA',
  'RA',
  'ST',
  'MF',
  'FLEX',
];

List<LineupPositionModel> planInitialLineup({
  required List<MatchPlayer> players,
  required int fieldSize,
  String? formation,
  Map<String, int> playerPriority = const {},
}) {
  final available = players.toList();
  final slots = lineupSlots(fieldSize, formation: formation);
  final assigned = List<MatchPlayer?>.filled(slots.length, null);
  final planned = <LineupPositionModel>[];

  void reserveExact(bool secondary) {
    for (var index = 0; index < slots.length; index++) {
      if (assigned[index] != null) continue;
      final slotCode = slots[index].$3;
      final candidates = available.where((player) {
        final raw = secondary ? player.secondaryPosition : player.position;
        return raw?.trim().toUpperCase() == slotCode;
      }).toList()
        ..sort((a, b) {
          int alternateOpportunity(MatchPlayer player) {
            final alternate = secondary
                ? player.position?.trim().toUpperCase()
                : player.secondaryPosition?.trim().toUpperCase();
            if (alternate == null || alternate.isEmpty) return 0;
            return List.generate(slots.length, (slotIndex) => slotIndex)
                .where(
                  (slotIndex) =>
                      slotIndex != index &&
                      assigned[slotIndex] == null &&
                      slots[slotIndex].$3 == alternate,
                )
                .length;
          }

          final opportunity = alternateOpportunity(a).compareTo(
            alternateOpportunity(b),
          );
          return opportunity != 0
              ? opportunity
              : _stablePlayerOrder(a, b, playerPriority);
        });
      if (candidates.isEmpty) continue;
      assigned[index] = candidates.first;
      available.remove(candidates.first);
    }
  }

  // Reserve exact position matches globally before compatible replacements
  // are assigned. An available striker must not be consumed by an earlier
  // unmatched goalkeeper or midfield slot.
  reserveExact(false);
  reserveExact(true);

  for (var index = 0; index < slots.length; index++) {
    final slot = slots[index];
    var player = assigned[index];
    if (player == null) {
      if (available.isEmpty) continue;
      available.sort((a, b) {
        final fit = lineupFitScore(
          b.position,
          b.secondaryPosition,
          slot.$3,
        ).compareTo(
          lineupFitScore(a.position, a.secondaryPosition, slot.$3),
        );
        return fit != 0 ? fit : _stablePlayerOrder(a, b, playerPriority);
      });
      player = available.removeAt(0);
    }
    planned.add(
      LineupPositionModel(
        player: player,
        positionCode: slot.$3,
        x: slot.$1,
        y: slot.$2,
        period: 1,
        isStarter: true,
        isGoalkeeper: slot.$3 == 'TW',
        isCaptain: false,
      ),
    );
  }
  return planned;
}

int _stablePlayerOrder(
  MatchPlayer a,
  MatchPlayer b,
  Map<String, int> playerPriority,
) {
  final priorityOrder = (playerPriority[a.id] ?? 0).compareTo(
    playerPriority[b.id] ?? 0,
  );
  if (priorityOrder != 0) return priorityOrder;
  final shirtOrder = (a.shirtNumber ?? 999).compareTo(b.shirtNumber ?? 999);
  return shirtOrder != 0 ? shirtOrder : a.name.compareTo(b.name);
}

int lineupFitScore(
  String? rawPlayerPosition,
  String? rawSecondaryPosition,
  String slot,
) {
  final position = rawPlayerPosition?.trim().toUpperCase() ?? '';
  final secondary = rawSecondaryPosition?.trim().toUpperCase() ?? '';
  if (position == slot) return 1000;
  if (secondary == slot) return 850;
  if (slot == 'TW') {
    return position == 'TW' || secondary == 'TW' ? 1000 : -500;
  }
  if (position == 'TW') return -1000;

  const compatible = <String, Set<String>>{
    'LV': {'IV', 'LA'},
    'IV': {'LV', 'RV', 'DM'},
    'RV': {'IV', 'RA'},
    'DM': {'IV', 'ZM', 'MF'},
    'ZM': {'DM', 'OM', 'LM', 'RM', 'MF'},
    'LM': {'LA', 'ZM', 'MF'},
    'RM': {'RA', 'ZM', 'MF'},
    'OM': {'ZM', 'ST', 'LA', 'RA', 'MF'},
    'LA': {'LM', 'ST', 'OM'},
    'RA': {'RM', 'ST', 'OM'},
    'ST': {'LA', 'RA', 'OM'},
    'MF': {'DM', 'ZM', 'LM', 'RM', 'OM'},
  };
  if (compatible[slot]?.contains(position) == true) return 500;
  if (compatible[slot]?.contains(secondary) == true) return 400;
  return 0;
}

List<(double, double, String)> lineupSlots(
  int fieldSize, {
  String? formation,
}) {
  final formationSlots = _formationSlots(fieldSize, formation);
  if (formationSlots != null) return formationSlots;
  return switch (fieldSize) {
    3 => const [
        (.5, .88, 'TW'),
        (.25, .42, 'MF'),
        (.75, .42, 'MF'),
      ],
    4 => const [
        (.5, .9, 'TW'),
        (.25, .58, 'LV'),
        (.75, .58, 'RV'),
        (.5, .2, 'ST'),
      ],
    5 => const [
        (.5, .9, 'TW'),
        (.25, .65, 'LV'),
        (.75, .65, 'RV'),
        (.5, .42, 'ZM'),
        (.5, .16, 'ST'),
      ],
    9 => const [
        (.5, .92, 'TW'),
        (.2, .72, 'LV'),
        (.5, .76, 'IV'),
        (.8, .72, 'RV'),
        (.18, .45, 'LM'),
        (.5, .5, 'ZM'),
        (.82, .45, 'RM'),
        (.36, .18, 'ST'),
        (.64, .18, 'ST'),
      ],
    11 => const [
        (.5, .93, 'TW'),
        (.12, .72, 'LV'),
        (.38, .77, 'IV'),
        (.62, .77, 'IV'),
        (.88, .72, 'RV'),
        (.16, .43, 'LM'),
        (.4, .5, 'ZM'),
        (.6, .5, 'ZM'),
        (.84, .43, 'RM'),
        (.36, .16, 'ST'),
        (.64, .16, 'ST'),
      ],
    _ => const [
        (.5, .9, 'TW'),
        (.3, .7, 'LV'),
        (.7, .7, 'RV'),
        (.2, .45, 'LM'),
        (.5, .5, 'ZM'),
        (.8, .45, 'RM'),
        (.5, .18, 'ST'),
      ],
  };
}

List<(double, double, String)>? _formationSlots(
  int fieldSize,
  String? formation,
) {
  final rows = formationRows(formation, fieldSize);
  if (rows == null) return null;
  final result = <(double, double, String)>[(.5, .92, 'TW')];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final count = rows[rowIndex];
    final progress = rows.length == 1 ? .5 : rowIndex / (rows.length - 1);
    final y = .72 - (.54 * progress);
    final codes = _positionCodesForRow(count, rowIndex, rows.length);
    for (var index = 0; index < count; index++) {
      final x = count == 1 ? .5 : .14 + (.72 * index / (count - 1));
      result.add((x, y, codes[index]));
    }
  }
  return result;
}

/// Parses a tactical formation such as `2-3-1` for the requested team size.
/// Zero rows remain valid for the existing mini-football presets (`2-0`).
List<int>? formationRows(String? formation, int fieldSize) {
  final value = formation?.trim() ?? '';
  if (!RegExp(r'^\d+(?:-\d+)+$').hasMatch(value)) return null;
  final rawRows = value.split('-').map(int.parse).toList();
  if (rawRows.every((count) => count == 0) ||
      rawRows.any((count) => count < 0 || count > 6) ||
      rawRows.fold<int>(0, (sum, count) => sum + count) != fieldSize - 1) {
    return null;
  }
  return rawRows.where((count) => count > 0).toList();
}

bool isValidFormation(String? formation, int fieldSize) =>
    formationRows(formation, fieldSize) != null;

List<String> _positionCodesForRow(int count, int row, int rowCount) {
  final isDefence = row == 0;
  final isAttack = row == rowCount - 1 && rowCount > 1;
  if (isDefence) {
    return switch (count) {
      1 => const ['IV'],
      2 => const ['LV', 'RV'],
      3 => const ['LV', 'IV', 'RV'],
      4 => const ['LV', 'IV', 'IV', 'RV'],
      _ => List.filled(count, 'IV'),
    };
  }
  if (isAttack) {
    return switch (count) {
      1 => const ['ST'],
      2 => const ['ST', 'ST'],
      3 => const ['LA', 'ST', 'RA'],
      _ => List.filled(count, 'ST'),
    };
  }
  return switch (count) {
    1 => const ['ZM'],
    2 => const ['LM', 'RM'],
    3 => const ['LM', 'ZM', 'RM'],
    4 => const ['LM', 'ZM', 'ZM', 'RM'],
    5 => const ['LM', 'DM', 'ZM', 'OM', 'RM'],
    _ => List.filled(count, 'MF'),
  };
}
