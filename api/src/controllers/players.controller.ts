import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export async function listPlayers(_req: Request, res: Response) {
  const players = await prisma.player.findMany({
    include: {
      userLinks: {
        include: { user: true },
      },
      matchRsvps: true,
      goals: true,
    },
  });
  res.json(players);
}

export async function createPlayer(req: Request, res: Response) {
  const { firstName, lastName, birthDate, gender, position, shirtNumber, photoUrl, team, parentUserId } = req.body;

  const player = await prisma.player.create({
    data: {
      firstName,
      lastName,
      birthDate: new Date(birthDate),
      gender,
      position,
      shirtNumber,
      photoUrl,
      team,
      userLinks: parentUserId
        ? { create: { userId: parentUserId, relation: 'parent' } }
        : undefined,
    },
    include: { userLinks: { include: { user: true } } },
  });

  res.status(201).json(player);
}

export async function updatePlayer(req: Request, res: Response) {
  const { playerId } = req.params;
  const { firstName, lastName, birthDate, gender, position, shirtNumber, photoUrl, team, parentUserId } = req.body;

  const player = await prisma.player.update({
    where: { id: playerId },
    data: {
      firstName,
      lastName,
      birthDate: birthDate ? new Date(birthDate) : undefined,
      gender,
      position,
      shirtNumber,
      photoUrl,
      team,
      userLinks: parentUserId
        ? {
            upsert: {
              where: { userId_playerId: { playerId, userId: parentUserId } },
              update: {},
              create: { userId: parentUserId, relation: 'parent' },
            },
          }
        : undefined,
    },
    include: { userLinks: { include: { user: true } } },
  });

  res.json(player);
}

export async function deletePlayer(req: Request, res: Response) {
  const { playerId } = req.params;
  await prisma.player.delete({ where: { id: playerId } });
  res.status(204).send();
}
