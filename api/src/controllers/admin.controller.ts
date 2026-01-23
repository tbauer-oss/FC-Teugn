import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { AccountStatus, Role } from '../types/enums';

export async function pendingUsers(req: Request, res: Response) {
  const teamId = req.user!.teamId;
  const users = await prisma.user.findMany({
    where: { teamId, status: AccountStatus.PENDING },
    orderBy: { createdAt: 'asc' },
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      status: true,
      createdAt: true,
    },
  });

  return res.json(users);
}

export async function approveUser(req: Request, res: Response) {
  const { userId, status } = req.body as { userId?: string; status?: AccountStatus };
  if (!userId) {
    return res.status(400).json({ message: 'userId required' });
  }

  const teamId = req.user!.teamId;
  const target = await prisma.user.findFirst({ where: { id: userId, teamId } });
  if (!target) {
    return res.status(404).json({ message: 'User not found' });
  }

  const nextStatus =
    status === AccountStatus.BLOCKED || status === AccountStatus.APPROVED
      ? status
      : AccountStatus.APPROVED;

  const updated = await prisma.user.update({
    where: { id: target.id },
    data: { status: nextStatus },
    select: { id: true, email: true, name: true, role: true, status: true },
  });

  return res.json(updated);
}

export async function assignParentPlayer(req: Request, res: Response) {
  const { parentId, playerId } = req.body as { parentId?: string; playerId?: string };
  if (!parentId || !playerId) {
    return res.status(400).json({ message: 'parentId and playerId required' });
  }

  const teamId = req.user!.teamId;
  const [parent, player] = await Promise.all([
    prisma.user.findFirst({ where: { id: parentId, teamId } }),
    prisma.player.findFirst({ where: { id: playerId, teamId } }),
  ]);

  if (!parent || parent.role !== Role.PARENT) {
    return res.status(404).json({ message: 'Parent not found' });
  }

  if (!player) {
    return res.status(404).json({ message: 'Player not found' });
  }

  const link = await prisma.parentPlayerLink.upsert({
    where: { parentId_playerId: { parentId, playerId } },
    update: {},
    create: { parentId, playerId },
  });

  return res.status(201).json(link);
}
