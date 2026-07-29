export function rosterTeamIdsForMatch(
  targetTeamIds: string[],
  accessibleTeamIds: string[],
  targetRosterCount: number,
) {
  const accessible = [...new Set(accessibleTeamIds)];
  const targets = [...new Set(targetTeamIds)].filter((teamId) =>
    accessible.includes(teamId),
  );

  if (targets.length > 0 && targetRosterCount > 0) return targets;
  return accessible;
}
