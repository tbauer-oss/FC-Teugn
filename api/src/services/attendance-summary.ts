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
