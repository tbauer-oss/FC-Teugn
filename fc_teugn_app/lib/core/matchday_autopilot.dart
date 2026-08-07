import 'lineup_planner.dart';
import 'models/matchday.dart';
import 'models/player.dart';

enum AutopilotStrategy {
  balanced,
  playingTime,
  positionFidelity,
}

extension AutopilotStrategyPresentation on AutopilotStrategy {
  String get label => switch (this) {
        AutopilotStrategy.balanced => 'Ausgewogen',
        AutopilotStrategy.playingTime => 'Einsatzzeit',
        AutopilotStrategy.positionFidelity => 'Positionstreu',
      };

  String get description => switch (this) {
        AutopilotStrategy.balanced =>
          'Verbindet faire Spielzeit mit möglichst passenden Positionen.',
        AutopilotStrategy.playingTime =>
          'Bevorzugt Spieler mit wenig Saison- und Spielminuten.',
        AutopilotStrategy.positionFidelity =>
          'Hält Haupt-, Neben- und taktische Positionsgruppen besonders konsequent ein.',
      };
}

class AutopilotReadinessItem {
  const AutopilotReadinessItem({
    required this.label,
    required this.ready,
    required this.detail,
  });

  final String label;
  final bool ready;
  final String detail;
}

class MatchdayAutopilotPlan {
  const MatchdayAutopilotPlan({
    required this.strategy,
    required this.restoreStartersToStartingPositions,
    required this.formation,
    required this.fieldSize,
    required this.periodCount,
    required this.periodMinutes,
    required this.players,
    required this.positions,
    required this.plannedMinutes,
    required this.substitutions,
    required this.readiness,
    required this.positionMatches,
  });

  final AutopilotStrategy strategy;
  final bool restoreStartersToStartingPositions;
  final String formation;
  final int fieldSize;
  final int periodCount;
  final int periodMinutes;
  final List<MatchPlayer> players;
  final List<LineupPositionModel> positions;
  final Map<String, int> plannedMinutes;
  final List<PlannedSubstitutionModel> substitutions;
  final List<AutopilotReadinessItem> readiness;
  final int positionMatches;

  int get readyChecks => readiness.where((item) => item.ready).length;
  int get totalMinutes => periodCount * periodMinutes;
  int get benchCount =>
      (players.length - positions.length).clamp(0, 999).toInt();
  bool get canApply =>
      players.length >= fieldSize && positions.length == fieldSize;

  int get minuteSpread {
    if (plannedMinutes.isEmpty) return 0;
    final goalkeeperIds = players
        .where((player) => player.position?.toUpperCase() == 'TW')
        .map((player) => player.id)
        .toSet();
    final values = plannedMinutes.entries
        .where(
          (entry) =>
              goalkeeperIds.length > 1 || !goalkeeperIds.contains(entry.key),
        )
        .map((entry) => entry.value)
        .toList()
      ..sort();
    if (values.isEmpty) return 0;
    return values.last - values.first;
  }
}

