import { randomBytes, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import {
  AccountStatus,
  AttendanceStatus,
  CarpoolRequestStatus,
  EventCategory,
  EventStatus,
  EventType,
  EventVisibility,
  HomeAway,
  NotificationCategory,
  Prisma,
  RecurrenceFrequency,
  Role as PrismaRole,
} from '@prisma/client';
import { openAttendancePlayerIds } from '../services/attendance-summary';
import { prisma } from '../lib/prisma';
import { Role } from '../types/enums';
import { hasPermission, Permission } from '../security/permissions';
import {
  accessibleTeamIds,
  contextualTeamIds,
  youthPlayerPoolTeamIdsForTeam,
} from '../services/team-access';
import { rosterTeamIdsForMatch } from '../services/match-roster';
import { createPitchConflictRequestsForEvent } from './pitch-conflicts.controller';
import {
  fieldSizeForGameFormat,
  syncSquadWithTeamDefaultLineup,
} from '../services/default-lineup.service';
import { syncScheduledRemindersForEvent } from '../services/reminder.service';
import { mediaAssetUrl } from '../services/media-access';
import { notifyUsers } from '../services/notification.service';

const eventInclude = {
  series: true,
  targetTeams: {
    include: {
      team: {
        select: {
          id: true,
          name: true,
          shortName: true,
          ageGroup: { select: { code: true, name: true } },
        },
      },
    },
  },
  participants: {
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          position: true,
          photoUrl: true,
          teamId: true,
        },
      },
      user: { select: { id: true, name: true, role: true } },
    },
  },
  attachments: true,
  attendance: {
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          position: true,
          photoUrl: true,
          teamId: true,
        },
      },
    },
  },
  carpoolOffers: {
    orderBy: { departureAt: 'asc' as const },
    include: {
      driver: { select: { id: true, name: true, phone: true } },
      passengers: {
        include: {
          player: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              preferredName: true,
            },
          },
        },
      },
    },
  },
  matchDetails: {
    include: {
      opponentRecord: {
        include: { logoAsset: { select: { id: true, deletedAt: true } } },
      },
    },
  },
  squads: { include: { members: true } },
} as const;

type CalendarEvent = Prisma.EventGetPayload<{ include: typeof eventInclude }>;

