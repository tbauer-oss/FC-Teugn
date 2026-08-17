import {
  AccountStatus,
  EventType,
  Prisma,
  Role,
  TrainingAttendanceStatus,
  TrainingPhase,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import {
  accessibleTeamIds,
  clubIdForTeam,
  contextualTeamIds,
  eventTeamScope,
  resolveContextTeamId,
} from '../services/team-access';
import { ensureNextRegularTrainingOccurrences } from '../services/regular-training-occurrence.service';

const occupancyAdminRoles: Role[] = [
  Role.SUPER_ADMIN,
  Role.CLUB_ADMIN,
  Role.YOUTH_DIRECTOR,
];

const trainingCoachRoles: Role[] = [
  Role.COACH,
  Role.TRAINER,
  Role.ASSISTANT_COACH,
  Role.TRAINER_ADMIN,
  Role.TEAM_MANAGER,
];

function text(value: unknown, max = 1000) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, max) : null;
}

function integer(value: unknown, minimum: number, maximum: number, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum
    ? parsed
    : fallback;
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

function stringList(value: unknown, maximum = 12) {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => text(item, 80))
        .filter((item): item is string => Boolean(item)),
    ),
  ].slice(0, maximum);
}

function safeUrl(value: unknown) {
  const normalized = text(value, 500);
  if (!normalized) return null;
  try {
    const url = new URL(normalized);
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : null;
  } catch {
    return null;
  }
}

const trainingInclude = {
  targetTeams: {
    include: {
      team: { select: { id: true, name: true, shortName: true } },
    },
  },
  attendance: {
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          photoUrl: true,
          position: true,
          status: true,
        },
      },
    },
  },
  trainingPlan: {
    include: {
      coachAssignments: {
        orderBy: { createdAt: 'asc' as const },
        include: {
          user: {
            select: { id: true, name: true, role: true },
          },
        },
      },
      items: {
        orderBy: { position: 'asc' as const },
        include: { exercise: true },
      },
    },
  },
} as const;

async function eligibleTrainingCoaches(teamIds: string[]) {
  const users = await prisma.user.findMany({
    where: {
      status: AccountStatus.APPROVED,
      OR: [
        {
          teamId: { in: teamIds },
          role: { in: trainingCoachRoles },
        },
        {
          memberships: {
            some: {
              teamId: { in: teamIds },
              status: AccountStatus.APPROVED,
              role: { in: trainingCoachRoles },
            },
          },
        },
      ],
    },
    select: {
      id: true,
      name: true,
      role: true,
      teamId: true,
      memberships: {
        where: {
          teamId: { in: teamIds },
          status: AccountStatus.APPROVED,
          role: { in: trainingCoachRoles },
        },
        select: { teamId: true, role: true },
      },
    },
    orderBy: { name: 'asc' },
  });
  return users.map((user) => ({
    id: user.id,
    name: user.name,
    role: user.memberships[0]?.role ?? user.role,
    teamIds: [
      ...new Set([
        ...(teamIds.includes(user.teamId) ? [user.teamId] : []),
        ...user.memberships.map((membership) => membership.teamId),
      ]),
    ],
  }));
}

