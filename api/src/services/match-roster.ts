export function rosterTeamIdsForMatch(
  accessibleTeamIds: string[],
) {
  return [...new Set(accessibleTeamIds)];
}