function clean(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function safeHttpUrl(value: unknown) {
  const normalized = clean(value);
  if (!normalized) return null;
  try {
    const parsed = new URL(normalized);
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function validDate(value: unknown) {
  if (!value) return null;
  const result = new Date(String(value));
  return Number.isNaN(result.getTime()) ? null : result;
}

function boundedInt(value: unknown, minimum: number, maximum: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum ? parsed : null;
}

function enumValue<T extends Record<string, string>>(
  values: T,
  value: unknown,
  fallback: T[keyof T],
) {
  const normalized = String(value ?? '').toUpperCase();
  return (Object.values(values) as string[]).includes(normalized)
    ? (normalized as T[keyof T])
    : fallback;
}

function isStaff(role: Role | PrismaRole) {
  return hasPermission(role as Role, Permission.MANAGE_EVENTS);
}

function typeForCategory(category: EventCategory) {
  if (category === EventCategory.TRAINING) return EventType.TRAINING;
  const matchCategories = new Set<EventCategory>([
    EventCategory.LEAGUE_MATCH,
    EventCategory.FRIENDLY_MATCH,
    EventCategory.CUP_MATCH,
    EventCategory.TOURNAMENT,
    EventCategory.INDOOR_TOURNAMENT,
    EventCategory.FOOTBALL_FESTIVAL,
  ]);
  if (matchCategories.has(category)) {
    return EventType.MATCH;
  }
  return EventType.EVENT;
}

function titleForCategory(category: EventCategory) {
  const titles: Record<EventCategory, string> = {
    [EventCategory.TRAINING]: 'Training',
    [EventCategory.LEAGUE_MATCH]: 'Pflichtspiel',
    [EventCategory.FRIENDLY_MATCH]: 'Freundschaftsspiel',
    [EventCategory.CUP_MATCH]: 'Pokalspiel',
    [EventCategory.TOURNAMENT]: 'Turnier',
    [EventCategory.INDOOR_TOURNAMENT]: 'Hallenturnier',
    [EventCategory.FOOTBALL_FESTIVAL]: 'Fußballfestival',
    [EventCategory.TEAM_MEETING]: 'Mannschaftsbesprechung',
    [EventCategory.PARENTS_MEETING]: 'Elternabend',
    [EventCategory.CHRISTMAS_PARTY]: 'Weihnachtsfeier',
    [EventCategory.SEASON_CLOSING]: 'Saisonabschluss',
    [EventCategory.CLUB_EVENT]: 'Vereinsveranstaltung',
    [EventCategory.TRIP]: 'Ausflug',
    [EventCategory.PHOTO_SESSION]: 'Fototermin',
    [EventCategory.SPECIAL_EVENT]: 'Sonderveranstaltung',
  };
  return titles[category];
}

function eventScope(teamIds: string[]): Prisma.EventWhereInput {
  return {
    OR: [{ teamId: { in: teamIds } }, { targetTeams: { some: { teamId: { in: teamIds } } } }],
  };
}

async function ownPlayerIds(userId: string, role: Role | PrismaRole) {
  if (role === Role.PARENT) {
    const links = await prisma.parentPlayerLink.findMany({
      where: { parentId: userId },
      select: { playerId: true },
    });
    return links.map((link) => link.playerId);
  }
  if (role === Role.PLAYER) {
    const player = await prisma.player.findUnique({
      where: { userId },
      select: { id: true },
    });
    return player ? [player.id] : [];
  }
  return [];
}

function targetIdsForEvent(event: {
  teamId: string;
  targetTeams: Array<{ teamId: string }>;
}) {
  return event.targetTeams.length
    ? event.targetTeams.map((target) => target.teamId)
    : [event.teamId];
}

async function canManageEvent(
  user: { id: string; teamId: string; role: Role | PrismaRole },
  event: { teamId: string; targetTeams: Array<{ teamId: string }> },
) {
  const teamIds = await accessibleTeamIds(user);
  return canManageEventWithIds(user, event, teamIds);
}

function canManageEventWithIds(
  user: { role: Role | PrismaRole },
  event: { teamId: string; targetTeams: Array<{ teamId: string }> },
  teamIds: string[],
) {
  if (!isStaff(user.role)) return false;
  if (hasPermission(user.role as Role, Permission.MANAGE_ORGANIZATION)) {
    return true;
  }
  return targetIdsForEvent(event).every((teamId) => teamIds.includes(teamId));
}

async function rosterForTeamIds(teamIds: string[]) {
  return prisma.player.findMany({
    where: { teamId: { in: teamIds }, status: 'ACTIVE' },
    select: {
      id: true,
      firstName: true,
      lastName: true,
      preferredName: true,
      position: true,
      photoUrl: true,
      teamId: true,
    },
    orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
  });
}

type RosterPlayer = Awaited<ReturnType<typeof rosterForTeamIds>>[number];

async function rosterForEvent(event: CalendarEvent, accessibleIds: string[]) {
  const explicit = event.participants
    .filter((participant) => participant.responseRequired && participant.player)
    .map((participant) => participant.player!);
  if (explicit.length) {
    return explicit.filter(
      (player) => player.teamId !== null && accessibleIds.includes(player.teamId),
    );
  }
  const teamIds = targetIdsForEvent(event).filter((id) =>
    accessibleIds.includes(id),
  );
  return rosterForTeamIds(teamIds);
}

async function serializeEvent(
  event: CalendarEvent,
  user: { id: string; teamId: string; role: Role | PrismaRole },
  knownAccessibleIds?: string[],
  knownRoster?: RosterPlayer[],
) {
  const staff = isStaff(user.role);
  const accessibleIds = knownAccessibleIds ?? (await accessibleTeamIds(user));
  const manageable = canManageEventWithIds(user, event, accessibleIds);
  const personalPlayerIds = staff ? [] : await ownPlayerIds(user.id, user.role);
  const eventTargetIds = targetIdsForEvent(event);
  const explicitParticipantPlayers = event.participants
    .filter((participant) => participant.responseRequired && participant.player)
    .map((participant) => participant.player!);
  const roster = staff
    ? knownRoster
      ? knownRoster.filter(
          (player) =>
            player.teamId !== null &&
            eventTargetIds.includes(player.teamId) &&
            (!explicitParticipantPlayers.length ||
              explicitParticipantPlayers.some((item) => item.id === player.id)),
        )
      : await rosterForEvent(event, accessibleIds)
    : [];
  const visibleAttendance = staff
    ? event.attendance.filter((reply) =>
        reply.player.teamId !== null &&
        accessibleIds.includes(reply.player.teamId),
      )
    : event.attendance.filter((reply) => personalPlayerIds.includes(reply.playerId));
  const openPlayerIds = new Set(
    openAttendancePlayerIds(
      roster.map((player) => player.id),
      visibleAttendance,
    ),
  );
  const summary = {
    yes: visibleAttendance.filter((reply) => reply.status === AttendanceStatus.YES).length,
    no: visibleAttendance.filter((reply) => reply.status === AttendanceStatus.NO).length,
    maybe: visibleAttendance.filter((reply) => reply.status === AttendanceStatus.MAYBE).length,
    unknown: staff ? openPlayerIds.size : 0,
    goalkeeperAvailable: visibleAttendance.filter(
      (reply) =>
        reply.status === AttendanceStatus.YES &&
        (reply.goalkeeperAvailable === true ||
          reply.player.position?.toLowerCase().includes('tor')),
    ).length,
  };
  const ownPassengerOfferIds = new Set(
    event.carpoolOffers
      .filter(
        (offer) =>
          offer.driverId === user.id ||
          offer.passengers.some(
            (passenger) =>
              personalPlayerIds.includes(passenger.playerId) &&
              passenger.status !== CarpoolRequestStatus.CANCELLED,
          ),
      )
      .map((offer) => offer.id),
  );

  return {
    ...event,
    matchDetails: event.matchDetails
      ? {
          ...event.matchDetails,
          opponentRecord: undefined,
          opponentLogoUrl:
            event.matchDetails.opponentRecord?.logoAsset &&
            event.matchDetails.opponentRecord.logoAsset.deletedAt === null
              ? mediaAssetUrl(event.matchDetails.opponentRecord.logoAsset.id, '12h')
              : event.matchDetails.opponentLogoUrl,
        }
      : null,
    internalNote: staff ? event.internalNote : undefined,
    attendance: visibleAttendance,
    participants: staff
      ? event.participants
      : event.participants.filter((participant) =>
          participant.playerId
            ? personalPlayerIds.includes(participant.playerId)
            : participant.userId === user.id,
        ),
    attendanceSummary: summary,
    missingAttendance: staff
      ? roster.filter((player) => openPlayerIds.has(player.id))
      : undefined,
    carpoolOffers: event.carpoolOffers.map((offer) => ({
      ...offer,
      driver: {
        ...offer.driver,
        phone:
          manageable || offer.driverId === user.id || ownPassengerOfferIds.has(offer.id)
            ? offer.driver.phone
            : undefined,
      },
      freeSeats:
        offer.seatsTotal -
        offer.passengers.filter((passenger) => passenger.status === CarpoolRequestStatus.CONFIRMED)
          .length,
      passengers: manageable || offer.driverId === user.id
        ? offer.passengers
        : offer.passengers.filter((passenger) =>
            personalPlayerIds.includes(passenger.playerId),
          ),
      canManage: manageable || offer.driverId === user.id,
    })),
    capabilities: {
      canManage: manageable,
      canRespond: hasPermission(user.role as Role, Permission.RESPOND_ATTENDANCE),
      canOfferRide: user.role !== Role.READ_ONLY,
      canOpenEmergencyView:
        hasPermission(user.role as Role, Permission.VIEW_SENSITIVE_PLAYER) &&
        eventTargetIds.every((teamId) => accessibleIds.includes(teamId)),
    },
  };
}

function parseStringList(value: unknown) {
  return Array.isArray(value)
    ? value.map(clean).filter((item): item is string => Boolean(item))
    : [];
}

async function validatedParticipants(
  teamIds: string[],
  playerValue: unknown,
  userValue: unknown,
) {
  const playerIds = [...new Set(parseStringList(playerValue))];
  const userIds = [...new Set(parseStringList(userValue))];
  const [players, users] = await Promise.all([
    playerIds.length
      ? prisma.player.findMany({
          where: { id: { in: playerIds }, teamId: { in: teamIds }, status: 'ACTIVE' },
          select: { id: true },
        })
      : Promise.resolve([]),
    userIds.length
      ? prisma.user.findMany({
          where: {
            id: { in: userIds },
            status: AccountStatus.APPROVED,
            OR: [
              { teamId: { in: teamIds } },
              { memberships: { some: { teamId: { in: teamIds }, status: AccountStatus.APPROVED } } },
            ],
          },
          select: { id: true },
        })
      : Promise.resolve([]),
  ]);
  return players.length === playerIds.length && users.length === userIds.length
    ? { playerIds, userIds }
    : null;
}

async function syncEventParticipants(
  tx: Prisma.TransactionClient,
  eventId: string,
  participants: { playerIds: string[]; userIds: string[] },
) {
  await tx.eventParticipant.deleteMany({ where: { eventId } });
  await tx.attendance.deleteMany({
    where: { eventId, playerId: { notIn: participants.playerIds } },
  });
  if (participants.playerIds.length || participants.userIds.length) {
    await tx.eventParticipant.createMany({
      data: [
        ...participants.playerIds.map((playerId) => ({
          eventId,
          playerId,
          responseRequired: true,
        })),
        ...participants.userIds.map((userId) => ({
          eventId,
          userId,
          responseRequired: false,
        })),
      ],
      skipDuplicates: true,
    });
  }
  for (const playerId of participants.playerIds) {
    await tx.attendance.upsert({
      where: { eventId_playerId: { eventId, playerId } },
      update: {},
      create: { eventId, playerId, status: AttendanceStatus.UNKNOWN },
    });
  }
}

function eventData(body: Record<string, unknown>) {
  const category = enumValue(
    EventCategory,
    body.category,
    body.type === 'TRAINING'
      ? EventCategory.TRAINING
      : body.type === 'MATCH'
        ? EventCategory.LEAGUE_MATCH
        : EventCategory.SPECIAL_EVENT,
  );
  return {
    type: typeForCategory(category),
    category,
    status: enumValue(EventStatus, body.status, EventStatus.SCHEDULED),
    visibility: enumValue(EventVisibility, body.visibility, EventVisibility.TEAM),
    title: clean(body.title) ?? titleForCategory(category),
    startAt: validDate(body.startAt),
    endAt: validDate(body.endAt),
    meetingAt: validDate(body.meetingAt),
    location: clean(body.location),
    address: clean(body.address),
    mapUrl: safeHttpUrl(body.mapUrl),
    homeAway: body.homeAway
      ? enumValue(HomeAway, body.homeAway, HomeAway.NEUTRAL)
      : null,
    opponent: clean(body.opponent),
    venue: clean(body.venue),
    contactName: clean(body.contactName),
    contactPhone: clean(body.contactPhone),
    description: clean(body.description),
    equipment: clean(body.equipment),
    clothing: clean(body.clothing),
    catering: clean(body.catering),
    carpoolRequired: body.carpoolRequired === true,
    maxParticipants: body.maxParticipants
      ? boundedInt(body.maxParticipants, 1, 500)
      : null,
    responseDeadline: validDate(body.responseDeadline),
    internalNote: clean(body.internalNote),
    reminderMinutes: Array.isArray(body.reminderMinutes)
      ? body.reminderMinutes
          .map((value) => boundedInt(value, 0, 10080))
          .filter((value): value is number => value !== null)
      : [],
  };
}

async function activeSeasonEndForTeams(teamIds: string[]) {
  const teams = await prisma.team.findMany({
    where: { id: { in: teamIds } },
    select: {
      ageGroup: {
        select: {
          season: { select: { endDate: true } },
        },
      },
    },
  });
  if (teams.length !== teamIds.length) return null;
  const earliest = teams
    .map((team) => team.ageGroup.season.endDate)
    .sort((left, right) => left.getTime() - right.getTime())[0];
  if (!earliest) return null;
  const inclusive = new Date(earliest);
  inclusive.setUTCHours(23, 59, 59, 999);
  return inclusive;
}

function matchTiming(
  body: Record<string, unknown>,
  fallback?: { periodCount: number; periodMinutes: number },
) {
  const periodCount =
    body.periodCount == null
      ? fallback?.periodCount ?? 2
      : boundedInt(body.periodCount, 1, 8);
  const periodMinutes =
    body.periodMinutes == null
      ? fallback?.periodMinutes ?? 30
      : boundedInt(body.periodMinutes, 1, 90);
  if (
    periodCount == null ||
    periodMinutes == null ||
    periodCount * periodMinutes > 180
  ) {
    return null;
  }
  return {
    periodCount,
    periodMinutes,
    durationMinutes: periodCount * periodMinutes,
  };
}

export function generateOccurrences(
  startAt: Date,
  until: Date,
  frequency: RecurrenceFrequency,
  interval: number,
  weekdays: number[],
) {
  const dates: Date[] = [];
  const maximumUntil = new Date(startAt);
  maximumUntil.setUTCFullYear(maximumUntil.getUTCFullYear() + 2);
  const safeUntil = until < maximumUntil ? until : maximumUntil;
  const normalizedInterval = Math.max(1, Math.min(interval, 12));

  if (frequency !== RecurrenceFrequency.CUSTOM) {
    const step = frequency === RecurrenceFrequency.BIWEEKLY ? 14 : 7 * normalizedInterval;
    for (
      let current = new Date(startAt);
      current <= safeUntil && dates.length < 120;
      current = new Date(current.getTime() + step * 86400000)
    ) {
      dates.push(current);
    }
    return dates;
  }

  const selectedDays = new Set(weekdays.filter((day) => day >= 1 && day <= 7));
  if (selectedDays.size === 0) {
    selectedDays.add(startAt.getUTCDay() === 0 ? 7 : startAt.getUTCDay());
  }
  const startMidnight = Date.UTC(
    startAt.getUTCFullYear(),
    startAt.getUTCMonth(),
    startAt.getUTCDate(),
  );
  for (
    let current = new Date(startAt);
    current <= safeUntil && dates.length < 120;
    current = new Date(current.getTime() + 86400000)
  ) {
    const elapsedDays = Math.floor(
      (Date.UTC(current.getUTCFullYear(), current.getUTCMonth(), current.getUTCDate()) -
        startMidnight) /
        86400000,
    );
    const week = Math.floor(elapsedDays / 7);
    const weekday = current.getUTCDay() === 0 ? 7 : current.getUTCDay();
    if (week % normalizedInterval === 0 && selectedDays.has(weekday)) {
      dates.push(current);
    }
  }
  return dates;
}

async function validatedTargetTeams(
  req: Request,
  requested: unknown,
  fallbackTeamId: string,
) {
  const allowed = await accessibleTeamIds(req.user!);
  const requestedIds = parseStringList(requested);
  const ids = requestedIds.length ? [...new Set(requestedIds)] : [fallbackTeamId];
  return ids.length > 0 && ids.every((id) => allowed.includes(id)) ? ids : null;
}

export async function listEvents(req: Request, res: Response) {
  const user = req.user!;
  const accessibleIds = await accessibleTeamIds(user);
  const teamIds = await contextualTeamIds(user);
  const from = validDate(req.query.from);
  const to = validDate(req.query.to);
  const requestedTeams = parseStringList(
    typeof req.query.teamIds === 'string' ? req.query.teamIds.split(',') : req.query.teamIds,
  );
  const effectiveTeams = requestedTeams.length
    ? requestedTeams.filter((id) => accessibleIds.includes(id))
    : teamIds;
  const categories = parseStringList(
    typeof req.query.categories === 'string'
      ? req.query.categories.split(',')
      : req.query.categories,
  ).filter((value) => Object.values(EventCategory).includes(value as EventCategory));

  const events = await prisma.event.findMany({
    where: {
      ...eventScope(effectiveTeams),
      ...(from || to
        ? {
            startAt: {
              ...(from ? { gte: from } : {}),
              ...(to ? { lte: to } : {}),
            },
          }
        : {}),
      ...(categories.length ? { category: { in: categories as EventCategory[] } } : {}),
      ...(!isStaff(user.role) ? { visibility: { not: EventVisibility.STAFF_ONLY } } : {}),
    },
    orderBy: { startAt: 'asc' },
    include: eventInclude,
  });
  const roster = isStaff(user.role) ? await rosterForTeamIds(effectiveTeams) : undefined;
  return res.json(
    await Promise.all(
      events.map((event) => serializeEvent(event, user, accessibleIds, roster)),
    ),
  );
}

export async function getEvent(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: {
      id: req.params.id,
      ...eventScope(teamIds),
      ...(!isStaff(user.role) ? { visibility: { not: EventVisibility.STAFF_ONLY } } : {}),
    },
    include: eventInclude,
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  return res.json(await serializeEvent(event, user, teamIds));
}

export async function createEvent(req: Request, res: Response) {
  const user = req.user!;
  const data = eventData(req.body);
  if (!data.startAt || !data.location) {
    return res.status(400).json({ message: 'Beginn und Ort sind erforderlich.' });
  }
  if (data.endAt && data.endAt < data.startAt) {
    return res.status(400).json({ message: 'Das Ende darf nicht vor dem Beginn liegen.' });
  }
  const timing = data.type === EventType.MATCH ? matchTiming(req.body) : null;
  if (data.type === EventType.MATCH && !timing) {
    return res.status(400).json({
      message:
        'Bitte 1–8 Spielabschnitte und 1–90 Minuten je Abschnitt angeben (maximal 180 Minuten insgesamt).',
    });
  }
  let teamIds = await validatedTargetTeams(req, req.body.teamIds, user.teamId);
  if (data.visibility === EventVisibility.CLUB) {
    if (!hasPermission(user.role, Permission.MANAGE_ORGANIZATION)) {
      return res.status(403).json({
        message: 'Vereinsweite Termine dürfen nur von der Vereinsleitung angelegt werden.',
      });
    }
    teamIds = await accessibleTeamIds(user);
  }
  if (!teamIds) {
    return res.status(403).json({ message: 'Mindestens eine erlaubte Mannschaft auswählen.' });
  }
  const participants = await validatedParticipants(
    teamIds,
    req.body.participantPlayerIds,
    req.body.participantUserIds,
  );
  if (!participants) {
    return res.status(400).json({
      message: 'Mindestens eine ausgewählte Person gehört nicht zum Terminkontext.',
    });
  }
  const hasExplicitParticipants =
    Object.prototype.hasOwnProperty.call(req.body, 'participantPlayerIds') ||
    Object.prototype.hasOwnProperty.call(req.body, 'participantUserIds');
  const opponentRecord = data.type === EventType.MATCH && req.body.opponentId
    ? await prisma.opponent.findFirst({
        where: {
          id: String(req.body.opponentId),
          archivedAt: null,
          ageGroup: { teams: { some: { id: { in: teamIds } } } },
        },
        select: { id: true },
      })
    : null;
  const attachments: Array<{
    name: string;
    url: string;
    mimeType: string | null;
  }> = Array.isArray(req.body.attachments)
    ? req.body.attachments
        .map((value: unknown) => {
          const item = value as Record<string, unknown>;
          const name = clean(item.name);
          const url = safeHttpUrl(item.url);
          return name && url ? { name, url, mimeType: clean(item.mimeType) } : null;
        })
        .filter(
          (
            item: { name: string; url: string; mimeType: string | null } | null,
          ): item is { name: string; url: string; mimeType: string | null } => Boolean(item),
        )
    : [];
  const recurrence = req.body.recurrence as Record<string, unknown> | undefined;
  let recurrenceUntil = validDate(recurrence?.until);
  const frequency = recurrence
    ? enumValue(
        RecurrenceFrequency,
        recurrence.frequency,
        RecurrenceFrequency.WEEKLY,
      )
    : null;
  const interval = boundedInt(recurrence?.interval, 1, 12) ?? 1;
  const weekdays = Array.isArray(recurrence?.weekdays)
    ? recurrence.weekdays
        .map((value) => boundedInt(value, 1, 7))
        .filter((value): value is number => value !== null)
    : [];
  if (recurrence && data.category === EventCategory.TRAINING) {
    recurrenceUntil = await activeSeasonEndForTeams(teamIds);
    if (!recurrenceUntil) {
      return res.status(400).json({
        message: 'Für die ausgewählten Mannschaften wurde kein Saisonende gefunden.',
      });
    }
  }
  if (recurrence && (!recurrenceUntil || recurrenceUntil < data.startAt)) {
    return res.status(400).json({
      message: data.category === EventCategory.TRAINING
        ? 'Der Trainingsbeginn liegt nach dem Ende der Saison.'
        : 'Für die Serie ist ein gültiges Enddatum nötig.',
    });
  }

  const starts =
    frequency && recurrenceUntil
      ? generateOccurrences(data.startAt, recurrenceUntil, frequency, interval, weekdays)
      : [data.startAt];
  if (starts.length === 0) {
    return res.status(400).json({
      message:
        'In diesem Zeitraum liegt kein Termin auf den ausgewählten Wochentagen.',
    });
  }
  const duration = data.endAt ? data.endAt.getTime() - data.startAt.getTime() : null;
  const meetingOffset = data.meetingAt
    ? data.meetingAt.getTime() - data.startAt.getTime()
    : null;
  const safeData = {
    ...data,
    title: data.title,
    startAt: data.startAt,
    location: data.location,
  };

  const createdIds = await prisma.$transaction(async (tx) => {
    const series =
      frequency && recurrenceUntil
        ? await tx.eventSeries.create({
            data: {
              teamId: teamIds[0],
              createdById: user.id,
              frequency,
              interval,
              weekdays,
              until: recurrenceUntil,
            },
          })
        : null;
    const events: Prisma.EventCreateManyInput[] = starts.map((startAt) => ({
      ...safeData,
      id: randomUUID(),
      teamId: teamIds[0],
      seriesId: series?.id ?? null,
      title: data.title!,
      startAt,
      location: data.location!,
      endAt: duration === null ? null : new Date(startAt.getTime() + duration),
      meetingAt:
        meetingOffset === null ? null : new Date(startAt.getTime() + meetingOffset),
    }));
    await tx.event.createMany({ data: events });
    await tx.eventTargetTeam.createMany({
      data: events.flatMap((event) =>
        teamIds.map((teamId) => ({
          eventId: event.id!,
          teamId,
        })),
      ),
    });
    if (hasExplicitParticipants) {
      await tx.eventParticipant.createMany({
        data: events.flatMap((event) => [
          ...participants.playerIds.map((playerId) => ({
            eventId: event.id!,
            playerId,
            responseRequired: true,
          })),
          ...participants.userIds.map((userId) => ({
            eventId: event.id!,
            userId,
            responseRequired: false,
          })),
        ]),
        skipDuplicates: true,
      });
      if (participants.playerIds.length) {
        await tx.attendance.createMany({
          data: events.flatMap((event) =>
            participants.playerIds.map((playerId) => ({
              eventId: event.id!,
              playerId,
              status: AttendanceStatus.UNKNOWN,
            })),
          ),
          skipDuplicates: true,
        });
      }
    }
    if (attachments.length > 0) {
      await tx.eventAttachment.createMany({
        data: events.flatMap((event) =>
          attachments.map((attachment) => ({
            eventId: event.id!,
            ...attachment,
          })),
        ),
      });
    }
    if (data.type === EventType.MATCH && timing) {
      await tx.matchDetails.createMany({
        data: events.map((event) => ({
          eventId: event.id!,
          opponent: data.opponent ?? 'Unbekannt',
          opponentId: opponentRecord?.id,
          isHome: data.homeAway !== HomeAway.AWAY,
          pitch: data.venue,
          ...timing,
        })),
      });
    }
    const ids = events.map((event) => event.id!);
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: teamIds[0],
        action: series ? 'EVENT_SERIES_CREATED' : 'EVENT_CREATED',
        entityType: series ? 'EventSeries' : 'Event',
        entityId: series?.id ?? ids[0],
        metadata: {
          eventIds: ids,
          occurrences: ids.length,
          teamIds,
          participantPlayerIds: participants.playerIds,
          participantUserIds: participants.userIds,
        },
      },
    });
    return ids;
  });

  const created = await prisma.event.findMany({
    where: { id: { in: createdIds } },
    orderBy: { startAt: 'asc' },
    include: eventInclude,
  });
  await Promise.all(createdIds.map(syncScheduledRemindersForEvent));
  await Promise.all(
    createdIds.map((eventId) =>
      createPitchConflictRequestsForEvent({
        eventId,
        requesterId: user.id,
        requestApprovals: req.body.requestPitchConflictApprovals === true,
        message: clean(req.body.pitchConflictMessage),
      }),
    ),
  );
  const accessibleIds = await accessibleTeamIds(user);
  const roster = isStaff(user.role)
    ? await rosterForTeamIds(accessibleIds)
    : undefined;
  const result = await Promise.all(
    created.map((event) =>
      serializeEvent(event, user, accessibleIds, roster),
    ),
  );
  return res.status(201).json(result.length === 1 ? result[0] : result);
}

