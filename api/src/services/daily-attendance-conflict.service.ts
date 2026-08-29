import {
  AttendanceResponseSource,
  AttendanceStatus,
  EventStatus,
  EventType,
  GuardianRelationship,
  Prisma,
} from '@prisma/client';
import {
  fieldSizeForGameFormat,
  syncSquadWithTeamDefaultLineup,
} from './default-lineup.service';

const AUTOMATIC_DAILY_DECLINE_PREFIX = 'Automatisch abgesagt:';
const berlinDayFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Berlin',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});
const berlinTimeFormatter = new Intl.DateTimeFormat('de-DE', {
  timeZone: 'Europe/Berlin',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

type BerlinDay = { year: number; month: number; day: number };

export type DailyAttendanceEvent = {
  id: string;
  title: string;
  startAt: Date;
  teamId: string;
};

type AcceptanceInput = {
  event: DailyAttendanceEvent;
  playerId: string;
  actorId: string;
  respondedAt: Date;
  responseSource: AttendanceResponseSource;
  responderRelationship?: GuardianRelationship | null;
  goalkeeperAvailable?: boolean | null;
  honorLaterExistingAcceptance?: boolean;
};

function berlinDayParts(value: Date): BerlinDay {
  const parts = berlinDayFormatter.formatToParts(value);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((item) => item.type === type)?.value ?? 0);
  return {
    year: part('year'),
    month: part('month'),
    day: part('day'),
  };
}

function berlinMidnight(day: BerlinDay) {
  const desiredUtcShape = Date.UTC(day.year, day.month - 1, day.day);
  let result = new Date(desiredUtcShape);
  for (let index = 0; index < 3; index += 1) {
    const parts = berlinDayFormatter.formatToParts(result);
    const part = (type: Intl.DateTimeFormatPartTypes) =>
      Number(parts.find((item) => item.type === type)?.value ?? 0);
    const actualUtcShape = Date.UTC(
      part('year'),
      part('month') - 1,
      part('day'),
      part('hour'),
      part('minute'),
    );
    const correction = desiredUtcShape - actualUtcShape;
    if (correction === 0) break;
    result = new Date(result.getTime() + correction);
  }
  return result;
}

export function berlinCalendarDayRange(value: Date) {
  const day = berlinDayParts(value);
  const followingUtc = new Date(Date.UTC(day.year, day.month - 1, day.day + 1));
  const following = {
    year: followingUtc.getUTCFullYear(),
    month: followingUtc.getUTCMonth() + 1,
    day: followingUtc.getUTCDate(),
  };
  const key = `${String(day.year).padStart(4, '0')}-${String(day.month).padStart(2, '0')}-${String(day.day).padStart(2, '0')}`;
  return {
    key,
    startAt: berlinMidnight(day),
    endAt: berlinMidnight(following),
  };
}

function eventLabel(event: Pick<DailyAttendanceEvent, 'title' | 'startAt'>) {
  return `„${event.title}“ um ${berlinTimeFormatter.format(event.startAt)} Uhr`;
}

export function automaticDailyDeclineReason(
  winningEvent: Pick<DailyAttendanceEvent, 'title' | 'startAt'>,
) {
  return `${AUTOMATIC_DAILY_DECLINE_PREFIX} Am selben Tag wurde danach ${eventLabel(winningEvent)} zugesagt.`;
}

export function isAutomaticDailyDeclineReason(value: string | null | undefined) {
  return value?.startsWith(AUTOMATIC_DAILY_DECLINE_PREFIX) === true;
}

async function lockPlayerDay(
  tx: Prisma.TransactionClient,
  playerId: string,
  dayKey: string,
) {
  // Der transaktionsgebundene PostgreSQL-Lock serialisiert parallele Zusagen
  // desselben Spielers. So bleibt selbst bei nahezu zeitgleichen Geräten
  // exakt die zuletzt verarbeitete Zusage bestehen.
  await tx.$executeRaw(
    Prisma.sql`SELECT pg_advisory_xact_lock(hashtext(${`attendance:${playerId}:${dayKey}`}))`,
  );
}

export async function removePlayerFromDeclinedMatch(
  tx: Prisma.TransactionClient,
  input: { eventId: string; playerId: string; teamId: string },
) {
  const squad = await tx.squad.findUnique({
    where: { eventId: input.eventId },
    select: { id: true, lineup: { select: { id: true } } },
  });
  if (!squad) return;

  if (squad.lineup) {
    await Promise.all([
      tx.plannedSubstitution.deleteMany({
        where: {
          lineupId: squad.lineup.id,
          OR: [
            { playerInId: input.playerId },
            { playerOutId: input.playerId },
          ],
        },
      }),
      tx.lineupPosition.deleteMany({
        where: { lineupId: squad.lineup.id, playerId: input.playerId },
      }),
    ]);
  }
  await tx.squadMember.deleteMany({
    where: { squadId: squad.id, playerId: input.playerId },
  });
  const team = await tx.team.findUnique({
    where: { id: input.teamId },
    select: { gameFormat: true },
  });
  if (team) {
    await syncSquadWithTeamDefaultLineup(tx, {
      teamId: input.teamId,
      squadId: squad.id,
      fieldSize: fieldSizeForGameFormat(team.gameFormat),
    });
  }
}

export async function acceptAttendanceExclusivelyForDay(
  tx: Prisma.TransactionClient,
  input: AcceptanceInput,
) {
  const day = berlinCalendarDayRange(input.event.startAt);
  await lockPlayerDay(tx, input.playerId, day.key);

  const conflicts = await tx.attendance.findMany({
    where: {
      playerId: input.playerId,
      status: AttendanceStatus.YES,
      eventId: { not: input.event.id },
      event: {
        status: EventStatus.SCHEDULED,
        isHiddenRegularOccurrence: false,
        startAt: { gte: day.startAt, lt: day.endAt },
      },
    },
    select: {
      id: true,
      respondedAt: true,
      updatedAt: true,
      event: {
        select: {
          id: true,
          title: true,
          startAt: true,
          type: true,
          teamId: true,
          targetTeams: { select: { teamId: true }, take: 1 },
        },
      },
    },
  });

  const laterConflict = input.honorLaterExistingAcceptance
    ? conflicts
        .filter(
          (item) =>
            (item.respondedAt ?? item.updatedAt).getTime() >
            input.respondedAt.getTime(),
        )
        .sort(
          (left, right) =>
            (right.respondedAt ?? right.updatedAt).getTime() -
            (left.respondedAt ?? left.updatedAt).getTime(),
        )[0]
    : undefined;

  if (laterConflict) {
    const reason = automaticDailyDeclineReason(laterConflict.event);
    const reply = await tx.attendance.upsert({
      where: {
        eventId_playerId: {
          eventId: input.event.id,
          playerId: input.playerId,
        },
      },
      update: {
        status: AttendanceStatus.NO,
        reason,
        goalkeeperAvailable: null,
        respondedById: input.actorId,
        respondedAt: input.respondedAt,
        responseSource: AttendanceResponseSource.SYSTEM_ADMINISTRATION,
        responderRelationship: null,
      },
      create: {
        eventId: input.event.id,
        playerId: input.playerId,
        status: AttendanceStatus.NO,
        reason,
        respondedById: input.actorId,
        respondedAt: input.respondedAt,
        responseSource: AttendanceResponseSource.SYSTEM_ADMINISTRATION,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: input.actorId,
        teamId: input.event.teamId,
        action: 'ATTENDANCE_DAILY_CONFLICT_AUTO_DECLINED',
        entityType: 'Attendance',
        entityId: reply.id,
        metadata: {
          playerId: input.playerId,
          declinedEventId: input.event.id,
          winningEventId: laterConflict.event.id,
          day: day.key,
          reason,
        },
      },
    });
    return { reply, automaticallyDeclined: [], accepted: false };
  }

  const reply = await tx.attendance.upsert({
    where: {
      eventId_playerId: {
        eventId: input.event.id,
        playerId: input.playerId,
      },
    },
    update: {
      status: AttendanceStatus.YES,
      reason: null,
      goalkeeperAvailable: input.goalkeeperAvailable ?? null,
      respondedById: input.actorId,
      respondedAt: input.respondedAt,
      responseSource: input.responseSource,
      responderRelationship: input.responderRelationship ?? null,
    },
    create: {
      eventId: input.event.id,
      playerId: input.playerId,
      status: AttendanceStatus.YES,
      goalkeeperAvailable: input.goalkeeperAvailable ?? null,
      respondedById: input.actorId,
      respondedAt: input.respondedAt,
      responseSource: input.responseSource,
      responderRelationship: input.responderRelationship ?? null,
    },
  });

  if (conflicts.length > 0) {
    const conflictIds = conflicts.map((item) => item.id);
    const reason = automaticDailyDeclineReason(input.event);
    await tx.attendance.updateMany({
      where: { id: { in: conflictIds }, status: AttendanceStatus.YES },
      data: {
        status: AttendanceStatus.NO,
        reason,
        goalkeeperAvailable: null,
        respondedById: input.actorId,
        respondedAt: input.respondedAt,
        responseSource: AttendanceResponseSource.SYSTEM_ADMINISTRATION,
        responderRelationship: null,
      },
    });
    for (const conflict of conflicts) {
      if (conflict.event.type !== EventType.MATCH) continue;
      await removePlayerFromDeclinedMatch(tx, {
        eventId: conflict.event.id,
        playerId: input.playerId,
        teamId:
          conflict.event.targetTeams[0]?.teamId ?? conflict.event.teamId,
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: input.actorId,
        teamId: input.event.teamId,
        action: 'ATTENDANCE_DAILY_CONFLICTS_AUTO_DECLINED',
        entityType: 'Attendance',
        entityId: reply.id,
        metadata: {
          playerId: input.playerId,
          winningEventId: input.event.id,
          declinedEventIds: conflicts.map((item) => item.event.id),
          day: day.key,
          reason,
        },
      },
    });
  }

  return {
    reply,
    automaticallyDeclined: conflicts.map((item) => item.event.id),
    accepted: true,
  };
}
