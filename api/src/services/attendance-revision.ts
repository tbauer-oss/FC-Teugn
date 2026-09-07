import { AttendanceStatus } from '@prisma/client';

export function attendanceAfterRevision<T extends { status: AttendanceStatus; respondedAt?: Date | null; absenceId?: string | null }>(
  reply: T, event: { responseRevisionAt?: Date | null; attendanceFinalized?: boolean; startAt: Date }, now = new Date(),
) {
  const needsConfirmation = !event.attendanceFinalized && event.startAt > now && !!event.responseRevisionAt &&
    !reply.absenceId && (!reply.respondedAt || reply.respondedAt < event.responseRevisionAt);
  return needsConfirmation ? { ...reply, status: AttendanceStatus.UNKNOWN, previousResponseStatus: reply.status, needsConfirmation: true } : reply;
}
