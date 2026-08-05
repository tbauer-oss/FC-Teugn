import 'models/matchday.dart';

Map<String, NominationStatus> retainEligibleSquadSelection(
  Map<String, NominationStatus> selection,
  Iterable<String> eligiblePlayerIds,
) {
  final eligible = eligiblePlayerIds.toSet();
  return {
    for (final entry in selection.entries)
      if (eligible.contains(entry.key)) entry.key: entry.value,
  };
}
