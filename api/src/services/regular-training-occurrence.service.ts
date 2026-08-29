import {
  AttendanceStatus,
  EventCategory,
  EventStatus,
  EventType,
  EventVisibility,
  Prisma,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import {
  acceptAttendanceExclusivelyForDay,
  isAutomaticDailyDeclineReason,
} from './daily-attendance-conflict.service';
import { parseTrainingSlot } from './pitch-conflict.service';

export type RegularTrainingTeamSchedule = {
  id: string;
  name: string;
  trainingLocation: string | null;
  trainingTimes: string[];
  seasonStartDate: Date | null;
  seasonEndDate: Date | null;
  indoorSeasonStartDate: Date | null;
  indoorSeasonEndDate: Date | null;
  indoorTrainingLocation: string | null;
  indoorTrainingTimes: string[];
  ageGroup: {
    season: {
      startDate: Date;
      endDate: Date;
      name: string;
    };
  };
};

type RegularTrainingTransaction = Pick<
  Prisma.TransactionClient,
  | 'event'
  | 'eventParticipant'
  | 'auditLog'
  | 'attendance'
  | 'regularTrainingAttendancePreference'
>;

type CalendarParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
};

export type RegularTrainingOccurrence = {
  teamId: string;
  teamName: string;
  seasonName: string;
  startAt: Date;
  endAt: Date;
  location: string;
};

async function applyRegularTrainingAttendancePreferences(
  tx: RegularTrainingTransaction,
  eventId: string,
  teamId: string,
  startAt: Date,
) {
  // Einige isolierte Bestands-Tests verwenden bewusst einen schlanken
  // Transaktions-Dummy. In der echten Prisma-Transaktion sind beide Delegates
  // vorhanden; der Guard hält die Terminabgleich-Tests rückwärtskompatibel.
  if (
    !('regularTrainingAttendancePreference' in tx) ||
    !('attendance' in tx)
  ) {
    return;
  }
  const preferences = await tx.regularTrainingAttendancePreference.findMany({
    where: {
      teamId,
      status: AttendanceStatus.YES,
      validFrom: { lte: startAt },
      validUntil: { gte: startAt },
    },
    select: {
      playerId: true,
      respondedById: true,
      responseSource: true,
      responderRelationship: true,
      updatedAt: true,
    },
    orderBy: { playerId: 'asc' },
  });
  if (preferences.length === 0) return;

  const existing = await tx.attendance.findMany({
    where: {
      eventId,
      playerId: { in: preferences.map((item) => item.playerId) },
    },
    select: { playerId: true, status: true, reason: true },
  });
  const existingByPlayer = new Map(
    existing.map((item) => [item.playerId, item]),
  );
  for (const preference of preferences) {
    const current = existingByPlayer.get(preference.playerId);
    // Eine bewusst für diesen konkreten Termin eingetragene Absage ist eine
    // Ausnahme und darf von der Serienzusage niemals überschrieben werden.
    if (
      current?.status === AttendanceStatus.NO &&
      !isAutomaticDailyDeclineReason(current.reason)
    ) {
      continue;
    }
    await acceptAttendanceExclusivelyForDay(
      tx as Prisma.TransactionClient,
      {
        event: { id: eventId, title: 'Training', startAt, teamId },
        playerId: preference.playerId,
        actorId: preference.respondedById,
        respondedAt: preference.updatedAt,
        responseSource: preference.responseSource,
        responderRelationship: preference.responderRelationship,
        honorLaterExistingAcceptance: true,
      },
    );
  }
}

async function removeForeignRegularTrainingParticipants(
  tx: RegularTrainingTransaction,
  eventId: string,
  teamId: string,
) {
  // Schlanke Test-Transaktionen aus älteren Tests besitzen diesen Delegate
  // teilweise noch nicht. In echten Prisma-Transaktionen ist er vorhanden.
  if (!('eventParticipant' in tx) || !('attendance' in tx)) return;

  const [attendance, participants] = await Promise.all([
    tx.attendance.findMany({
      where: { eventId },
      select: {
        id: true,
        playerId: true,
        player: { select: { teamId: true } },
      },
    }),
    tx.eventParticipant.findMany({
      where: { eventId, playerId: { not: null } },
      select: {
        id: true,
        playerId: true,
        player: { select: { teamId: true } },
      },
    }),
  ]);
  const foreignAttendanceIds = attendance
    .filter((item) => item.player.teamId !== teamId)
    .map((item) => item.id);
  const foreignParticipantIds = participants
    .filter((item) => item.player?.teamId !== teamId)
    .map((item) => item.id);
  if (foreignAttendanceIds.length === 0 && foreignParticipantIds.length === 0) {
    return;
  }

  await Promise.all([
    foreignAttendanceIds.length > 0
      ? tx.attendance.deleteMany({ where: { id: { in: foreignAttendanceIds } } })
      : Promise.resolve(),
    foreignParticipantIds.length > 0
      ? tx.eventParticipant.deleteMany({ where: { id: { in: foreignParticipantIds } } })
      : Promise.resolve(),
  ]);
  await tx.auditLog.create({
    data: {
      teamId,
      action: 'REGULAR_TRAINING_FOREIGN_PARTICIPANTS_CLEANED',
      entityType: 'Event',
      entityId: eventId,
      metadata: {
        removedAttendance: foreignAttendanceIds.length,
        removedParticipants: foreignParticipantIds.length,
      },
    },
  });
}

const berlinPartsFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Berlin',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

function calendarParts(value: Date): CalendarParts {
  const parts = berlinPartsFormatter.formatToParts(value);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((item) => item.type === type)?.value ?? 0);
  return {
    year: part('year'),
    month: part('month'),
    day: part('day'),
    hour: part('hour'),
    minute: part('minute'),
  };
}

function dateKey(value: Pick<CalendarParts, 'year' | 'month' | 'day'>) {
  return value.year * 10_000 + value.month * 100 + value.day;
}

function berlinDateTime(
  date: Pick<CalendarParts, 'year' | 'month' | 'day'>,
  minuteOfDay: number,
) {
  const desired = {
    ...date,
    hour: Math.floor(minuteOfDay / 60),
    minute: minuteOfDay % 60,
  };
  const desiredUtcShape = Date.UTC(
    desired.year,
    desired.month - 1,
    desired.day,
    desired.hour,
    desired.minute,
  );
  let result = new Date(desiredUtcShape);
  // Zwei Korrekturen reichen sowohl für CET als auch CEST und halten die
  // gespeicherte UTC-Zeit stabil über die Zeitumstellungen hinweg.
  for (let index = 0; index < 3; index += 1) {
    const actual = calendarParts(result);
    const actualUtcShape = Date.UTC(
      actual.year,
      actual.month - 1,
      actual.day,
      actual.hour,
      actual.minute,
    );
    const correction = desiredUtcShape - actualUtcShape;
    if (correction === 0) break;
    result = new Date(result.getTime() + correction);
  }
  return result;
}

function weekdayNumber(value: string) {
  const weekdays = new Map([
    ['montag', 1],
    ['dienstag', 2],
    ['mittwoch', 3],
    ['donnerstag', 4],
    ['freitag', 5],
    ['samstag', 6],
    ['sonntag', 7],
  ]);
  return weekdays.get(value.toLocaleLowerCase('de-DE')) ?? null;
}

export function nextRegularTrainingOccurrence(
  team: RegularTrainingTeamSchedule,
  now = new Date(),
): RegularTrainingOccurrence | null {
  const seasonStart = calendarParts(
    team.seasonStartDate ?? team.ageGroup.season.startDate,
  );
  const seasonEnd = calendarParts(
    team.seasonEndDate ?? team.ageGroup.season.endDate,
  );
  const today = calendarParts(now);
  const firstKey = Math.max(dateKey(today), dateKey(seasonStart));
  let cursor = new Date(
    Date.UTC(
      firstKey === dateKey(today) ? today.year : seasonStart.year,
      (firstKey === dateKey(today) ? today.month : seasonStart.month) - 1,
      firstKey === dateKey(today) ? today.day : seasonStart.day,
    ),
  );
  const lastKey = dateKey(seasonEnd);
  const indoorStartKey = team.indoorSeasonStartDate
    ? dateKey(calendarParts(team.indoorSeasonStartDate))
    : null;
  const indoorEndKey = team.indoorSeasonEndDate
    ? dateKey(calendarParts(team.indoorSeasonEndDate))
    : null;
  const outdoorSlots = team.trainingTimes
    .map((value) => parseTrainingSlot(value, team.trainingLocation))
    .filter(
      (slot): slot is NonNullable<ReturnType<typeof parseTrainingSlot>> =>
        slot !== null,
    );
  const indoorSlots = team.indoorTrainingTimes
    .map((value) => parseTrainingSlot(value, team.indoorTrainingLocation))
    .filter(
      (slot): slot is NonNullable<ReturnType<typeof parseTrainingSlot>> =>
        slot !== null,
    );

  // Eine Saison ist üblicherweise deutlich kürzer. Die Obergrenze verhindert
  // dennoch, dass fehlerhafte Stammdaten eine unbeschränkte Suche auslösen.
  for (let checkedDays = 0; checkedDays < 800; checkedDays += 1) {
    const cursorParts = {
      year: cursor.getUTCFullYear(),
      month: cursor.getUTCMonth() + 1,
      day: cursor.getUTCDate(),
    };
    const cursorKey = dateKey(cursorParts);
    if (cursorKey > lastKey) break;
    const indoor =
      indoorStartKey !== null &&
      indoorEndKey !== null &&
      cursorKey >= indoorStartKey &&
      cursorKey <= indoorEndKey;
    const weekday = cursor.getUTCDay() === 0 ? 7 : cursor.getUTCDay();
    const candidates = (indoor ? indoorSlots : outdoorSlots)
      .filter((slot) => weekdayNumber(slot.weekday) === weekday)
      .map((slot) => ({
        teamId: team.id,
        teamName: team.name,
        seasonName: team.ageGroup.season.name,
        startAt: berlinDateTime(cursorParts, slot.startMinute),
        endAt: berlinDateTime(cursorParts, slot.endMinute),
        location: slot.pitch,
      }))
      .filter((occurrence) => occurrence.startAt > now)
      .sort((left, right) => left.startAt.getTime() - right.startAt.getTime());
    if (candidates.length > 0) return candidates[0];
    cursor = new Date(cursor.getTime() + 86_400_000);
  }
  return null;
}