export async function listPitchOccupancy(req: Request, res: Response) {
  const indoor = String(req.query.mode ?? '').toUpperCase() === 'INDOOR';
  const contextTeamId = await resolveContextTeamId(req.user!);
  if (!contextTeamId) {
    return res.status(404).json({ message: 'Keine aktive Mannschaft gefunden.' });
  }
  const currentTeam = await prisma.team.findUnique({
    where: { id: contextTeamId },
    select: {
      ageGroup: {
        select: {
          season: {
            select: {
              id: true,
              name: true,
              startDate: true,
              endDate: true,
              recreationalTrainingLocation: true,
              recreationalTrainingTimes: true,
              seniorTrainingLocation: true,
              seniorTrainingTimes: true,
              seniorMatchdayTimes: true,
              approvedOccupancyConflictKeys: true,
              club: { select: { id: true, name: true } },
            },
          },
        },
      },
    },
  });
  if (!currentTeam) {
    return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  }
  const season = currentTeam.ageGroup.season;
  const teams = await prisma.team.findMany({
    where: {
      isActive: true,
      ageGroup: { seasonId: season.id },
    },
    orderBy: [
      { ageGroup: { sortOrder: 'asc' } },
      { name: 'asc' },
    ],
    select: {
      id: true,
      name: true,
      shortName: true,
      trainingLocation: true,
      trainingTimes: true,
      trainingPartnerIds: true,
      matchdayTimes: true,
      indoorTrainingLocation: true,
      indoorTrainingTimes: true,
      indoorTrainingPartnerIds: true,
      ageGroup: {
        select: { code: true, name: true, sortOrder: true },
      },
    },
  });
  const occupancyTeams = teams.map((team) => indoor ? {
    ...team,
    trainingLocation: team.indoorTrainingLocation,
    trainingTimes: team.indoorTrainingTimes,
    trainingPartnerIds: team.indoorTrainingPartnerIds,
    matchdayTimes: [],
  } : team);
  const recreationalSchedule = {
    id: `recreational:${season.id}`,
    name: 'Freizeitkicker',
    shortName: 'Freizeitkicker',
    trainingLocation: season.recreationalTrainingLocation,
    trainingTimes: season.recreationalTrainingTimes,
    trainingPartnerIds: [],
    matchdayTimes: [],
    ageGroup: {
      code: '',
      name: 'Freizeit',
      sortOrder: 999,
    },
  };
  const seniorSchedule = {
    id: `seniors:${season.id}`,
    name: 'Herren',
    shortName: 'Herren',
    trainingLocation: season.seniorTrainingLocation,
    trainingTimes: season.seniorTrainingTimes,
    trainingPartnerIds: [],
    matchdayTimes: season.seniorMatchdayTimes,
    ageGroup: {
      code: '',
      name: 'Herren',
      sortOrder: 998,
    },
  };
  const specialEntries = indoor
    ? await prisma.indoorOccupancyEntry.findMany({
        where: { seasonId: season.id },
        orderBy: [{ startAt: 'asc' }, { title: 'asc' }],
      })
    : [];
  return res.json({
    club: season.club,
    season: {
      id: season.id,
      name: season.name,
      startDate: season.startDate,
      endDate: season.endDate,
    },
    mode: indoor ? 'INDOOR' : 'OUTDOOR',
    teams: [
      ...occupancyTeams,
      ...(!indoor &&
              (seniorSchedule.trainingTimes.length > 0 ||
                seniorSchedule.matchdayTimes.length > 0)
          ? [seniorSchedule]
          : []),
      ...(!indoor && recreationalSchedule.trainingTimes.length > 0
          ? [recreationalSchedule]
          : []),
    ],
    recreationalSchedule,
    seniorSchedule,
    specialEntries,
    approvedConflictKeys: season.approvedOccupancyConflictKeys,
    canManageOccupancy: occupancyAdminRoles.includes(req.user!.role as Role),
  });
}

async function editableOccupancySeason(user: Request['user'], seasonId: string) {
  if (!user || !canManageClubOccupancy(user.role as Role)) return null;
  const clubId =
    user.role === Role.SUPER_ADMIN ? null : await clubIdForTeam(user.teamId);
  return prisma.season.findFirst({
    where: {
      id: seasonId,
      isActive: true,
      ...(user.role === Role.SUPER_ADMIN
        ? {}
        : clubId
          ? { clubId }
          : { id: '__unauthorized__' }),
    },
    select: { id: true },
  });
}