export async function updateEvent(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const existing = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: eventInclude,
  });
  if (!existing) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, existing))) {
    return res.status(403).json({
      message: 'Gemeinsame Termine dürfen nur für vollständig zugeordnete Mannschaften geändert werden.',
    });
  }
  const scope = req.query.scope === 'series' ? 'series' : 'single';
  const parsed = eventData({ ...existing, ...req.body });
  if (!parsed.startAt || !parsed.location) {
    return res.status(400).json({ message: 'Beginn und Ort sind erforderlich.' });
  }
  if (parsed.endAt && parsed.endAt < parsed.startAt) {
    return res.status(400).json({ message: 'Das Ende darf nicht vor dem Beginn liegen.' });
  }
  const timing =
    parsed.type === EventType.MATCH
      ? matchTiming(req.body, existing.matchDetails ?? undefined)
      : null;
  if (parsed.type === EventType.MATCH && !timing) {
    return res.status(400).json({
      message:
        'Bitte 1–8 Spielabschnitte und 1–90 Minuten je Abschnitt angeben (maximal 180 Minuten insgesamt).',
    });
  }
  const targetTeamIds = await validatedTargetTeams(
    req,
    req.body.teamIds ?? existing.targetTeams.map((target) => target.teamId),
    existing.teamId,
  );
  if (!targetTeamIds) return res.status(403).json({ message: 'Mannschaft nicht erlaubt.' });
  const participantSelectionProvided =
    Object.prototype.hasOwnProperty.call(req.body, 'participantPlayerIds') ||
    Object.prototype.hasOwnProperty.call(req.body, 'participantUserIds');
  const participants = participantSelectionProvided
    ? await validatedParticipants(
        targetTeamIds,
        req.body.participantPlayerIds,
        req.body.participantUserIds,
      )
    : null;
  if (participantSelectionProvided && !participants) {
    return res.status(400).json({
      message: 'Mindestens eine ausgewählte Person gehört nicht zum Terminkontext.',
    });
  }
  const opponentRecord = parsed.type === EventType.MATCH && req.body.opponentId
    ? await prisma.opponent.findFirst({
        where: {
          id: String(req.body.opponentId),
          archivedAt: null,
          ageGroup: { teams: { some: { id: { in: targetTeamIds } } } },
        },
        select: { id: true },
      })
    : null;
  const updateStartAt = parsed.startAt;
  const updateEndAt = parsed.endAt;
  const baseUpdate = {
    ...parsed,
    title: parsed.title,
    startAt: updateStartAt,
    location: parsed.location,
  };

  await prisma.$transaction(async (tx) => {
    if (scope === 'series' && existing.seriesId) {
      const delta = updateStartAt.getTime() - existing.startAt.getTime();
      const duration = updateEndAt
        ? updateEndAt.getTime() - updateStartAt.getTime()
        : null;
      const meetingOffset = parsed.meetingAt
        ? parsed.meetingAt.getTime() - updateStartAt.getTime()
        : null;
      const deadlineOffset = parsed.responseDeadline
        ? parsed.responseDeadline.getTime() - updateStartAt.getTime()
        : null;
      const future = await tx.event.findMany({
        where: {
          seriesId: existing.seriesId,
          startAt: { gte: existing.startAt },
          isSeriesException: false,
        },
      });
      for (const occurrence of future) {
        const startAt = new Date(occurrence.startAt.getTime() + delta);
        await tx.event.update({
          where: { id: occurrence.id },
          data: {
            ...baseUpdate,
            startAt,
            endAt: duration === null ? null : new Date(startAt.getTime() + duration),
            meetingAt:
              meetingOffset === null ? null : new Date(startAt.getTime() + meetingOffset),
            responseDeadline:
              deadlineOffset === null
                ? null
                : new Date(startAt.getTime() + deadlineOffset),
            teamId: targetTeamIds[0],
            targetTeams: {
              deleteMany: {},
              create: targetTeamIds.map((teamId) => ({ teamId })),
            },
          },
        });
        if (participants) {
          await syncEventParticipants(tx, occurrence.id, participants);
        }
        if (parsed.type === EventType.MATCH && timing) {
          await tx.matchDetails.upsert({
            where: { eventId: occurrence.id },
            update: {
              opponent: parsed.opponent ?? 'Unbekannt',
              opponentId: opponentRecord?.id ?? null,
              isHome: parsed.homeAway !== HomeAway.AWAY,
              pitch: parsed.venue,
              ...timing,
            },
            create: {
              eventId: occurrence.id,
              opponent: parsed.opponent ?? 'Unbekannt',
              opponentId: opponentRecord?.id ?? null,
              isHome: parsed.homeAway !== HomeAway.AWAY,
              pitch: parsed.venue,
              ...timing,
            },
          });
        }
      }
    } else {
      await tx.event.update({
        where: { id: existing.id },
        data: {
          ...baseUpdate,
          teamId: targetTeamIds[0],
          isSeriesException: Boolean(existing.seriesId),
          targetTeams: {
            deleteMany: {},
            create: targetTeamIds.map((teamId) => ({ teamId })),
          },
        },
      });
      if (participants) {
        await syncEventParticipants(tx, existing.id, participants);
      }
      if (parsed.type === EventType.MATCH && timing) {
        await tx.matchDetails.upsert({
          where: { eventId: existing.id },
          update: {
            opponent: parsed.opponent ?? 'Unbekannt',
            opponentId: opponentRecord?.id ?? null,
            isHome: parsed.homeAway !== HomeAway.AWAY,
            pitch: parsed.venue,
            ...timing,
          },
          create: {
            eventId: existing.id,
            opponent: parsed.opponent ?? 'Unbekannt',
            opponentId: opponentRecord?.id ?? null,
            isHome: parsed.homeAway !== HomeAway.AWAY,
            pitch: parsed.venue,
            ...timing,
          },
        });
      }
    }
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: existing.teamId,
        action: scope === 'series' ? 'EVENT_SERIES_UPDATED' : 'EVENT_UPDATED',
        entityType: 'Event',
        entityId: existing.id,
        metadata: { scope, seriesId: existing.seriesId, teamIds: targetTeamIds },
      },
    });
  });
  const reminderEventIds = scope === 'series' && existing.seriesId
    ? await prisma.event.findMany({
        where: { seriesId: existing.seriesId, startAt: { gte: existing.startAt } },
        select: { id: true },
      }).then((events) => events.map((event) => event.id))
    : [existing.id];
  await Promise.all(reminderEventIds.map(syncScheduledRemindersForEvent));
  await createPitchConflictRequestsForEvent({
    eventId: existing.id,
    requesterId: user.id,
    requestApprovals: req.body.requestPitchConflictApprovals === true,
    message: clean(req.body.pitchConflictMessage),
  });
  return getEvent(req, res);
}

