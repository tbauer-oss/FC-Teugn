import { AccountStatus, HomeAway, Role } from '@prisma/client';
import { prisma } from '../lib/prisma';

const WEEKDAYS = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
] as const;

const COACH_ROLE_PRIORITY: Role[] = [
  Role.COACH,
  Role.TRAINER_ADMIN,
  Role.TRAINER,
  Role.ASSISTANT_COACH,
  Role.TEAM_MANAGER,
];

export const CLUB_MATCH_PITCHES = [
  'Platz 1 unten',
  'Platz 2 oben',
  'Sportplatz Teugn · beide Plätze',
  'Platz noch offen / unklar',
] as const;

type ParsedSlot = {
  raw: string;
  weekday: string;
  startMinute: number;
  endMinute: number;
  pitch: string;
};

export type PitchConflict = {
  kind: 'TEAM' | 'SENIORS' | 'RECREATIONAL';
  requiresApproval: boolean;
  trainingTeamId: string;
  trainingTeamName: string;
  ageGroupCode: string;
  trainingScheduleValue: string;
  weekday: string;
  startMinute: number;
  endMinute: number;
  startLabel: string;
  endLabel: string;
  pitch: string;
  headCoach: {
    id: string;
    name: string;
    phone: string | null;
    email: string;
    role: Role;
  } | null;
};

function normalizedPitch(value: string | null | undefined) {
  return String(value ?? '')
    .trim()
    .toLocaleLowerCase('de-DE')
    .replace(/\s+/g, ' ');
}

function isOpenPitch(value: string) {
  const pitch = normalizedPitch(value);
  return !pitch || pitch.includes('offen') || pitch.includes('unklar');
}

export function requestableEventPitch(
  homeAway: HomeAway | null,
  pitch: string | null | undefined,
) {
  const value = pitch?.trim();
  return homeAway !== HomeAway.AWAY && value && !isOpenPitch(value)
    ? value
    : null;
}

export function pitchesOverlap(left: string, right: string) {
  if (isOpenPitch(left) || isOpenPitch(right)) return false;
  const a = normalizedPitch(left);
  const b = normalizedPitch(right);
  if (a === b) return true;
  const aBoth = a.includes('beide plätze') || a.includes('beide plaetze');
  const bBoth = b.includes('beide plätze') || b.includes('beide plaetze');
  const aTeugn = a.includes('platz 1') || a.includes('platz 2') || a.includes('teugn');
  const bTeugn = b.includes('platz 1') || b.includes('platz 2') || b.includes('teugn');
  return (aBoth && bTeugn) || (bBoth && aTeugn);
}

function minuteLabel(value: number) {
  const hour = Math.floor(value / 60).toString().padStart(2, '0');
  const minute = (value % 60).toString().padStart(2, '0');
  return `${hour}:${minute}`;
}

export function parseTrainingSlot(
  raw: string,
  defaultPitch: string | null,
): ParsedSlot | null {
  const dayMatch = raw.match(
    /(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)/i,
  );
  const timeMatch = raw.match(
    /(\d{1,2}):(\d{2})\s*(?:-|–|—|bis)\s*(\d{1,2}):(\d{2})/i,
  );
  if (!dayMatch || !timeMatch) return null;
  const startMinute = Number(timeMatch[1]) * 60 + Number(timeMatch[2]);
  const endMinute = Number(timeMatch[3]) * 60 + Number(timeMatch[4]);
  if (
    startMinute < 0 ||
    startMinute >= 24 * 60 ||
    endMinute <= startMinute ||
    endMinute > 24 * 60
  ) {
    return null;
  }
  const weekday =
    WEEKDAYS.find(
      (item) =>
        item.toLocaleLowerCase('de-DE') ===
        dayMatch[1].toLocaleLowerCase('de-DE'),
    ) ?? dayMatch[1];
  const pitchMatch = raw.match(
    /(?:·|\|)\s*Platz:\s*(.+?)\s*$/i,
  );
  return {
    raw,
    weekday,
    startMinute,
    endMinute,
    pitch:
      pitchMatch?.[1]?.trim() ||
      defaultPitch?.trim() ||
      'Platz noch offen / unklar',
  };
}