function indoorEntryData(body: Record<string, unknown>) {
  const title = text(body.title, 120);
  const startAt = new Date(String(body.startAt ?? ''));
  const endAt = new Date(String(body.endAt ?? ''));
  const isRecurring = body.isRecurring === true;
  const recurrenceWeekdays = [
    ...new Set(
      (Array.isArray(body.recurrenceWeekdays)
        ? body.recurrenceWeekdays
        : []
      )
        .map(Number)
        .filter((value) => Number.isInteger(value) && value >= 1 && value <= 7),
    ),
  ].sort();
  const recurrenceIntervalWeeks = integer(
    body.recurrenceIntervalWeeks,
    1,
    4,
    1,
  );
  const recurrenceUntil = isRecurring
    ? new Date(String(body.recurrenceUntil ?? ''))
    : null;
  if (!title) {
    return { error: 'Eine Bezeichnung ist erforderlich.' } as const;
  }
  if (
    Number.isNaN(startAt.getTime()) ||
    Number.isNaN(endAt.getTime()) ||
    endAt <= startAt
  ) {
    return { error: 'Beginn und Ende des Termins sind ungültig.' } as const;
  }
  if (endAt.getTime() - startAt.getTime() > 7 * 86400000) {
    return { error: 'Eine einzelne Hallenbelegung darf höchstens sieben Tage dauern.' } as const;
  }
  if (
    isRecurring &&
    (recurrenceWeekdays.length === 0 ||
      !recurrenceUntil ||
      Number.isNaN(recurrenceUntil.getTime()) ||
      recurrenceUntil < startAt)
  ) {
    return {
      error:
        'Für einen Serientermin müssen Wochentage und ein gültiges Serienende angegeben werden.',
    } as const;
  }
  return {
    data: {
      title,
      location: 'Sporthalle',
      startAt,
      endAt,
      notes: text(body.notes, 1000),
      isRecurring,
      recurrenceWeekdays: isRecurring ? recurrenceWeekdays : [],
      recurrenceIntervalWeeks: isRecurring ? recurrenceIntervalWeeks : 1,
      recurrenceUntil,
    },
  } as const;
}

export async function createIndoorOccupancyEntry(req: Request, res: Response) {
  const seasonId = text(req.body?.seasonId, 100);
  if (!seasonId) {
    return res.status(400).json({ message: 'Eine Saison muss ausgewählt sein.' });
  }
  const season = await editableOccupancySeason(req.user, seasonId);
  if (!season) {
    return res.status(403).json({
      message:
        'Nur Systemadministration, Vereinsleitung oder Jugendleitung dürfen Hallen-Sonderbelegungen verwalten.',
    });
  }
  const parsed = indoorEntryData(req.body ?? {});
  if ('error' in parsed) return res.status(400).json({ message: parsed.error });
  const entry = await prisma.$transaction(async (tx) => {
    const created = await tx.indoorOccupancyEntry.create({
      data: {
        seasonId,
        ...parsed.data,
        createdById: req.user!.id,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: 'INDOOR_OCCUPANCY_ENTRY_CREATED',
        entityType: 'IndoorOccupancyEntry',
        entityId: created.id,
        metadata: parsed.data,
      },
    });
    return created;
  });
  return res.status(201).json(entry);
}

export async function updateIndoorOccupancyEntry(req: Request, res: Response) {
  const existing = await prisma.indoorOccupancyEntry.findUnique({
    where: { id: req.params.entryId },
  });
  if (!existing) {
    return res.status(404).json({ message: 'Hallenbelegung nicht gefunden.' });
  }
  const season = await editableOccupancySeason(req.user, existing.seasonId);
  if (!season) {
    return res.status(403).json({
      message:
        'Nur Systemadministration, Vereinsleitung oder Jugendleitung dürfen Hallen-Sonderbelegungen verwalten.',
    });
  }
  const parsed = indoorEntryData(req.body ?? {});
  if ('error' in parsed) return res.status(400).json({ message: parsed.error });
  const entry = await prisma.$transaction(async (tx) => {
    const updated = await tx.indoorOccupancyEntry.update({
      where: { id: existing.id },
      data: parsed.data,
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: 'INDOOR_OCCUPANCY_ENTRY_UPDATED',
        entityType: 'IndoorOccupancyEntry',
        entityId: existing.id,
        metadata: { before: existing, after: parsed.data },
      },
    });
    return updated;
  });
  return res.json(entry);
}

