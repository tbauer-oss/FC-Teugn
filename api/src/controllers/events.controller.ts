import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { AttendanceStatus, EventType, Role } from '../types/enums';

export async function listEvents(req: Request, res: Response) {
  const { teamId, role, id: userId } = req.user!;

  let attendanceInclude: boolean | { where: { playerId: { in: string[] } } } = true;
  if (role === Role.PARENT) {
    const links = await prisma.parentPlayerLink.findMany({
      where: { parentId: userId },
      select: { playerId: true },
    });
    const playerIds = links.map((link: { playerId: string }) => link.playerId);
    attendanceInclude = { where: { playerId: { in: playerIds } } };
  }

  const events = await prisma.event.findMany({
    where: { teamId },
    orderBy: { startAt: 'asc' },
    include: {
      matchDetails: true,
      attendance: attendanceInclude,
      squads: { include: { members: true } },
    },
  });

  return res.json(events);
}

export async function getEvent(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;

  const event = await prisma.event.findFirst({
    where: { id, teamId },
    include: { matchDetails: true, attendance: true, squads: { include: { members: true } } },
  });

  if (!event) return res.status(404).json({ message: 'Event not found' });
  return res.json(event);
}

export async function createEvent(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { type, title, startAt, endAt, location, description } = req.body;

  if (!type || !title || !startAt || !location) {
    return res.status(400).json({ message: 'type, title, startAt, location required' });
  }

  const normalizedType =
    type === EventType.MATCH || type === 'MATCH'
      ? EventType.MATCH
      : type === EventType.EVENT || type === 'EVENT'
        ? EventType.EVENT
        : EventType.TRAINING;

  const event = await prisma.event.create({
    data: {
      teamId,
      type: normalizedType,
      title,
      startAt: new Date(startAt),
      endAt: endAt ? new Date(endAt) : undefined,
      location,
      description,
    },
  });

  return res.status(201).json(event);
}

export async function updateEvent(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;
  const { type, title, startAt, endAt, location, description } = req.body;

  const event = await prisma.event.findFirst({ where: { id, teamId } });
  if (!event) return res.status(404).json({ message: 'Event not found' });

  const normalizedType =
    type === EventType.MATCH || type === 'MATCH'
      ? EventType.MATCH
      : type === EventType.EVENT || type === 'EVENT'
        ? EventType.EVENT
        : type === EventType.TRAINING || type === 'TRAINING'
          ? EventType.TRAINING
          : undefined;

  const updated = await prisma.event.update({
    where: { id },
    data: {
      type: normalizedType,
      title,
      startAt: startAt ? new Date(startAt) : undefined,
      endAt: endAt ? new Date(endAt) : undefined,
      location,
      description,
    },
  });

  return res.json(updated);
}

export async function deleteEvent(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;

  const event = await prisma.event.findFirst({ where: { id, teamId } });
  if (!event) return res.status(404).json({ message: 'Event not found' });

  await prisma.event.delete({ where: { id } });
  return res.status(204).send();
}

export async function setAttendance(req: Request, res: Response) {
  const { teamId, role, id: userId } = req.user!;
  const { id } = req.params;
  const { playerId, status } = req.body as { playerId?: string; status?: string };

  if (!playerId || !status) {
    return res.status(400).json({ message: 'playerId and status required' });
  }

  const event = await prisma.event.findFirst({ where: { id, teamId } });
  if (!event) return res.status(404).json({ message: 'Event not found' });

  const player = await prisma.player.findFirst({ where: { id: playerId, teamId } });
  if (!player) return res.status(404).json({ message: 'Player not found' });

  if (role === Role.PARENT) {
    const link = await prisma.parentPlayerLink.findFirst({
      where: { parentId: userId, playerId },
    });
    if (!link) return res.status(403).json({ message: 'Not assigned to player' });
  }

  const normalizedStatus =
    status === AttendanceStatus.YES || status === 'YES'
      ? AttendanceStatus.YES
      : status === AttendanceStatus.NO || status === 'NO'
        ? AttendanceStatus.NO
        : status === AttendanceStatus.MAYBE || status === 'MAYBE'
          ? AttendanceStatus.MAYBE
          : AttendanceStatus.UNKNOWN;

  const attendance = await prisma.attendance.upsert({
    where: { eventId_playerId: { eventId: id, playerId } },
    update: { status: normalizedStatus },
    create: { eventId: id, playerId, status: normalizedStatus },
  });

  return res.json(attendance);
}

export async function finalizeAttendance(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;

  const event = await prisma.event.findFirst({ where: { id, teamId } });
  if (!event) return res.status(404).json({ message: 'Event not found' });

  const updated = await prisma.event.update({
    where: { id },
    data: { attendanceFinalized: true },
  });

  return res.json(updated);
}

export async function upsertMatchDetails(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;
  const { opponent, isHome, competition, notes, ourGoals, theirGoals } = req.body;

  const event = await prisma.event.findFirst({ where: { id, teamId } });
  if (!event) return res.status(404).json({ message: 'Event not found' });

  const details = await prisma.matchDetails.upsert({
    where: { eventId: id },
    update: { opponent, isHome, competition, notes, ourGoals, theirGoals },
    create: {
      eventId: id,
      opponent: opponent ?? 'Unbekannt',
      isHome: isHome ?? true,
      competition,
      notes,
      ourGoals,
      theirGoals,
    },
  });

  return res.json(details);
}

export async function upsertSquad(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;
  const { name, formation, playerIds } = req.body as {
    name?: string;
    formation?: string;
    playerIds?: string[];
  };

  const event = await prisma.event.findFirst({ where: { id, teamId } });
  if (!event) return res.status(404).json({ message: 'Event not found' });

  const existingSquad = await prisma.squad.findFirst({ where: { eventId: id } });
  const squad = existingSquad
    ? await prisma.squad.update({
        where: { id: existingSquad.id },
        data: { name, formation },
      })
    : await prisma.squad.create({
        data: { eventId: id, name, formation },
      });

  if (playerIds) {
    await prisma.squadMember.deleteMany({ where: { squadId: squad.id } });
    if (playerIds.length > 0) {
      await prisma.squadMember.createMany({
        data: playerIds.map((playerId) => ({ squadId: squad.id, playerId })),
        skipDuplicates: true,
      });
    }
  }

  const updated = await prisma.squad.findUnique({
    where: { id: squad.id },
    include: { members: true },
  });

  return res.json(updated);
}