export async function deleteEvent(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const existing = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: { targetTeams: true },
  });
  if (!existing) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, existing))) {
    return res.status(403).json({ message: 'Keine Berechtigung für die vollständige Termingruppe.' });
  }
  const scope = req.query.scope === 'series' ? 'series' : 'single';
  const permanent = req.query.permanent === 'true';
  if (permanent) {
    if (user.role !== Role.SUPER_ADMIN) {
      return res.status(403).json({
        message: 'Nur die Systemadministration darf Termine und Spiele endgültig löschen.',
      });
    }
    const deleted = await prisma.$transaction(async (tx) => {
      const events = await tx.event.findMany({
        where:
          scope === 'series' && existing.seriesId
            ? {
                seriesId: existing.seriesId,
                startAt: { gte: existing.startAt },
              }
            : { id: existing.id },
        select: { id: true, type: true, title: true },
      });
      await tx.notification.deleteMany({
        where: {
          entityType: 'RecreationalPitchPriority',
          entityId: { in: events.map((event) => event.id) },
        },
      });
      await tx.event.deleteMany({
        where: { id: { in: events.map((event) => event.id) } },
      });
      if (scope === 'series' && existing.seriesId) {
        const remaining = await tx.event.count({
          where: { seriesId: existing.seriesId },
        });
        if (remaining === 0) {
          await tx.eventSeries.delete({
            where: { id: existing.seriesId },
          });
        }
      }
      await tx.auditLog.create({
        data: {
          actorId: user.id,
          teamId: existing.teamId,
          action:
            scope === 'series'
              ? 'EVENT_SERIES_PERMANENTLY_DELETED'
              : existing.type === EventType.MATCH
                ? 'MATCH_PERMANENTLY_DELETED'
                : 'EVENT_PERMANENTLY_DELETED',
          entityType: existing.type === EventType.MATCH ? 'Match' : 'Event',
          entityId: existing.id,
          metadata: {
            scope,
            seriesId: existing.seriesId,
            deletedEvents: events,
          },
        },
      });
      return events;
    });
    return res.json({
      status: 'DELETED',
      scope,
      deletedCount: deleted.length,
    });
  }
  const reason = clean(req.body?.reason) ?? 'Abgesagt';
  const now = new Date();
  await prisma.$transaction(async (tx) => {
    const affectedEvents = await tx.event.findMany({
      where:
        scope === 'series' && existing.seriesId
          ? { seriesId: existing.seriesId, startAt: { gte: existing.startAt } }
          : { id: existing.id },
      select: { id: true },
    });
    await tx.notification.deleteMany({
      where: {
        entityType: 'RecreationalPitchPriority',
        entityId: { in: affectedEvents.map((event) => event.id) },
      },
    });
    if (scope === 'series' && existing.seriesId) {
      await tx.event.updateMany({
        where: { seriesId: existing.seriesId, startAt: { gte: existing.startAt } },
        data: {
          status: EventStatus.CANCELLED,
          cancellationReason: reason,
          cancelledAt: now,
        },
      });
    } else {
      await tx.event.update({
        where: { id: existing.id },
        data: {
          status: EventStatus.CANCELLED,
          cancellationReason: reason,
          cancelledAt: now,
          isSeriesException: Boolean(existing.seriesId),
        },
      });
    }
    await tx.pitchConflictRequest.updateMany({
      where: {
        status: 'PENDING',
        ...(scope === 'series' && existing.seriesId
          ? {
              event: {
                seriesId: existing.seriesId,
                startAt: { gte: existing.startAt },
              },
            }
          : { eventId: existing.id }),
      },
      data: { status: 'CANCELLED' },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: existing.teamId,
        action: scope === 'series' ? 'EVENT_SERIES_CANCELLED' : 'EVENT_CANCELLED',
        entityType: 'Event',
        entityId: existing.id,
        metadata: { scope, reason, seriesId: existing.seriesId },
      },
    });
  });
  await prisma.scheduledReminder.updateMany({
    where: {
      ...(scope === 'series' && existing.seriesId
        ? { event: { seriesId: existing.seriesId, startAt: { gte: existing.startAt } } }
        : { eventId: existing.id }),
      status: { in: ['SCHEDULED', 'FAILED', 'PROCESSING'] },
    },
    data: { status: 'CANCELLED', cancelledAt: now },
  });
  return res.json({ status: EventStatus.CANCELLED, scope });
}

