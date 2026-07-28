import {
  EventType,
  Prisma,
  TrainingAttendanceStatus,
  TrainingPhase,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, eventTeamScope } from '../services/team-access';

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
      items: {
        orderBy: { position: 'asc' as const },
        include: { exercise: true },
      },
    },
  },
} as const;

export async function listTrainings(req: Request, res: Response) {
  const teamIds = await accessibleTeamIds(req.user!);
  const from = req.query.from ? new Date(String(req.query.from)) : new Date(Date.now() - 30 * 86400000);
  const to = req.query.to ? new Date(String(req.query.to)) : new Date(Date.now() + 180 * 86400000);
  const trainings = await prisma.event.findMany({
    where: {
      type: EventType.TRAINING,
      ...eventTeamScope(teamIds),
      startAt: {
        gte: Number.isNaN(from.getTime()) ? new Date(Date.now() - 30 * 86400000) : from,
        lte: Number.isNaN(to.getTime()) ? new Date(Date.now() + 180 * 86400000) : to,
      },
    },
    include: trainingInclude,
    orderBy: { startAt: 'asc' },
    take: 100,
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
      roster: roster.filter((player) =>
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
    where: { id: req.params.id, type: EventType.TRAINING, ...eventTeamScope(teamIds) },
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
    select: { id: true, teamId: true },
  });
  if (!training) return res.status(404).json({ message: 'Training nicht gefunden.' });
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if (items.length > 40) {
    return res.status(400).json({ message: 'Ein Trainingsplan darf höchstens 40 Bausteine enthalten.' });
  }
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
        coaches: text(req.body.coaches, 500),
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
        coaches: text(req.body.coaches, 500),
        materials: text(req.body.materials, 1000),
        pitchSetup: text(req.body.pitchSetup, 2000),
        feedback: text(req.body.feedback, 2000),
      },
    });
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
  const teamIds = await accessibleTeamIds(req.user!);
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