MatchdayAutopilotPlan buildMatchdayAutopilotPlan({
  required MatchdayModel match,
  required List<PlayerModel> allPlayers,
  AutopilotStrategy strategy = AutopilotStrategy.balanced,
  bool restoreStartersToStartingPositions = false,
}) {
  final fieldSize = match.gameFormat.playerCount;
  final details = match.details;
  final periodCount = details?.periodCount ?? 2;
  final periodMinutes = details?.periodMinutes ?? 30;
  final formation = match.squad?.lineup?.formation ??
      match.squad?.formation ??
      match.gameFormat.defaultFormation;
  final playerModels = {for (final player in allPlayers) player.id: player};

  final nominated = match.squad?.members
          .where((member) => member.status == NominationStatus.nominated)
          .map((member) => member.player)
          .toList() ??
      const <MatchPlayer>[];
  final players = nominated.isNotEmpty
      ? nominated
      : allPlayers
          .where((player) => player.status == PlayerStatus.active)
          .map(
            (player) => MatchPlayer(
              id: player.id,
              name: player.displayName,
              shirtNumber: player.shirtNumber,
              position: player.position,
              secondaryPosition: player.secondaryPosition,
              status: player.status,
            ),
          )
          .toList();
  final history = {
    for (final player in players)
      player.id: playerModels[player.id]?.minutes ?? 0,
  };
  players.sort((a, b) {
    final minutes = (history[a.id] ?? 0).compareTo(history[b.id] ?? 0);
    if (minutes != 0) return minutes;
    return (a.shirtNumber ?? 999).compareTo(b.shirtNumber ?? 999);
  });

  final savedPositions = match.squad?.lineup?.positions ?? const [];
  final playerIds = players.map((player) => player.id).toSet();
  final usableSaved = savedPositions.length == fieldSize &&
      savedPositions
          .every((position) => playerIds.contains(position.player.id));
  final positions = usableSaved
      ? savedPositions
          .map(
            (position) => LineupPositionModel(
              player: position.player,
              positionCode: position.positionCode,
              x: position.x,
              y: position.y,
              period: 1,
              isStarter: true,
              isGoalkeeper: position.isGoalkeeper,
              isCaptain: position.isCaptain,
            ),
          )
          .toList()
      : planInitialLineup(
          players: players,
          fieldSize: fieldSize,
          formation: formation,
          playerPriority: history,
        );
  if (positions.isNotEmpty &&
      !positions.any((position) => position.isCaptain)) {
    final captainIndex =
        positions.indexWhere((position) => !position.isGoalkeeper);
    final index = captainIndex < 0 ? 0 : captainIndex;
    final current = positions[index];
    positions[index] = LineupPositionModel(
      player: current.player,
      positionCode: current.positionCode,
      x: current.x,
      y: current.y,
      period: current.period,
      isStarter: current.isStarter,
      isGoalkeeper: current.isGoalkeeper,
      isCaptain: true,
    );
  }

  final rotation = _planRotation(
    players: players,
    positions: positions,
    periodCount: periodCount,
    periodMinutes: periodMinutes,
    history: history,
    strategy: strategy,
    restoreStartersToStartingPositions: restoreStartersToStartingPositions,
  );
  final positionMatches = positions.where((position) {
    final primary = position.player.position?.toUpperCase();
    final secondary = position.player.secondaryPosition?.toUpperCase();
    return primary == position.positionCode ||
        secondary == position.positionCode;
  }).length;

  return MatchdayAutopilotPlan(
    strategy: strategy,
    restoreStartersToStartingPositions:
        strategy == AutopilotStrategy.positionFidelity &&
            restoreStartersToStartingPositions,
    formation: formation,
    fieldSize: fieldSize,
    periodCount: periodCount,
    periodMinutes: periodMinutes,
    players: players,
    positions: positions,
    plannedMinutes: rotation.minutes,
    substitutions: rotation.substitutions,
    positionMatches: positionMatches,
    readiness: [
      AutopilotReadinessItem(
        label: 'Kader',
        ready: players.length >= fieldSize,
        detail: '${players.length} verfügbar · $fieldSize benötigt',
      ),
      AutopilotReadinessItem(
        label: 'Spielmodell',
        ready: details != null && periodCount > 0 && periodMinutes > 0,
        detail:
            '$periodCount × $periodMinutes Minuten · ${match.gameFormat.strength}',
      ),
      AutopilotReadinessItem(
        label: 'Spielort',
        ready: match.location.trim().isNotEmpty,
        detail: match.location.trim().isEmpty ? 'Noch offen' : match.location,
      ),
      AutopilotReadinessItem(
        label: 'Treffpunkt',
        ready: match.meetingAt != null,
        detail: match.meetingAt == null
            ? 'Noch nicht festgelegt'
            : 'Ist festgelegt',
      ),
      AutopilotReadinessItem(
        label: 'Positionsdaten',
        ready: players.every(
          (player) =>
              player.position != null && player.position!.trim().isNotEmpty,
        ),
        detail:
            '${players.where((player) => player.position != null && player.position!.trim().isNotEmpty).length} von ${players.length} gepflegt',
      ),
    ],
  );
}

class _RotationPlan {
  const _RotationPlan(this.minutes, this.substitutions);

  final Map<String, int> minutes;
  final List<PlannedSubstitutionModel> substitutions;
}