export async function setAttendance(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const playerId = clean(req.body.playerId);
  if (!playerId) return res.status(400).json({ message: 'Spieler fehlt.' });
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, status: EventStatus.SCHEDULED, ...eventScope(teamIds) },
    include: { targetTeams: true, attendance: true, participants: true },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden oder abgesagt.' });
  if (event.attendanceFinalized) {
    return res.status(409).json({ message: 'Die Rückmeldungen wurden bereits abgeschlossen.' });
  }
  if (
    !isStaff(user.role) &&
    event.responseDeadline &&
    event.responseDeadline < new Date()
  ) {
    return res.status(409).json({
      message: 'Die Rückmeldefrist ist abgelaufen. Bitte das Trainerteam kontaktieren.',
    });
  }
  const eventTeamIds = event.targetTeams.length
    ? event.targetTeams.map((target) => target.teamId)
    : [event.teamId];
  const attendanceTeamIds = event.type === EventType.MATCH
    ? rosterTeamIdsForMatch(await youthPlayerPoolTeamIdsForTeam(event.teamId))
    : eventTeamIds;
  const requestedPlayerIds = event.participants
    .filter((participant) => participant.responseRequired && participant.playerId)
    .map((participant) => participant.playerId!);
  if (event.participants.length && !requestedPlayerIds.includes(playerId)) {
    return res.status(403).json({
      message: 'Für diesen Spieler wurde keine Rückmeldung angefragt.',
    });
  }
  const player = await prisma.player.findFirst({
    where: { id: playerId, teamId: { in: attendanceTeamIds } },
  });
  if (!player) return res.status(404).json({ message: 'Spieler nicht gefunden.' });
  if (!isStaff(user.role)) {
    const allowedIds = await ownPlayerIds(user.id, user.role);
    if (!allowedIds.includes(playerId)) {
      return res.status(403).json({ message: 'Keine Berechtigung für diesen Spieler.' });
    }
  }
  const status = enumValue(
    AttendanceStatus,
    req.body.status,
    AttendanceStatus.UNKNOWN,
  );
  if (status === AttendanceStatus.YES && event.maxParticipants) {
    const yesCount = event.attendance.filter(
      (reply) => reply.status === AttendanceStatus.YES && reply.playerId !== playerId,
    ).length;
    if (yesCount >= event.maxParticipants) {
      return res.status(409).json({ message: 'Die maximale Teilnehmerzahl ist erreicht.' });
    }
  }
  const attendance = await prisma.$transaction(async (tx) => {
    const reply = await tx.attendance.upsert({
      where: { eventId_playerId: { eventId: event.id, playerId } },
      update: {
        status,
        reason: status === AttendanceStatus.NO ? clean(req.body.reason) : null,
        goalkeeperAvailable:
          typeof req.body.goalkeeperAvailable === 'boolean'
            ? req.body.goalkeeperAvailable
            : null,
        respondedById: user.id,
        respondedAt: new Date(),
      },
      create: {
        eventId: event.id,
        playerId,
        status,
        reason: status === AttendanceStatus.NO ? clean(req.body.reason) : null,
        goalkeeperAvailable:
          typeof req.body.goalkeeperAvailable === 'boolean'
            ? req.body.goalkeeperAvailable
            : null,
        respondedById: user.id,
        respondedAt: new Date(),
      },
    });
    if (event.type === EventType.MATCH) {
      const squad = await tx.squad.findUnique({ where: { eventId: event.id } });
      const teamId = event.targetTeams[0]?.teamId ?? event.teamId;
      const team = await tx.team.findUnique({
        where: { id: teamId },
        select: { gameFormat: true },
      });
      if (squad && team) {
        await syncSquadWithTeamDefaultLineup(tx, {
          teamId,
          squadId: squad.id,
          fieldSize: fieldSizeForGameFormat(team.gameFormat),
        });
      }
    }
    return reply;
  });
  return res.json(attendance);
}

