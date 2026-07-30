export const youthAgeOrder = ['G', 'F', 'E', 'D', 'C', 'B', 'A'] as const;

export function nextAgeGroupCode(code: string) {
  const normalized = code.trim().toUpperCase();
  const index = youthAgeOrder.indexOf(normalized as (typeof youthAgeOrder)[number]);
  if (index < 0 || index === youthAgeOrder.length - 1) return normalized;
  return youthAgeOrder[index + 1];
}
export interface TransitionTeamInput {
  id: string;
  teamNumber?: number;
  name: string;
  shortName: string | null;
  level: string | null;
  ageGroup: { code: string; name: string };
  playerCount: number;
  activePlayerCount: number;
  staffCount: number;
}

export interface TransitionTeamOverride {
  sourceTeamId: string;
  targetAgeGroupCode?: string;
  targetName?: string;
  includePlayers?: boolean;
  includeStaff?: boolean;
}

export function buildTransitionTeamPlans(
  teams: TransitionTeamInput[],
  overrides: TransitionTeamOverride[] = [],
) {
  const overrideByTeam = new Map(overrides.map((item) => [item.sourceTeamId, item]));
  return teams.map((team) => {
    const override = overrideByTeam.get(team.id);
    return {
      sourceTeamId: team.id,
      teamNumber: team.teamNumber ?? 1,
      sourceName: team.name,
      sourceAgeGroupCode: team.ageGroup.code,
      targetAgeGroupCode:
        override?.targetAgeGroupCode?.trim().toUpperCase() || nextAgeGroupCode(team.ageGroup.code),
      targetName: override?.targetName?.trim() || team.name,
      shortName: team.shortName,
      level: team.level,
      includePlayers: override?.includePlayers ?? true,
      includeStaff: override?.includeStaff ?? true,
      playerCount: team.playerCount,
      activePlayerCount: team.activePlayerCount,
      archivedPlayerCount: team.playerCount - team.activePlayerCount,
      staffCount: team.staffCount,
    };
  });
}
