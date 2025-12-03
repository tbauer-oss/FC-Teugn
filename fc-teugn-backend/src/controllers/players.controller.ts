import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export async function listPlayers(_req: Request, res: Response) {
  const players = await prisma.player.findMany();
  res.json(players);
}

export async function createPlayer(req: Request, res: Response) {
  const { firstName, lastName, birthDate, gender, position, shirtNumber, photoUrl, team } = req.body;

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
    },
  });

  res.status(201).json(player);
}

export async function updatePlayer(req: Request, res: Response) {
  const { playerId } = req.params;
  const { firstName, lastName, birthDate, gender, position, shirtNumber, photoUrl, team } = req.body;

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
    },
  });

  res.json(player);
}

export async function deletePlayer(req: Request, res: Response) {
  const { playerId } = req.params;
  await prisma.player.delete({ where: { id: playerId } });
  res.status(204).send();
}