export async function finalizeAttendance(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: { targetTeams: true },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, event))) {
    return res.status(403).json({ message: 'Keine Berechtigung für diesen Termin.' });
  }
  const updated = await prisma.event.update({
    where: { id: event.id },
    data: { attendanceFinalized: true },
  });
  return res.json(updated);
}

export async function recordActualAttendance(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: { targetTeams: true },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, event))) {
    return res.status(403).json({ message: 'Keine Berechtigung für diesen Termin.' });
  }
  const entries = Array.isArray(req.body.entries) ? req.body.entries : [];
  const targetTeamIds = event.targetTeams.length
    ? event.targetTeams.map((target) => target.teamId)
    : [event.teamId];
  const parsedPlayerIds: string[] = entries
    .map((entry: Record<string, unknown>) => clean(entry.playerId))
    .filter((value: string | null): value is string => Boolean(value));
  const playerIds: string[] = [...new Set<string>(parsedPlayerIds)];
  if (playerIds.length !== entries.length) {
    return res.status(400).json({ message: 'Ungültige Anwesenheitsdaten.' });
  }
  const validPlayers = await prisma.player.count({
    where: { id: { in: playerIds }, teamId: { in: targetTeamIds } },
  });
  if (validPlayers !== playerIds.length) {
    return res.status(403).json({
      message: 'Mindestens ein Spieler gehört nicht zu diesem Termin.',
    });
  }
  await prisma.$transaction(
    entries.map((entry: Record<string, unknown>) =>
      prisma.attendance.upsert({
        where: {
          eventId_playerId: {
            eventId: event.id,
            playerId: String(entry.playerId),
          },
        },
        update: {
          actualAttendance: enumValue(
            AttendanceStatus,
            entry.status,
            AttendanceStatus.UNKNOWN,
          ),
          actualAttendanceNote: clean(entry.note),
        },
        create: {
          eventId: event.id,
          playerId: String(entry.playerId),
          actualAttendance: enumValue(
            AttendanceStatus,
            entry.status,
            AttendanceStatus.UNKNOWN,
          ),
          actualAttendanceNote: clean(entry.note),
        },
      }),
    ),
  );
  return res.json({ updated: entries.length });
}