export async function deleteIndoorOccupancyEntry(req: Request, res: Response) {
  const existing = await prisma.indoorOccupancyEntry.findUnique({
    where: { id: req.params.entryId },
  });
  if (!existing) {
    return res.status(404).json({ message: 'Hallenbelegung nicht gefunden.' });
  }
  const season = await editableOccupancySeason(req.user, existing.seasonId);
  if (!season) {
    return res.status(403).json({
      message:
        'Nur Systemadministration, Vereinsleitung oder Jugendleitung dürfen Hallen-Sonderbelegungen verwalten.',
    });
  }
  await prisma.$transaction([
    prisma.indoorOccupancyEntry.delete({ where: { id: existing.id } }),
    prisma.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: 'INDOOR_OCCUPANCY_ENTRY_DELETED',
        entityType: 'IndoorOccupancyEntry',
        entityId: existing.id,
        metadata: existing,
      },
    }),
  ]);
  return res.status(204).send();
}

export function canManageRecreationalOccupancy(role: Role) {
  return role === Role.SUPER_ADMIN;
}

export function canManageClubOccupancy(role: Role) {
  return occupancyAdminRoles.includes(role);
}

export async function updateRecreationalOccupancy(
  req: Request,
  res: Response,
) {
  const user = req.user!;
  if (!canManageRecreationalOccupancy(user.role)) {
    return res.status(403).json({
      message:
        'Nur die Systemadministration darf den Freizeitkickern einen Platz zuweisen.',
    });
  }
  const seasonId = text(req.body?.seasonId, 100);
  if (!seasonId) {
    return res.status(400).json({ message: 'Eine Saison muss ausgewählt sein.' });
  }
  const trainingLocation = text(req.body?.trainingLocation, 200);
  const trainingTimes = stringList(req.body?.trainingTimes, 14);
  const season = await prisma.$transaction(async (tx) => {
    const existing = await tx.season.findFirst({
      where: { id: seasonId, isActive: true },
      select: {
        id: true,
        recreationalTrainingLocation: true,
        recreationalTrainingTimes: true,
      },
    });
    if (!existing) return null;
    const updated = await tx.season.update({
      where: { id: seasonId },
      data: {
        recreationalTrainingLocation: trainingLocation,
        recreationalTrainingTimes: trainingTimes,
      },
      select: {
        id: true,
        recreationalTrainingLocation: true,
        recreationalTrainingTimes: true,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: 'RECREATIONAL_PITCH_OCCUPANCY_UPDATED',
        entityType: 'Season',
        entityId: seasonId,
        metadata: {
          before: {
            trainingLocation: existing.recreationalTrainingLocation,
            trainingTimes: existing.recreationalTrainingTimes,
          },
          after: { trainingLocation, trainingTimes },
        },
      },
    });
    return updated;
  });
  if (!season) {
    return res.status(404).json({ message: 'Aktive Saison nicht gefunden.' });
  }
  return res.json({
    id: `recreational:${season.id}`,
    name: 'Freizeitkicker',
    shortName: 'Freizeitkicker',
    trainingLocation: season.recreationalTrainingLocation,
    trainingTimes: season.recreationalTrainingTimes,
    ageGroup: { code: '', name: 'Freizeit', sortOrder: 999 },
  });
}