export async function ensureNextRegularTrainingOccurrences(
  requestedTeamIds: string[],
  now = new Date(),
) {
  const teamIds = [...new Set(requestedTeamIds)];
  if (teamIds.length === 0) return;
  const teams = await prisma.team.findMany({
    where: {
      id: { in: teamIds },
      isActive: true,
      deletedAt: null,
    },
    select: {
      id: true,
      name: true,
      trainingLocation: true,
      trainingTimes: true,
      seasonStartDate: true,
      seasonEndDate: true,
      indoorSeasonStartDate: true,
      indoorSeasonEndDate: true,
      indoorTrainingLocation: true,
      indoorTrainingTimes: true,
      ageGroup: {
        select: {
          season: {
            select: { startDate: true, endDate: true, name: true },
          },
        },
      },
    },
  });
  // Jeder Abruf gleicht auch Altstände früherer App-Versionen ab. Damit
  // verschwinden alte Uhrzeiten und doppelte Materialisierungen unmittelbar,
  // ohne dass ein Administrator den Wochenplan erneut speichern muss.
  await Promise.all(
    teams.map((team) =>
      prisma.$transaction((tx) =>
        reconcileNextRegularTrainingOccurrence(tx, team, now),
      ),
    ),
  );
}

/**
 * Reconciles the already materialized next occurrence after a team's regular
 * schedule changes. The canonical event is updated in place so attendance,
 * participants, cancellations and reminders keep their logical identity.
 * Additional stale materializations are retained only as hidden history,
 * never as a second visible training.
 */