export async function sendAttendanceReminders(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: { targetTeams: true, attendance: true, participants: true },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, event))) {
    return res.status(403).json({ message: 'Keine Berechtigung für diesen Termin.' });
  }
  const targetTeamIds = event.targetTeams.length
    ? event.targetTeams.map((target) => target.teamId)
    : [event.teamId];
  const replied = new Set(
    event.attendance
      .filter((attendance) => attendance.status !== AttendanceStatus.UNKNOWN)
      .map((attendance) => attendance.playerId),
  );
  const explicitlyRequested = event.participants
    .filter((participant) => participant.responseRequired && participant.playerId)
    .map((participant) => participant.playerId!);
  const players = await prisma.player.findMany({
    where: {
      teamId: { in: targetTeamIds },
      status: 'ACTIVE',
      id: {
        notIn: [...replied],
        ...(event.participants.length ? { in: explicitlyRequested } : {}),
      },
    },
    include: {
      parentLinks: {
        where: { receivesCommunication: true },
        select: { parentId: true },
      },
    },
  });
  const recipientIds = new Set<string>();
  for (const player of players) {
    if (player.userId) recipientIds.add(player.userId);
    player.parentLinks.forEach((link) => recipientIds.add(link.parentId));
  }
  const message =
    clean(req.body.message) ??
    `Bitte Rückmeldung zu „${event.title}“ am ${event.startAt.toLocaleDateString('de-DE')}.`;
  const pushEnabled = req.body.pushEnabled !== false;
  let pushResult = { notifications: 0, deliveries: 0 };
  if (recipientIds.size) {
    const recipients = [...recipientIds];
    await prisma.eventReminder.createMany({
      data: recipients.map((recipientId) => ({
        eventId: event.id,
        recipientId,
        message,
      })),
    });
    pushResult = await notifyUsers(recipients, {
      category: NotificationCategory.EVENT_REMINDER,
      title: 'Offene Rückmeldung',
      body: message,
      actionUrl: `/events/${event.id}`,
      entityType: 'Event',
      entityId: event.id,
      pushEnabled,
    });
  }
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: event.teamId,
      action: 'EVENT_ATTENDANCE_REMINDER_SENT',
      entityType: 'Event',
      entityId: event.id,
      metadata: {
        recipients: recipientIds.size,
        missingPlayers: players.length,
        pushEnabled,
        pushDeliveries: pushResult.deliveries,
      },
    },
  });
  return res.json({
    recipients: recipientIds.size,
    missingPlayers: players.length,
    notifications: pushResult.notifications,
    pushDeliveries: pushResult.deliveries,
  });
}

export async function createCarpoolOffer(req: Request, res: Response) {
  const user = req.user!;
  if (user.role === Role.READ_ONLY) {
    return res.status(403).json({ message: 'Keine Berechtigung für Fahrangebote.' });
  }
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, status: EventStatus.SCHEDULED, ...eventScope(teamIds) },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  const seatsTotal = boundedInt(req.body.seatsTotal, 1, 8);
  const departureLocation = clean(req.body.departureLocation);
  const departureAt = validDate(req.body.departureAt);
  if (!seatsTotal || !departureLocation || !departureAt) {
    return res.status(400).json({
      message: 'Freie Plätze, Abfahrtsort und Abfahrtszeit sind erforderlich.',
    });
  }
  if (departureAt > event.startAt) {
    return res.status(400).json({
      message: 'Die Abfahrt muss vor dem Terminbeginn liegen.',
    });
  }
  const offer = await prisma.carpoolOffer.create({
    data: {
      eventId: event.id,
      driverId: user.id,
      seatsTotal,
      departureLocation,
      departureAt,
      notes: clean(req.body.notes),
    },
  });
  return res.status(201).json(offer);
}