function berlinDateParts(value: Date) {
  const parts = new Intl.DateTimeFormat('de-DE', {
    timeZone: 'Europe/Berlin',
    weekday: 'long',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(value);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((item) => item.type === type)?.value ?? '';
  const rawWeekday = part('weekday');
  const weekday =
    WEEKDAYS.find(
      (item) =>
        item.toLocaleLowerCase('de-DE') === rawWeekday.toLocaleLowerCase('de-DE'),
    ) ?? rawWeekday;
  return {
    weekday,
    minute: Number(part('hour')) * 60 + Number(part('minute')),
  };
}

export async function findPitchConflicts(input: {
  startAt: Date;
  endAt: Date;
  pitch: string;
  targetTeamIds: string[];
}): Promise<PitchConflict[]> {
  if (
    input.endAt <= input.startAt ||
    isOpenPitch(input.pitch) ||
    input.targetTeamIds.length === 0
  ) {
    return [];
  }
  const sourceTeam = await prisma.team.findFirst({
    where: { id: { in: input.targetTeamIds }, deletedAt: null },
    select: {
      ageGroup: {
        select: {
          season: {
            select: {
              id: true,
              seniorTrainingLocation: true,
              seniorTrainingTimes: true,
              recreationalTrainingLocation: true,
              recreationalTrainingTimes: true,
            },
          },
        },
      },
    },
  });
  if (!sourceTeam) return [];
  const season = sourceTeam.ageGroup.season;

  const start = berlinDateParts(input.startAt);
  const end = berlinDateParts(input.endAt);
  const eventEndMinute =
    start.weekday === end.weekday ? end.minute : 24 * 60;
  const teams = await prisma.team.findMany({
    where: {
      deletedAt: null,
      isActive: true,
      ageGroup: { seasonId: season.id },
    },
    select: {
      id: true,
      name: true,
      shortName: true,
      trainingLocation: true,
      trainingTimes: true,
      ageGroup: { select: { code: true } },
      memberships: {
        where: {
          status: AccountStatus.APPROVED,
          role: { in: COACH_ROLE_PRIORITY },
        },
        select: {
          role: true,
          user: {
            select: {
              id: true,
              name: true,
              email: true,
              phone: true,
              status: true,
            },
          },
        },
      },
    },
  });

  const conflicts: PitchConflict[] = [];
  for (const team of teams) {
    const memberships = [...team.memberships].sort(
      (left, right) =>
        COACH_ROLE_PRIORITY.indexOf(left.role) -
        COACH_ROLE_PRIORITY.indexOf(right.role),
    );
    const primary = memberships.find(
      (membership) => membership.user.status === AccountStatus.APPROVED,
    );
    for (const raw of team.trainingTimes) {
      const slot = parseTrainingSlot(raw, team.trainingLocation);
      if (
        !slot ||
        slot.weekday !== start.weekday ||
        !pitchesOverlap(input.pitch, slot.pitch) ||
        start.minute >= slot.endMinute ||
        eventEndMinute <= slot.startMinute
      ) {
        continue;
      }
      conflicts.push({
        kind: 'TEAM',
        requiresApproval: primary != null,
        trainingTeamId: team.id,
        trainingTeamName: team.shortName?.trim() || team.name,
        ageGroupCode: team.ageGroup.code,
        trainingScheduleValue: slot.raw,
        weekday: slot.weekday,
        startMinute: slot.startMinute,
        endMinute: slot.endMinute,
        startLabel: minuteLabel(slot.startMinute),
        endLabel: minuteLabel(slot.endMinute),
        pitch: slot.pitch,
        headCoach: primary
          ? {
              id: primary.user.id,
              name: primary.user.name,
              phone: primary.user.phone,
              email: primary.user.email,
              role: primary.role,
            }
          : null,
      });
    }
  }
  const sharedSchedules = [
    {
      id: `seniors:${season.id}`,
      kind: 'SENIORS' as const,
      name: 'Herren',
      location: season.seniorTrainingLocation,
      values: season.seniorTrainingTimes,
    },
    {
      id: `recreational:${season.id}`,
      kind: 'RECREATIONAL' as const,
      name: 'Freizeitkicker',
      location: season.recreationalTrainingLocation,
      values: season.recreationalTrainingTimes,
    },
  ];
  for (const schedule of sharedSchedules) {
    for (const raw of schedule.values) {
      const slot = parseTrainingSlot(raw, schedule.location);
      if (
        !slot ||
        slot.weekday !== start.weekday ||
        !pitchesOverlap(input.pitch, slot.pitch) ||
        start.minute >= slot.endMinute ||
        eventEndMinute <= slot.startMinute
      ) {
        continue;
      }
      conflicts.push({
        kind: schedule.kind,
        requiresApproval: false,
        trainingTeamId: schedule.id,
        trainingTeamName: schedule.name,
        ageGroupCode: '',
        trainingScheduleValue: slot.raw,
        weekday: slot.weekday,
        startMinute: slot.startMinute,
        endMinute: slot.endMinute,
        startLabel: minuteLabel(slot.startMinute),
        endLabel: minuteLabel(slot.endMinute),
        pitch: slot.pitch,
        headCoach: null,
      });
    }
  }
  return conflicts;
}

export function pitchConflictAction(
  conflict: Pick<PitchConflict, 'kind' | 'requiresApproval' | 'headCoach'>,
) {
  if (conflict.kind === 'RECREATIONAL') {
    return 'INFORM_RECREATIONAL' as const;
  }
  if (conflict.requiresApproval && conflict.headCoach) {
    return 'REQUEST_APPROVAL' as const;
  }
  return 'NONE' as const;
}
