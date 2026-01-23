import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { Role } from '../types/enums';

export async function listPlayers(req: Request, res: Response) {
  const { teamId, role, id: userId } = req.user!;

  if (role === Role.PARENT) {
    const links = await prisma.parentPlayerLink.findMany({
      where: { parentId: userId },
      include: { player: true },
    });
    const players = links.map((link: { player: { id: string } }) => link.player);
    return res.json(players);
  }

  const players = await prisma.player.findMany({
    where: { teamId },
    orderBy: { lastName: 'asc' },
  });
  return res.json(players);
}

export async function getPlayer(req: Request, res: Response) {
  const { teamId, role, id: userId } = req.user!;
  const { id } = req.params;

  if (role === Role.PARENT) {
    const link = await prisma.parentPlayerLink.findFirst({
      where: { parentId: userId, playerId: id },
      include: { player: true },
    });
    if (!link) return res.status(404).json({ message: 'Player not found' });
    return res.json(link.player);
  }

  const player = await prisma.player.findFirst({ where: { id, teamId } });
  if (!player) return res.status(404).json({ message: 'Player not found' });
  return res.json(player);
}

export async function createPlayer(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { firstName, lastName, birthDate, position, shirtNumber, parentId } = req.body;

  if (!firstName || !lastName) {
    return res.status(400).json({ message: 'firstName and lastName required' });
  }

  const player = await prisma.player.create({
    data: {
      teamId,
      firstName,
      lastName,
      birthDate: birthDate ? new Date(birthDate) : undefined,
      position,
      shirtNumber,
    },
  });

  if (parentId) {
    await prisma.parentPlayerLink.upsert({
      where: { parentId_playerId: { parentId, playerId: player.id } },
      update: {},
      create: { parentId, playerId: player.id },
    });
  }

  return res.status(201).json(player);
}

export async function updatePlayer(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;
  const { firstName, lastName, birthDate, position, shirtNumber } = req.body;

  const player = await prisma.player.findFirst({ where: { id, teamId } });
  if (!player) return res.status(404).json({ message: 'Player not found' });

  const updated = await prisma.player.update({
    where: { id },
    data: {
      firstName,
      lastName,
      birthDate: birthDate ? new Date(birthDate) : undefined,
      position,
      shirtNumber,
    },
  });

  return res.json(updated);
}

export async function deletePlayer(req: Request, res: Response) {
  const { teamId } = req.user!;
  const { id } = req.params;

  const player = await prisma.player.findFirst({ where: { id, teamId } });
  if (!player) return res.status(404).json({ message: 'Player not found' });

  await prisma.player.delete({ where: { id } });
  return res.status(204).send();
}
