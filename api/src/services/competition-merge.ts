export type ImportSnapshot = Record<string, string | number | boolean | null>;
export const importFieldLabels: Record<string, string> = {
  startAt: 'Anstoß', endAt: 'Ende', location: 'Spielort', address: 'Adresse',
  status: 'Terminstatus', title: 'Bezeichnung', opponent: 'Gegner',
  homeAway: 'Heim/Auswärts', ourGoals: 'Eigene Tore', theirGoals: 'Gegentore',
  matchStatus: 'Spielstatus', competition: 'Wettbewerb', division: 'Staffel', matchDay: 'Spieltag',
};
export function mergeCompetitionFields(base: ImportSnapshot | null,
  current: ImportSnapshot, source: ImportSnapshot, sourceWins = false,
  resolutions: Record<string, 'LOCAL' | 'SOURCE'> = {}) {
  const merged = { ...source };
  const conflicts: string[] = [];
  for (const key of Object.keys(source)) {
    if (current[key] === source[key]) continue;
    const localChanged = base == null || current[key] !== base[key];
    const sourceChanged = base == null || source[key] !== base[key];
    if (localChanged && sourceChanged) {
      if (!resolutions[key]) conflicts.push(key);
      if (resolutions[key] === 'LOCAL' || (!resolutions[key] && !sourceWins)) merged[key] = current[key];
    } else if (localChanged) merged[key] = current[key];
  }
  return { merged, conflicts };
}