export async function reconcileNextRegularTrainingOccurrence(
  tx: RegularTrainingTransaction,
  team: RegularTrainingTeamSchedule,
  now = new Date(),
) {
  const idPrefix = `regular-training:${team.id}:`;
  const materialized = await tx.event.findMany({
    where: {
      teamId: team.id,
      category: EventCategory.TRAINING,
      startAt: { gte: now },
      OR: [
        { id: { startsWith: idPrefix } },
        {
          seriesId: null,
          isSeriesException: true,
          description: {
            startsWith: 'Reguläre Trainingszeit laut Belegungsplan der Saison ',
          },
        },
      ],
    },
    orderBy: { startAt: 'asc' },
    select: {
      id: true,
      startAt: true,
      endAt: true,
      location: true,
      status: true,
      isHiddenRegularOccurrence: true,
      _count: { select: { attendance: true, participants: true } },
    },
  });
  let expected = nextRegularTrainingOccurrence(team, now);
  const visible = materialized.filter(
    (event) => !event.isHiddenRegularOccurrence,
  );
  const preservedOccurrenceIds = new Set<string>();

  // A deleted/cancelled item is an exception for exactly this team and this
  // start time. Walk past such exceptions instead of treating the first
  // weekly slot as the team's only future regular training. This keeps the
  // tombstone intact while still materialising the next valid occurrence.
  for (let guard = 0; expected && guard < 128; guard += 1) {
    const matchingTombstone = materialized.find(
      (event) =>
        event.isHiddenRegularOccurrence &&
        Math.abs(event.startAt.getTime() - expected!.startAt.getTime()) <
          5 * 60_000,
    );
    if (matchingTombstone) {
      const explicitDeletion = await tx.auditLog.findFirst({
        where: {
          entityType: 'Event',
          entityId: matchingTombstone.id,
          action: {
            in: [
              'CANCELLED_TRAINING_OCCURRENCE_DELETED',
              'REGULAR_TRAINING_OCCURRENCE_DELETED',
            ],
          },
        },
        select: { id: true },
      });
      if (explicitDeletion) {
        preservedOccurrenceIds.add(matchingTombstone.id);
        expected = nextRegularTrainingOccurrence(
          team,
          new Date(expected.startAt.getTime() + 5 * 60_000),
        );
        continue;
      }
    }
    const matchingCancellation = visible.find(
      (event) =>
        event.status === EventStatus.CANCELLED &&
        Math.abs(event.startAt.getTime() - expected!.startAt.getTime()) <
          5 * 60_000,
    );
    if (matchingCancellation) {
      preservedOccurrenceIds.add(matchingCancellation.id);
      expected = nextRegularTrainingOccurrence(
        team,
        new Date(expected.startAt.getTime() + 5 * 60_000),
      );
      continue;
    }
    break;
  }
  const reconcilableVisible = visible.filter(
    (event) => !preservedOccurrenceIds.has(event.id),
  );
  if (!expected) {
    const hiddenIds = reconcilableVisible.map((event) => event.id);
    if (hiddenIds.length > 0) {
      await tx.event.updateMany({
        where: { id: { in: hiddenIds } },
        data: {
          isHiddenRegularOccurrence: true,
          reminderSyncPendingAt: new Date(),
        },
      });
    }
    return [...preservedOccurrenceIds, ...hiddenIds];
  }

  const expectedId =
    `regular-training:${team.id}:${expected.startAt.getTime()}`;
  const expectedTombstone = materialized.find(
    (event) =>
      event.isHiddenRegularOccurrence &&
      Math.abs(event.startAt.getTime() - expected.startAt.getTime()) <
        5 * 60_000,
  );
  // Prefer the occurrence that already contains user data. This protects a
  // response-bearing event even if an earlier software version produced a
  // duplicate. The stable event ID keeps all dependent rows attached.
  const canonical = [
    ...reconcilableVisible,
    ...(expectedTombstone ? [expectedTombstone] : []),
  ]
    .filter((event) => event.status !== EventStatus.CANCELLED)
    .sort((left, right) => {
      const leftData = left._count.attendance + left._count.participants;
      const rightData = right._count.attendance + right._count.participants;
      return rightData - leftData ||
        left.startAt.getTime() - right.startAt.getTime();
    })[0];
  const canonicalId = canonical?.id ?? expectedId;
  const eventData = {
    teamId: team.id,
    type: EventType.TRAINING,
    category: EventCategory.TRAINING,
    visibility: EventVisibility.TEAM,
    title: 'Training',
    startAt: expected.startAt,
    endAt: expected.endAt,
    location: expected.location,
    description:
      `Reguläre Trainingszeit laut Belegungsplan der Saison ${expected.seasonName}.`,
    isSeriesException: true,
    isHiddenRegularOccurrence: false,
  } as const;
  if (canonical) {
    const alreadyCurrent =
      !canonical.isHiddenRegularOccurrence &&
      canonical.startAt.getTime() === expected.startAt.getTime() &&
      canonical.endAt?.getTime() === expected.endAt.getTime() &&
      canonical.location === expected.location;
    if (!alreadyCurrent) {
      await tx.event.update({
        where: { id: canonical.id },
        data: {
          ...eventData,
          reminderSyncPendingAt: new Date(),
          targetTeams: {
            deleteMany: {},
            create: [{ teamId: team.id }],
          },
        },
      });
    }
  } else {
    await tx.event.upsert({
      where: { id: canonicalId },
      update: {},
      create: {
        id: canonicalId,
        status: EventStatus.SCHEDULED,
        ...eventData,
        targetTeams: { create: [{ teamId: team.id }] },
      },
    });
  }
  await removeForeignRegularTrainingParticipants(tx, canonicalId, team.id);
  await applyRegularTrainingAttendancePreferences(
    tx,
    canonicalId,
    team.id,
    expected.startAt,
  );
  const staleIds = reconcilableVisible
    .map((event) => event.id)
    .filter((id) => id !== canonicalId);
  if (staleIds.length > 0) {
    await tx.event.updateMany({
      where: { id: { in: staleIds } },
      data: {
        isHiddenRegularOccurrence: true,
        reminderSyncPendingAt: new Date(),
      },
    });
  }
  return [...preservedOccurrenceIds, canonicalId, ...staleIds];
}
