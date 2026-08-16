import {
  EventCategory,
  EventStatus,
  EventType,
  EventVisibility,
  Prisma,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
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
  'event'
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
  const occurrences = teams
    .map((team) => nextRegularTrainingOccurrence(team, now))
    .filter(
      (occurrence): occurrence is RegularTrainingOccurrence =>
        occurrence !== null,
    );
  if (occurrences.length === 0) return;

  const existing = await prisma.event.findMany({
    where: {
      category: EventCategory.TRAINING,
      OR: occurrences.map((occurrence) => ({
        startAt: {
          gte: new Date(occurrence.startAt.getTime() - 5 * 60_000),
          lte: new Date(occurrence.startAt.getTime() + 5 * 60_000),
        },
        OR: [
          { teamId: occurrence.teamId },
          { targetTeams: { some: { teamId: occurrence.teamId } } },
        ],
      })),
    },
    select: {
      teamId: true,
      startAt: true,
      targetTeams: { select: { teamId: true } },
    },
  });

  await Promise.all(
    occurrences.map(async (occurrence) => {
      const duplicate = existing.some((event) => {
        const targetIds = event.targetTeams.length
          ? event.targetTeams.map((target) => target.teamId)
          : [event.teamId];
        return (
          targetIds.includes(occurrence.teamId) &&
          Math.abs(event.startAt.getTime() - occurrence.startAt.getTime()) <
            5 * 60_000
        );
      });
      if (duplicate) return;
      const id = `regular-training:${occurrence.teamId}:${occurrence.startAt.getTime()}`;
      await prisma.event.upsert({
        where: { id },
        update: {},
        create: {
          id,
          teamId: occurrence.teamId,
          type: EventType.TRAINING,
          category: EventCategory.TRAINING,
          status: EventStatus.SCHEDULED,
          visibility: EventVisibility.TEAM,
          title: 'Training',
          startAt: occurrence.startAt,
          endAt: occurrence.endAt,
          location: occurrence.location,
          description: `Reguläre Trainingszeit laut Belegungsplan der Saison ${occurrence.seasonName}.`,
          isSeriesException: true,
          targetTeams: { create: [{ teamId: occurrence.teamId }] },
        },
      });
    }),
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
      id: { startsWith: idPrefix },
      startAt: { gte: now },
    },
    orderBy: { startAt: 'asc' },
    select: {
      id: true,
      startAt: true,
      isHiddenRegularOccurrence: true,
      _count: { select: { attendance: true, participants: true } },
    },
  });
  const expected = nextRegularTrainingOccurrence(team, now);
  const visible = materialized.filter(
    (event) => !event.isHiddenRegularOccurrence,
  );
  if (!expected) {
    const hiddenIds = visible.map((event) => event.id);
    if (visible.length > 0) {
      await tx.event.updateMany({
        where: { id: { in: hiddenIds } },
        data: { isHiddenRegularOccurrence: true },
      });
    }
    return hiddenIds;
  }

  // Prefer the occurrence that already contains user data. This protects a
  // response-bearing event even if an earlier software version produced a
  // duplicate. The stable event ID keeps all dependent rows attached.
  const canonical = [...visible].sort((left, right) => {
    const leftData = left._count.attendance + left._count.participants;
    const rightData = right._count.attendance + right._count.participants;
    return rightData - leftData || left.startAt.getTime() - right.startAt.getTime();
  })[0];
  const canonicalId = canonical?.id ??
    `regular-training:${team.id}:${expected.startAt.getTime()}`;
  const expectedTombstone = !canonical
    ? materialized.find(
        (event) =>
          event.id === canonicalId && event.isHiddenRegularOccurrence,
      )
    : undefined;
  // A hidden occurrence is an explicit single-date deletion. Re-creating it
  // would undo the user's exception and can also violate the stable ID's
  // unique constraint. Keep the tombstone authoritative for that date.
  if (expectedTombstone) return [expectedTombstone.id];
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
    await tx.event.update({
      where: { id: canonical.id },
      data: {
        ...eventData,
        targetTeams: {
          deleteMany: {},
          create: [{ teamId: team.id }],
        },
      },
    });
  } else {
    await tx.event.create({
      data: {
        id: canonicalId,
        status: EventStatus.SCHEDULED,
        ...eventData,
        targetTeams: { create: [{ teamId: team.id }] },
      },
    });
  }
  const staleIds = visible
    .map((event) => event.id)
    .filter((id) => id !== canonicalId);
  if (staleIds.length > 0) {
    await tx.event.updateMany({
      where: { id: { in: staleIds } },
      data: { isHiddenRegularOccurrence: true },
    });
  }
  return [canonicalId, ...staleIds];
}
