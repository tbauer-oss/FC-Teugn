type Player = { id: string; name: string; userIds: string[] };
export type VotingUnit = { unitKey: string; label: string; authorizedUserIds: string[]; playerIds: string[] };
/** Snapshot connected households so two guardians cannot vote twice for the
 * same family. Every child is retained for subsequent authorization checks. */
export function buildVotingUnits(type: string, players: Player[], people: { id: string; name: string }[]): VotingUnit[] {
  if (type === 'PERSON') return people.map(p => ({ unitKey: `person:${p.id}`, label: p.name, authorizedUserIds: [p.id], playerIds: [] }));
  if (type === 'CHILD') return players.filter(p => p.userIds.length).map(p => ({
    unitKey: `child:${p.id}`, label: p.name, authorizedUserIds: [...new Set(p.userIds)], playerIds: [p.id],
  }));
  const groups: Player[][] = [];
  for (const player of players) {
    if (!player.userIds.length) continue;
    const matching = groups.filter(group => group.some(p => p.userIds.some(id => player.userIds.includes(id))));
    const merged = [player, ...matching.flat()];
    for (const group of matching) groups.splice(groups.indexOf(group), 1);
    groups.push(merged);
  }
  return groups.map(group => ({ unitKey: `family:${group.map(p => p.id).sort()[0]}`,
    label: group.map(p => p.name).join(', '), playerIds: group.map(p => p.id),
    authorizedUserIds: [...new Set(group.flatMap(p => p.userIds))] }));
}
export function validateVote(choices: unknown, optionCount: number, multiple: boolean): number[] {
  if (!Array.isArray(choices) || choices.length < 1 || (!multiple && choices.length !== 1) ||
    choices.some(c => !Number.isInteger(c) || c < 0 || c >= optionCount) || new Set(choices).size !== choices.length) {
    throw new Error('Bitte gültige Antwortmöglichkeiten auswählen.');
  }
  return choices;
}