_RotationPlan _planRotation({
  required List<MatchPlayer> players,
  required List<LineupPositionModel> positions,
  required int periodCount,
  required int periodMinutes,
  required Map<String, int> history,
  required AutopilotStrategy strategy,
  required bool restoreStartersToStartingPositions,
}) {
  final onField = positions.toList();
  final startingSlots = {
    for (final position in positions)
      if (position.isStarter) position.player.id: position,
  };
  final startingIds = onField.map((position) => position.player.id).toSet();
  final bench =
      players.where((player) => !startingIds.contains(player.id)).toList();
  final minutes = {for (final player in players) player.id: 0};
  final totalDuration = periodCount * periodMinutes;
  if (bench.isEmpty || onField.isEmpty) {
    for (final position in onField) {
      minutes[position.player.id] = totalDuration;
    }
    return _RotationPlan(minutes, const []);
  }

  final substitutions = <PlannedSubstitutionModel>[];
  final interval = (periodMinutes ~/ 2).clamp(5, 15).toInt();
  final waveSize = (onField.length ~/ 3).clamp(1, bench.length).toInt();
  var lastMinute = 0;

  for (var globalMinute = interval;
      globalMinute < totalDuration;
      globalMinute += interval) {
    final elapsed = globalMinute - lastMinute;
    for (final position in onField) {
      minutes[position.player.id] =
          (minutes[position.player.id] ?? 0) + elapsed;
    }
    lastMinute = globalMinute;

    bench.sort((a, b) => _compareIncomingPlayers(
          a,
          b,
          onField: onField,
          minutes: minutes,
          history: history,
          strategy: strategy,
        ));
    final incomingPlayers = bench.take(waveSize).toList();
    final outgoingIndices = <int>{};
    final outgoingPlayers = <MatchPlayer>[];

    for (final incoming in incomingPlayers) {
      final startingSlot = strategy == AutopilotStrategy.positionFidelity &&
              restoreStartersToStartingPositions
          ? startingSlots[incoming.id]
          : null;
      var candidates = List.generate(onField.length, (index) => index)
          .where((index) => !outgoingIndices.contains(index))
          .where((index) {
        final slot = onField[index];
        return incoming.position?.toUpperCase() == 'TW'
            ? slot.isGoalkeeper
            : !slot.isGoalkeeper;
      }).toList();
      if (candidates.isEmpty) continue;
      final compatible = candidates
          .where(
            (index) =>
                lineupFitScore(
                  incoming.position,
                  incoming.secondaryPosition,
                  onField[index].positionCode,
                ) >=
                0,
          )
          .toList();
      if (compatible.isNotEmpty) candidates = compatible;
      if (strategy == AutopilotStrategy.balanced) {
        final mostPlayed = candidates
            .map((index) => minutes[onField[index].player.id] ?? 0)
            .reduce((a, b) => a > b ? a : b);
        // Im ausgewogenen Modus bleibt die Positionspassung das wichtigste
        // Kriterium, solange die aktuelle Einsatzzeit nicht stark auseinander
        // läuft.
        candidates = candidates
            .where(
              (index) =>
                  (minutes[onField[index].player.id] ?? 0) >=
                  mostPlayed - interval,
            )
            .toList();
      }
      candidates.sort((a, b) {
        final returnsToStartingSlotA = startingSlot != null &&
            _isSameTacticalSlot(onField[a], startingSlot);
        final returnsToStartingSlotB = startingSlot != null &&
            _isSameTacticalSlot(onField[b], startingSlot);
        if (returnsToStartingSlotA != returnsToStartingSlotB) {
          return returnsToStartingSlotB ? 1 : -1;
        }
        final fitA = lineupFitScore(
          incoming.position,
          incoming.secondaryPosition,
          onField[a].positionCode,
        );
        final fitB = lineupFitScore(
          incoming.position,
          incoming.secondaryPosition,
          onField[b].positionCode,
        );
        final playedA = minutes[onField[a].player.id] ?? 0;
        final playedB = minutes[onField[b].player.id] ?? 0;
        if (strategy == AutopilotStrategy.playingTime) {
          final played = playedB.compareTo(playedA);
          if (played != 0) return played;
          final positionFit = fitB.compareTo(fitA);
          if (positionFit != 0) return positionFit;
        } else {
          final positionFit = fitB.compareTo(fitA);
          if (positionFit != 0) return positionFit;
          final played = playedB.compareTo(playedA);
          if (played != 0) return played;
        }
        if (onField[a].isCaptain != onField[b].isCaptain) {
          return onField[a].isCaptain ? 1 : -1;
        }
        return onField[a].player.name.compareTo(onField[b].player.name);
      });
      final outgoingIndex = candidates.first;
      final outgoing = onField[outgoingIndex];
      outgoingIndices.add(outgoingIndex);
      outgoingPlayers.add(outgoing.player);
      final period =
          (globalMinute ~/ periodMinutes).clamp(0, periodCount - 1).toInt() + 1;
      final minute = globalMinute % periodMinutes;
      substitutions.add(
        PlannedSubstitutionModel(
          period: period,
          minute: minute,
          playerInId: incoming.id,
          playerOutId: outgoing.player.id,
          positionCode: outgoing.positionCode,
          note: _rotationNote(
            incoming,
            outgoing.positionCode,
            returnsToStartingPosition: startingSlot != null &&
                _isSameTacticalSlot(outgoing, startingSlot),
          ),
        ),
      );
      onField[outgoingIndex] = LineupPositionModel(
        player: incoming,
        positionCode: outgoing.positionCode,
        x: outgoing.x,
        y: outgoing.y,
        period: period,
        isStarter: false,
        isGoalkeeper: outgoing.isGoalkeeper,
        isCaptain: false,
      );
    }
    bench.removeWhere(
      (player) => incomingPlayers.any((incoming) => incoming.id == player.id),
    );
    bench.addAll(outgoingPlayers);
  }
  final remaining = totalDuration - lastMinute;
  for (final position in onField) {
    minutes[position.player.id] =
        (minutes[position.player.id] ?? 0) + remaining;
  }
  return _RotationPlan(minutes, substitutions);
}