export async function updateSeniorOccupancy(req: Request, res: Response) {
  const user = req.user!;
  if (!canManageClubOccupancy(user.role as Role)) {
    return res.status(403).json({
      message:
        'Nur Systemadministration, Vereinsleitung oder Jugendleitung dürfen die Herren-Belegung verwalten.',
    });
  }
  const seasonId = text(req.body?.seasonId, 100);
  if (!seasonId) {
    return res.status(400).json({ message: 'Eine Saison muss ausgewählt sein.' });
  }
  const trainingLocation = text(req.body?.trainingLocation, 200);
  const trainingTimes = stringList(req.body?.trainingTimes, 14);
  const matchdayTimes = stringList(req.body?.matchdayTimes, 14);
  const clubId = user.role === Role.SUPER_ADMIN
    ? null
    : await clubIdForTeam(user.teamId);
  const season = await prisma.$transaction(async (tx) => {
    const existing = await tx.season.findFirst({
      where: {
        id: seasonId,
        isActive: true,
        ...(user.role === Role.SUPER_ADMIN
          ? {}
          : clubId
            ? { clubId }
            : { id: '__unauthorized__' }),
      },
      select: {
        id: true,
        seniorTrainingLocation: true,
        seniorTrainingTimes: true,
        seniorMatchdayTimes: true,
      },
    });
    if (!existing) return null;
    const updated = await tx.season.update({
      where: { id: seasonId },
      data: {
        seniorTrainingLocation: trainingLocation,
        seniorTrainingTimes: trainingTimes,
        seniorMatchdayTimes: matchdayTimes,
      },
      select: {
        id: true,
        seniorTrainingLocation: true,
        seniorTrainingTimes: true,
        seniorMatchdayTimes: true,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: 'SENIOR_PITCH_OCCUPANCY_UPDATED',
        entityType: 'Season',
        entityId: seasonId,
        metadata: {
          before: existing,
          after: { trainingLocation, trainingTimes, matchdayTimes },
        },
      },
    });
    return updated;
  });
  if (!season) {
    return res.status(404).json({ message: 'Aktive Saison nicht gefunden.' });
  }
  return res.json({
    id: `seniors:${season.id}`,
    name: 'Herren',
    shortName: 'Herren',
    trainingLocation: season.seniorTrainingLocation,
    trainingTimes: season.seniorTrainingTimes,
    trainingPartnerIds: [],
    matchdayTimes: season.seniorMatchdayTimes,
    ageGroup: { code: '', name: 'Herren', sortOrder: 998 },
  });
}

export async function updateOccupancyConflictApproval(
  req: Request,
  res: Response,
) {
  const user = req.user!;
  if (!canManageClubOccupancy(user.role as Role)) {
    return res.status(403).json({
      message:
        'Diese Überschneidung darf nicht bestätigt werden.',
    });
  }
  const seasonId = text(req.body?.seasonId, 100);
  const conflictKey = text(req.body?.conflictKey, 500);
  const approved = req.body?.approved !== false;
  if (!seasonId || !conflictKey) {
    return res.status(400).json({
      message: 'Saison und Konflikt müssen angegeben werden.',
    });
  }
  const clubId = user.role === Role.SUPER_ADMIN
    ? null
    : await clubIdForTeam(user.teamId);
  const season = await prisma.season.findFirst({
    where: {
      id: seasonId,
      isActive: true,
      ...(user.role === Role.SUPER_ADMIN
        ? {}
        : clubId
          ? { clubId }
          : { id: '__unauthorized__' }),
    },
    select: { id: true, approvedOccupancyConflictKeys: true },
  });
  if (!season) {
    return res.status(404).json({ message: 'Aktive Saison nicht gefunden.' });
  }
  const keys = new Set(season.approvedOccupancyConflictKeys);
  if (approved) keys.add(conflictKey);
  else keys.delete(conflictKey);
  const approvedConflictKeys = [...keys].slice(-200);
  await prisma.$transaction([
    prisma.season.update({
      where: { id: seasonId },
      data: { approvedOccupancyConflictKeys: approvedConflictKeys },
    }),
    prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: approved
          ? 'PITCH_OCCUPANCY_CONFLICT_APPROVED'
          : 'PITCH_OCCUPANCY_CONFLICT_REOPENED',
        entityType: 'Season',
        entityId: seasonId,
        metadata: { conflictKey },
      },
    }),
  ]);
  return res.json({ approvedConflictKeys });
}

export async function listTrainingCoaches(req: Request, res: Response) {
  const teamIds = await accessibleTeamIds(req.user!);
  const training = await prisma.event.findFirst({
    where: {
      id: req.params.id,
      type: EventType.TRAINING,
      ...eventTeamScope(teamIds),
    },
    select: {
      teamId: true,
      targetTeams: { select: { teamId: true } },
    },
  });
  if (!training) {
    return res.status(404).json({ message: 'Training nicht gefunden.' });
  }
  const trainingTeamIds = [
    training.teamId,
    ...training.targetTeams.map((target) => target.teamId),
  ];
  return res.json(await eligibleTrainingCoaches(trainingTeamIds));
}

