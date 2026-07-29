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
}) {
  final available = players.toList();
  final slots = lineupSlots(fieldSize);
  final planned = <LineupPositionModel>[];

  for (final slot in slots) {
    if (available.isEmpty) break;
    available.sort(
      (a, b) => _fitScore(b.position, slot.$3)
          .compareTo(_fitScore(a.position, slot.$3)),
    );
    final player = available.removeAt(0);
    planned.add(
      LineupPositionModel(
        player: player,
        positionCode: slot.$3,
        x: slot.$1,
        y: slot.$2,
        period: 1,
        isStarter: true,
        isGoalkeeper: slot.$3 == 'TW',
        isCaptain: planned.length == 1,
      ),
    );
  }
  return planned;
}

int _fitScore(String? rawPlayerPosition, String slot) {
  final position = rawPlayerPosition?.trim().toUpperCase() ?? '';
  if (position == slot) return 1000;
  if (slot == 'TW') return position == 'TW' ? 1000 : -500;
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
  return compatible[slot]?.contains(position) == true ? 500 : 0;
}

List<(double, double, String)> lineupSlots(int fieldSize) =>
    switch (fieldSize) {
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