bool _isSameTacticalSlot(
  LineupPositionModel current,
  LineupPositionModel starting,
) =>
    current.positionCode == starting.positionCode &&
    current.x == starting.x &&
    current.y == starting.y;

int _compareIncomingPlayers(
  MatchPlayer a,
  MatchPlayer b, {
  required List<LineupPositionModel> onField,
  required Map<String, int> minutes,
  required Map<String, int> history,
  required AutopilotStrategy strategy,
}) {
  final currentA = minutes[a.id] ?? 0;
  final currentB = minutes[b.id] ?? 0;
  final historyA = history[a.id] ?? 0;
  final historyB = history[b.id] ?? 0;
  final fitA = _bestAvailableFit(a, onField);
  final fitB = _bestAvailableFit(b, onField);

  if (strategy == AutopilotStrategy.positionFidelity) {
    final fit = fitB.compareTo(fitA);
    if (fit != 0) return fit;
    final current = currentA.compareTo(currentB);
    if (current != 0) return current;
    final historic = historyA.compareTo(historyB);
    if (historic != 0) return historic;
  } else if (strategy == AutopilotStrategy.playingTime) {
    final historic = historyA.compareTo(historyB);
    if (historic != 0) return historic;
    final current = currentA.compareTo(currentB);
    if (current != 0) return current;
    final fit = fitB.compareTo(fitA);
    if (fit != 0) return fit;
  } else {
    final current = currentA.compareTo(currentB);
    if (current != 0) return current;
    final historic = historyA.compareTo(historyB);
    if (historic != 0) return historic;
    final fit = fitB.compareTo(fitA);
    if (fit != 0) return fit;
  }
  return a.name.compareTo(b.name);
}

int _bestAvailableFit(
  MatchPlayer player,
  List<LineupPositionModel> onField,
) {
  final goalkeeper = player.position?.toUpperCase() == 'TW';
  final scores = onField
      .where((slot) => goalkeeper ? slot.isGoalkeeper : !slot.isGoalkeeper)
      .map(
        (slot) => lineupFitScore(
          player.position,
          player.secondaryPosition,
          slot.positionCode,
        ),
      );
  if (scores.isEmpty) return -1000;
  return scores.reduce((a, b) => a > b ? a : b);
}

String _rotationNote(
  MatchPlayer incoming,
  String slot, {
  bool returnsToStartingPosition = false,
}) {
  if (returnsToStartingPosition) {
    return '$slot · Rückkehr auf Stammposition';
  }
  final primary = incoming.position?.trim().toUpperCase();
  final secondary = incoming.secondaryPosition?.trim().toUpperCase();
  if (primary == slot) return '$slot · Hauptposition';
  if (secondary == slot) return '$slot · Nebenposition';
  final score = lineupFitScore(primary, secondary, slot);
  if (score >= 400) return '$slot · direkt kompatibel';
  if (score >= 250) return '$slot · gleiche Positionsgruppe';
  if (score > 0) return '$slot · benachbarte Positionsgruppe';
  return '$slot · bestmögliche Alternative';
}