export async function listTrainings(req: Request, res: Response) {
  // The planning overview follows the actively selected youth context. A
  // system administrator or trainer must not see unrelated teams merely
  // because their account is allowed to administer the whole club.
  const teamIds = await contextualTeamIds(req.user!);
  const from = req.query.from
    ? new Date(String(req.query.from))
    : new Date(Date.now() - 180 * 86400000);
  const to = req.query.to
    ? new Date(String(req.query.to))
    : new Date(Date.now() + 550 * 86400000);
  await ensureNextRegularTrainingOccurrences(teamIds);
  const trainings = await prisma.event.findMany({
    where: {
      type: EventType.TRAINING,
      isHiddenRegularOccurrence: false,
      ...eventTeamScope(teamIds),
      startAt: {
        gte: Number.isNaN(from.getTime())
          ? new Date(Date.now() - 180 * 86400000)
          : from,
        lte: Number.isNaN(to.getTime())
          ? new Date(Date.now() + 550 * 86400000)
          : to,
      },
    },
    include: trainingInclude,
    orderBy: { startAt: 'asc' },
    take: 500,
  });
  const roster = await prisma.player.findMany({
    where: { teamId: { in: teamIds }, status: { not: 'LEFT' } },
    select: {
      id: true,
      teamId: true,
      firstName: true,
      lastName: true,
      preferredName: true,
      shirtNumber: true,
      status: true,
    },
    orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
  });
  return res.json(
    trainings.map((training) => ({
      ...training,
      roster: roster.filter(
        (player) =>
          player.teamId !== null &&
          [
            training.teamId,
            ...training.targetTeams.map((target) => target.teamId),
          ].includes(player.teamId),
      ),
    })),
  );
}

export async function getTraining(req: Request, res: Response) {
  const teamIds = await accessibleTeamIds(req.user!);
  const training = await prisma.event.findFirst({
    where: {
      id: req.params.id,
      type: EventType.TRAINING,
      isHiddenRegularOccurrence: false,
      ...eventTeamScope(teamIds),
    },
    include: trainingInclude,
  });
  if (!training) return res.status(404).json({ message: 'Training nicht gefunden.' });
  const rosterTeamIds = [
    training.teamId,
    ...training.targetTeams.map((target) => target.teamId),
  ];
  const roster = await prisma.player.findMany({
    where: { teamId: { in: rosterTeamIds }, status: { not: 'LEFT' } },
    select: {
      id: true,
      teamId: true,
      firstName: true,
      lastName: true,
      preferredName: true,
      shirtNumber: true,
      status: true,
    },
    orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
  });
  return res.json({ ...training, roster });
}

