import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { RSVPStatus } from '@prisma/client';

export async function listEvents(_req: Request, res: Response) {
  const events = await prisma.event.findMany({
    orderBy: { date: 'asc' },
    include: { rsvps: true },
  });
  res.json(events);
}

export async function createEvent(req: Request, res: Response) {
  const { title, date, startTime, location, description, rsvpEnabled } = req.body;

  const event = await prisma.event.create({
    data: {
      title,
      date: new Date(date),
      startTime: startTime ? new Date(startTime) : undefined,
      location,
      description,
      rsvpEnabled: rsvpEnabled ?? true,
    },
  });

  res.status(201).json(event);
}

export async function updateEvent(req: Request, res: Response) {
  const { eventId } = req.params;
  const { title, date, startTime, location, description, rsvpEnabled } = req.body;

  const event = await prisma.event.update({
    where: { id: eventId },
    data: {
      title,
      date: date ? new Date(date) : undefined,
      startTime: startTime ? new Date(startTime) : undefined,
      location,
      description,
      rsvpEnabled,
    },
  });

  res.json(event);
}

export async function deleteEvent(req: Request, res: Response) {
  const { eventId } = req.params;
  await prisma.event.delete({ where: { id: eventId } });
  res.status(204).send();
}

export async function setEventRSVP(req: Request, res: Response) {
  const { eventId } = req.params;
  const { userId, status } = req.body as { userId: string; status: RSVPStatus };

  const rsvp = await prisma.eventRSVP.upsert({
    where: { eventId_userId: { eventId, userId } },
    update: { status },
    create: { eventId, userId, status },
  });

  res.json(rsvp);
}
