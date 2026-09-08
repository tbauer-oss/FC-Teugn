type AttendanceReply = {
  playerId: string;
  status: string;
};

/**
 * Returns every roster player who still owes a real response.
 *
 * UNKNOWN rows are created as placeholders when an event explicitly asks
 * selected players for feedback. They remain open until a clear YES or NO is
 * submitted. Legacy MAYBE rows are deliberately treated as open.
 */
export function openAttendancePlayerIds(
  rosterPlayerIds: string[],
  attendance: AttendanceReply[],
) {
  const respondedPlayerIds = new Set(
    attendance
      .filter((reply) => reply.status === 'YES' || reply.status === 'NO')
      .map((reply) => reply.playerId),
  );
  return rosterPlayerIds.filter((playerId) => !respondedPlayerIds.has(playerId));
}

/** Match totals belong to the event, including guests and their declined replies.
 * A removed participant is excluded even if a historic response still exists. */
export function matchResponseRoster<T extends { id: string; teamId: string | null }>(
  teamRoster: T[],
  targetTeamIds: string[],
  participants: Array<{ playerId: string | null; responseRequired: boolean; player: T | null }>,
  responsePlayers: T[],
  nominatedPlayers: T[] = [],
): T[] {
  const invited = participants.filter(p => p.responseRequired && p.player).map(p => p.player!);
  const excluded = new Set(participants.filter(p => !p.responseRequired).map(p => p.playerId));
  const base = invited.length || nominatedPlayers.length
    ? [...invited, ...nominatedPlayers]
    : teamRoster.filter(p => p.teamId !== null && targetTeamIds.includes(p.teamId));
  return [...new Map([...base, ...responsePlayers]
    .filter(p => !excluded.has(p.id)).map(p => [p.id, p])).values()];
}