export async function saveTrainingPlan(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const training = await prisma.event.findFirst({
    where: { id: req.params.id, type: EventType.TRAINING, ...eventTeamScope(teamIds) },
    select: {
      id: true,
      teamId: true,
      targetTeams: { select: { teamId: true } },
    },
  });
  if (!training) return res.status(404).json({ message: 'Training nicht gefunden.' });
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if (items.length > 40) {
    return res.status(400).json({ message: 'Ein Trainingsplan darf höchstens 40 Bausteine enthalten.' });
  }
  const coachIds = stringList(req.body.coachIds, 20);
  const trainingTeamIds = [
    training.teamId,
    ...training.targetTeams.map((target) => target.teamId),
  ];
  const eligibleCoaches = await eligibleTrainingCoaches(trainingTeamIds);
  const eligibleCoachIds = new Set(eligibleCoaches.map((coach) => coach.id));
  if (coachIds.some((coachId) => !eligibleCoachIds.has(coachId))) {
    return res.status(400).json({
      message: 'Mindestens ein ausgewählter Trainer gehört nicht zum Trainerteam dieser Jugend.',
    });
  }
  const coachNames = coachIds
    .map((coachId) => eligibleCoaches.find((coach) => coach.id === coachId)?.name)
    .filter((name): name is string => Boolean(name));
  const exerciseIds: string[] = Array.from(
    new Set<string>(
      (items as Record<string, unknown>[])
        .map((item) => text(item.exerciseId, 100))
        .filter((item): item is string => Boolean(item)),
    ),
  );
  if (exerciseIds.length) {
    const exercises = await prisma.trainingExercise.count({
      where: { id: { in: exerciseIds }, teamId: { in: teamIds }, isArchived: false },
    });
    if (exercises !== exerciseIds.length) {
      return res.status(400).json({ message: 'Mindestens eine Übung ist nicht verfügbar.' });
    }
  }
  const plan = await prisma.$transaction(async (tx) => {
    const saved = await tx.trainingPlan.upsert({
      where: { eventId: training.id },
      update: {
        focusAreas: stringList(req.body.focusAreas),
        learningGoals: text(req.body.learningGoals, 2000),
        durationMinutes: integer(req.body.durationMinutes, 10, 300, 90),
        participantNotes: text(req.body.participantNotes, 1000),
        coaches: coachNames.length ? coachNames.join(', ') : null,
        materials: text(req.body.materials, 1000),
        pitchSetup: text(req.body.pitchSetup, 2000),
        feedback: text(req.body.feedback, 2000),
      },
      create: {
        eventId: training.id,
        createdById: user.id,
        focusAreas: stringList(req.body.focusAreas),
        learningGoals: text(req.body.learningGoals, 2000),
        durationMinutes: integer(req.body.durationMinutes, 10, 300, 90),
        participantNotes: text(req.body.participantNotes, 1000),
        coaches: coachNames.length ? coachNames.join(', ') : null,
        materials: text(req.body.materials, 1000),
        pitchSetup: text(req.body.pitchSetup, 2000),
        feedback: text(req.body.feedback, 2000),
      },
    });
    await tx.trainingPlanCoach.deleteMany({
      where: { trainingPlanId: saved.id },
    });
    if (coachIds.length) {
      await tx.trainingPlanCoach.createMany({
        data: coachIds.map((userId) => ({
          trainingPlanId: saved.id,
          userId,
        })),
      });
    }
    await tx.trainingPlanItem.deleteMany({ where: { trainingPlanId: saved.id } });
    if (items.length) {
      await tx.trainingPlanItem.createMany({
        data: items.map((item: Record<string, unknown>, index: number) => ({
          trainingPlanId: saved.id,
          exerciseId: text(item.exerciseId, 100),
          phase: enumValue(TrainingPhase, item.phase, TrainingPhase.MAIN_PART),
          title: text(item.title, 160) ?? `Baustein ${index + 1}`,
          durationMinutes: integer(item.durationMinutes, 1, 120, 10),
          position: index,
          notes: text(item.notes, 1000),
        })),
      });
    }
    return tx.trainingPlan.findUnique({
      where: { id: saved.id },
      include: {
        coachAssignments: {
          orderBy: { createdAt: 'asc' },
          include: {
            user: { select: { id: true, name: true, role: true } },
          },
        },
        items: {
          orderBy: { position: 'asc' },
          include: { exercise: true },
        },
      },
    });
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: training.teamId,
      action: 'TRAINING_PLAN_UPDATED',
      entityType: 'TrainingPlan',
      entityId: plan?.id,
      metadata: {
        itemCount: items.length,
        durationMinutes: plan?.durationMinutes,
        coachIds,
      } as Prisma.InputJsonValue,
    },
  });
  return res.json(plan);
}

