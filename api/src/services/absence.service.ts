import { AttendanceStatus, PlayerAbsence, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';

const berlinDay = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Berlin', year: 'numeric', month: '2-digit', day: '2-digit' });
export function absenceApplies(absence: Pick<PlayerAbsence, 'startsOn' | 'endsOn' | 'weekdays' | 'eventTypes' | 'teamIds' | 'endedAt'>,
  event: { startAt: Date; type: string; teamId: string; targetTeams?: { teamId: string }[] }) {
  const day = berlinDay.format(event.startAt);
  const weekday = new Date(`${day}T12:00:00Z`).getUTCDay();
  return !absence.endedAt && day >= absence.startsOn && day <= absence.endsOn &&
    (!absence.weekdays.length || absence.weekdays.includes(weekday)) &&
    absence.eventTypes.includes(event.type) && (!absence.teamIds.length ||
      [event.teamId, ...(event.targetTeams ?? []).map(team => team.teamId)].some(id => absence.teamIds.includes(id)));
}
function previousReply(value: Prisma.JsonValue | null): Prisma.AttendanceUncheckedUpdateInput {
  const source = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  return {
    status: (source.status as AttendanceStatus) ?? 'UNKNOWN', reason: source.reason as string | null ?? null,
    respondedAt: typeof source.respondedAt === 'string' ? new Date(source.respondedAt) : null,
    respondedById: source.respondedById as string | null ?? null,
    responseSource: source.responseSource as never ?? null,
    responderRelationship: source.responderRelationship as never ?? null,
    absenceId: null, beforeAbsence: Prisma.DbNull,
  };
}
export async function reconcilePlayerAbsences(tx: Prisma.TransactionClient, playerIds: string[], now = new Date(), eventIds?: string[]) {
  if (!playerIds.length) return;
  const players = await tx.player.findMany({ where: { id: { in: playerIds } },
    include: { absences: { where: { endedAt: null }, orderBy: { updatedAt: 'desc' } }, seasonAssignments: true } });
  for (const player of players) {
    const teamIds = [...new Set([player.teamId, ...player.seasonAssignments.map(a => a.teamId)].filter((id): id is string => !!id))];
    const events = await tx.event.findMany({ where: {
      ...(eventIds ? { id: { in: eventIds } } : {}),
      startAt: { gte: now }, attendanceFinalized: false,
      OR: [{ teamId: { in: teamIds } }, { targetTeams: { some: { teamId: { in: teamIds } } } }, { attendance: { some: { playerId: player.id, absenceId: { not: null } } } }],
    }, include: { attendance: { where: { playerId: player.id } }, targetTeams: true, participants: true } });
    for (const event of events) {
      const old = event.attendance[0];
      const requested = event.participants.filter(p => p.playerId && p.responseRequired).map(p => p.playerId);
      if (requested.length && !requested.includes(player.id) && !old?.absenceId) continue;
      const absence = player.absences.find(a => absenceApplies(a, event));
      if (!absence) {
        if (old?.absenceId) await tx.attendance.update({ where: { id: old.id }, data: previousReply(old.beforeAbsence) });
        else continue;
      } else if (!(old && !old.absenceId && old.respondedAt && old.respondedAt >= absence.updatedAt)) {
        if (old?.absenceId === absence.id && old.status === 'NO') continue;
        const beforeAbsence = old?.absenceId ? old.beforeAbsence : old ? JSON.parse(JSON.stringify({
          status: old.status, reason: old.reason, respondedAt: old.respondedAt, respondedById: old.respondedById,
          responseSource: old.responseSource, responderRelationship: old.responderRelationship,
        })) : {};
        const data = { status: AttendanceStatus.NO, absenceId: absence.id,
          beforeAbsence: beforeAbsence ?? {}, reason: 'Geplante Abwesenheit',
          respondedById: absence.createdById, respondedAt: absence.updatedAt };
        await tx.attendance.upsert({ where: { eventId_playerId: { eventId: event.id, playerId: player.id } },
          update: data, create: { ...data, eventId: event.id, playerId: player.id } });
      } else continue;
      await tx.event.update({ where: { id: event.id }, data: { reminderSyncPendingAt: now } });
    }
  }
}

export async function reconcileAbsencesForEvents(tx: Prisma.TransactionClient, eventIds: string[]) {
  if (!eventIds.length) return;
  const events = await tx.event.findMany({ where: { id: { in: eventIds } }, select: { teamId: true, targetTeams: true } });
  const teamIds = [...new Set(events.flatMap(e => [e.teamId, ...e.targetTeams.map(t => t.teamId)]))];
  const players = await tx.player.findMany({ where: {
    OR: [{ absences: { some: { endedAt: null } }, OR: [{ teamId: { in: teamIds } }, { seasonAssignments: { some: { teamId: { in: teamIds } } } }] },
      { attendance: { some: { eventId: { in: eventIds }, absenceId: { not: null } } } }],
  }, select: { id: true } });
  await reconcilePlayerAbsences(tx, players.map(p => p.id), new Date(), eventIds);
}

/** Called before reminders and after generation of regular training dates. */
export async function reconcileActiveAbsences() {
  const [active, previouslyApplied] = await Promise.all([
    prisma.playerAbsence.findMany({ where: { endedAt: null, endsOn: { gte: berlinDay.format(new Date()) } }, distinct: ['playerId'], select: { playerId: true } }),
    prisma.attendance.findMany({ where: { absenceId: { not: null }, event: { startAt: { gte: new Date() } } }, distinct: ['playerId'], select: { playerId: true } }),
  ]);
  const ids = [...new Set([...active, ...previouslyApplied].map(a => a.playerId))];
  for (const id of ids) await prisma.$transaction(tx => reconcilePlayerAbsences(tx, [id]), {
    isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 15000,
  });
  return { players: ids.length };
}