export async function requestCarpoolSeat(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const offer = await prisma.carpoolOffer.findFirst({
    where: {
      id: req.params.offerId,
      eventId: req.params.id,
      event: { is: eventScope(teamIds) },
    },
    include: { event: { include: { targetTeams: true } }, passengers: true },
  });
  if (!offer) return res.status(404).json({ message: 'Fahrangebot nicht gefunden.' });
  const playerId = clean(req.body.playerId);
  if (!playerId) return res.status(400).json({ message: 'Spieler fehlt.' });
  if (!isStaff(user.role)) {
    const allowed = await ownPlayerIds(user.id, user.role);
    if (!allowed.includes(playerId)) {
      return res.status(403).json({ message: 'Keine Berechtigung für diesen Spieler.' });
    }
  }
  const targetTeamIds = offer.event.targetTeams.length
    ? offer.event.targetTeams.map((target) => target.teamId)
    : [offer.event.teamId];
  const player = await prisma.player.findFirst({
    where: { id: playerId, teamId: { in: targetTeamIds } },
    select: { id: true },
  });
  if (!player) {
    return res.status(404).json({ message: 'Spieler gehört nicht zu diesem Termin.' });
  }
  const occupied = offer.passengers.filter(
    (passenger) => passenger.status === CarpoolRequestStatus.CONFIRMED,
  ).length;
  if (occupied >= offer.seatsTotal) {
    return res.status(409).json({ message: 'Für dieses Angebot sind keine Plätze mehr frei.' });
  }
  const passenger = await prisma.carpoolPassenger.upsert({
    where: { offerId_playerId: { offerId: offer.id, playerId } },
    update: { status: CarpoolRequestStatus.REQUESTED, requestedById: user.id },
    create: {
      offerId: offer.id,
      playerId,
      requestedById: user.id,
      status: CarpoolRequestStatus.REQUESTED,
    },
  });
  return res.status(201).json(passenger);
}

export async function updateCarpoolPassenger(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const passenger = await prisma.carpoolPassenger.findFirst({
    where: {
      id: req.params.passengerId,
      offerId: req.params.offerId,
      offer: {
        eventId: req.params.id,
        event: { is: eventScope(teamIds) },
      },
    },
    include: { offer: true },
  });
  if (!passenger) return res.status(404).json({ message: 'Mitfahranfrage nicht gefunden.' });
  const status = enumValue(
    CarpoolRequestStatus,
    req.body.status,
    CarpoolRequestStatus.CANCELLED,
  );
  const driverOrStaff = passenger.offer.driverId === user.id || isStaff(user.role);
  const requester = passenger.requestedById === user.id;
  if (
    (!driverOrStaff &&
      (status === CarpoolRequestStatus.CONFIRMED ||
        status === CarpoolRequestStatus.DECLINED)) ||
    (!driverOrStaff && !requester)
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für diese Anfrage.' });
  }
  if (
    status === CarpoolRequestStatus.CONFIRMED &&
    passenger.status !== CarpoolRequestStatus.CONFIRMED
  ) {
    const confirmed = await prisma.carpoolPassenger.count({
      where: {
        offerId: passenger.offerId,
        status: CarpoolRequestStatus.CONFIRMED,
      },
    });
    if (confirmed >= passenger.offer.seatsTotal) {
      return res.status(409).json({ message: 'Alle Plätze sind bereits belegt.' });
    }
  }
  return res.json(
    await prisma.carpoolPassenger.update({
      where: { id: passenger.id },
      data: { status },
    }),
  );
}

export async function calendarSubscription(req: Request, res: Response) {
  const token = randomBytes(24).toString('hex');
  const user = await prisma.user.update({
    where: { id: req.user!.id },
    data: { calendarToken: token },
    select: { calendarToken: true },
  });
  const baseUrl =
    process.env.PUBLIC_API_URL?.replace(/\/$/, '') ??
    `${req.protocol}://${req.get('host')}`;
  return res.json({
    url: `${baseUrl}/events/subscription/${user.calendarToken}.ics`,
  });
}

export function icsEscape(value: string | null | undefined) {
  return (value ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;');
}

export function icsDate(value: Date) {
  return value.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

export async function publicCalendarSubscription(req: Request, res: Response) {
  const user = await prisma.user.findFirst({
    where: {
      calendarToken: req.params.token,
      status: AccountStatus.APPROVED,
    },
    select: { id: true, role: true, teamId: true },
  });
  if (!user) return res.status(404).send('Kalenderabonnement nicht gefunden.');
  const teamIds = await accessibleTeamIds(user);
  const events = await prisma.event.findMany({
    where: {
      ...eventScope(teamIds),
      startAt: { gte: new Date(Date.now() - 90 * 86400000) },
      ...(!isStaff(user.role) ? { visibility: { not: EventVisibility.STAFF_ONLY } } : {}),
    },
    orderBy: { startAt: 'asc' },
  });
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//FC Teugn//Vereinskalender//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:FC Teugn',
  ];
  for (const event of events) {
    lines.push(
      'BEGIN:VEVENT',
      `UID:${event.id}@fc-teugn.de`,
      `DTSTAMP:${icsDate(event.updatedAt)}`,
      `DTSTART:${icsDate(event.startAt)}`,
      ...(event.endAt ? [`DTEND:${icsDate(event.endAt)}`] : []),
      `SUMMARY:${icsEscape(event.status === EventStatus.CANCELLED ? `ABGESAGT: ${event.title}` : event.title)}`,
      `LOCATION:${icsEscape(event.address ?? event.location)}`,
      `DESCRIPTION:${icsEscape(event.description)}`,
      `STATUS:${event.status === EventStatus.CANCELLED ? 'CANCELLED' : 'CONFIRMED'}`,
      'END:VEVENT',
    );
  }
  lines.push('END:VCALENDAR');
  res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="fc-teugn-kalender.ics"');
  res.setHeader('Cache-Control', 'private, max-age=300');
  return res.send(`${lines.join('\r\n')}\r\n`);
}

export async function upsertMatchDetails(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: { targetTeams: true },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, event))) {
    return res.status(403).json({ message: 'Keine Berechtigung für diesen Termin.' });
  }
  const { opponent, isHome, competition, notes, ourGoals, theirGoals } = req.body;
  const current = await prisma.matchDetails.findUnique({
    where: { eventId: event.id },
    select: { periodCount: true, periodMinutes: true },
  });
  const timing = matchTiming(req.body, current ?? undefined);
  if (!timing) {
    return res.status(400).json({
      message:
        'Bitte 1–8 Spielabschnitte und 1–90 Minuten je Abschnitt angeben (maximal 180 Minuten insgesamt).',
    });
  }
  const details = await prisma.matchDetails.upsert({
    where: { eventId: event.id },
    update: {
      opponent,
      isHome,
      competition,
      notes,
      ourGoals,
      theirGoals,
      ...timing,
    },
    create: {
      eventId: event.id,
      opponent: opponent ?? 'Unbekannt',
      isHome: isHome ?? true,
      competition,
      notes,
      ourGoals,
      theirGoals,
      ...timing,
    },
  });
  return res.json(details);
}

export async function upsertSquad(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    include: { targetTeams: true },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  if (!(await canManageEvent(user, event))) {
    return res.status(403).json({ message: 'Keine Berechtigung für diesen Termin.' });
  }
  const { name, formation, playerIds } = req.body as {
    name?: string;
    formation?: string;
    playerIds?: string[];
  };
  const existingSquad = await prisma.squad.findFirst({ where: { eventId: event.id } });
  const squad = existingSquad
    ? await prisma.squad.update({
        where: { id: existingSquad.id },
        data: { name, formation },
      })
    : await prisma.squad.create({
        data: { eventId: event.id, name, formation },
      });
  if (playerIds) {
    await prisma.squadMember.deleteMany({ where: { squadId: squad.id } });
    if (playerIds.length) {
      await prisma.squadMember.createMany({
        data: playerIds.map((playerId) => ({ squadId: squad.id, playerId })),
        skipDuplicates: true,
      });
    }
  }
  return res.json(
    await prisma.squad.findUnique({
      where: { id: squad.id },
      include: { members: true },
    }),
  );
}
