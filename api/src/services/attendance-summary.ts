type AttendanceReply = {
  playerId: string;
  status: string;
};

/**
 * Returns every roster player who still owes a real response.
 *
 * UNKNOWN rows are created as placeholders when an event explicitly asks
 * selected players for feedback. They must remain open until YES, NO or MAYBE
 * is submitted and therefore never count as an answered reply.
 */
export function openAttendancePlayerIds(
  rosterPlayerIds: string[],
  attendance: AttendanceReply[],
) {
  const respondedPlayerIds = new Set(
    attendance
      .filter((reply) => reply.status !== 'UNKNOWN')
      .map((reply) => reply.playerId),
  );
  return rosterPlayerIds.filter((playerId) => !respondedPlayerIds.has(playerId));
}