export async function recordTrainingAttendance(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const training = await prisma.event.findFirst({
    where: { id: req.params.id, type: EventType.TRAINING, ...eventTeamScope(teamIds) },
    select: { id: true, teamId: true },
  });
  if (!training) return res.status(404).json({ message: 'Training nicht gefunden.' });
  const entries = Array.isArray(req.body?.entries) ? req.body.entries : [];
  const playerIds = [
    ...new Set(entries.map((item: Record<string, unknown>) => text(item.playerId, 100)).filter(Boolean)),
  ] as string[];
  const validPlayers = await prisma.player.count({
    where: { id: { in: playerIds }, teamId: { in: teamIds } },
  });
  if (validPlayers !== playerIds.length) {
    return res.status(400).json({ message: 'Mindestens ein Spieler gehört nicht zur Mannschaft.' });
  }
  await prisma.$transaction(
    entries.map((entry: Record<string, unknown>) =>
      prisma.attendance.upsert({
        where: {
          eventId_playerId: {
            eventId: training.id,
            playerId: String(entry.playerId),
          },
        },
        update: {
          trainingStatus: enumValue(
            TrainingAttendanceStatus,
            entry.status,
            TrainingAttendanceStatus.PRESENT,
          ),
          actualAttendanceNote: text(entry.note, 500),
        },
        create: {
          eventId: training.id,
          playerId: String(entry.playerId),
          trainingStatus: enumValue(
            TrainingAttendanceStatus,
            entry.status,
            TrainingAttendanceStatus.PRESENT,
          ),
          actualAttendanceNote: text(entry.note, 500),
        },
      }),
    ),
  );
  await prisma.event.update({
    where: { id: training.id },
    data: { attendanceFinalized: true },
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: training.teamId,
      action: 'TRAINING_ATTENDANCE_RECORDED',
      entityType: 'Event',
      entityId: training.id,
      metadata: { entryCount: entries.length },
    },
  });
  return res.json({ recorded: entries.length });
}

export async function listExercises(req: Request, res: Response) {
  const teamIds = await contextualTeamIds(req.user!);
  const category = text(req.query.category, 100);
  const exercises = await prisma.trainingExercise.findMany({
    where: {
      teamId: { in: teamIds },
      isArchived: false,
      ...(category ? { category } : {}),
    },
    orderBy: [{ isFavorite: 'desc' }, { title: 'asc' }],
  });
  return res.json(exercises);
}

export async function saveExercise(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const teamId = text(req.body?.teamId, 100) ?? user.teamId;
  if (!teamIds.includes(teamId)) {
    return res.status(403).json({ message: 'Keine Berechtigung für diese Mannschaft.' });
  }
  const title = text(req.body?.title, 160);
  const setup = text(req.body?.setup, 3000);
  const instructions = text(req.body?.instructions, 5000);
  if (!title || !setup || !instructions) {
    return res.status(400).json({ message: 'Titel, Aufbau und Ablauf sind erforderlich.' });
  }
  const payload = {
    teamId,
    title,
    category: text(req.body.category, 100) ?? 'Allgemein',
    ageGroups: stringList(req.body.ageGroups),
    minPlayers:
      req.body.minPlayers == null ? null : integer(req.body.minPlayers, 1, 40, 1),
    maxPlayers:
      req.body.maxPlayers == null ? null : integer(req.body.maxPlayers, 1, 60, 20),
    durationMinutes: integer(req.body.durationMinutes, 1, 120, 15),
    materials: text(req.body.materials, 1000),
    setup,
    instructions,
    coachingPoints: text(req.body.coachingPoints, 3000),
    variations: text(req.body.variations, 3000),
    diagramUrl: safeUrl(req.body.diagramUrl),
    isFavorite: req.body.isFavorite === true,
  };
  const exercise = req.params.exerciseId
    ? await prisma.trainingExercise.update({
        where: { id: req.params.exerciseId, teamId: { in: teamIds } },
        data: payload,
      })
    : await prisma.trainingExercise.create({
        data: { ...payload, createdById: user.id },
      });
  return res.json(exercise);
}

export async function archiveExercise(req: Request, res: Response) {
  const teamIds = await accessibleTeamIds(req.user!);
  const result = await prisma.trainingExercise.updateMany({
    where: { id: req.params.exerciseId, teamId: { in: teamIds } },
    data: { isArchived: true },
  });
  if (!result.count) return res.status(404).json({ message: 'Übung nicht gefunden.' });
  return res.status(204).send();
}
