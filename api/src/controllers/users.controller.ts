import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { comparePassword, hashPassword } from '../lib/password';

async function buildPlayerStats(playerId: string) {
  const [rsvpCount, goalCount] = await Promise.all([
    prisma.matchRSVP.count({ where: { playerId, status: 'YES' } }),
    prisma.matchGoal.count({ where: { playerId } }),
  ]);

  return {
    gamesPlayed: rsvpCount,
    goals: goalCount,
  };
}

export async function me(req: Request, res: Response) {
  const userId = req.user!.id;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      playerLinks: {
        include: {
          player: true,
        },
      },
    },
  });

  if (!user) return res.status(404).json({ message: 'User not found' });

  const playersWithStats = await Promise.all(
    user.playerLinks.map(async (link: (typeof user.playerLinks)[number]) => ({
      ...link.player,
      stats: await buildPlayerStats(link.playerId),
    })),
  );

  res.json({
    id: user.id,
    email: user.email,
    name: user.name,
    phone: user.phone,
    role: user.role,
    players: playersWithStats,
  });
}

export async function updateProfile(req: Request, res: Response) {
  const userId = req.user!.id;
  const { name, phone } = req.body as { name?: string; phone?: string };

  const updated = await prisma.user.update({
    where: { id: userId },
    data: { name, phone },
    select: { id: true, email: true, name: true, phone: true, role: true },
  });

  res.json(updated);
}

export async function changePassword(req: Request, res: Response) {
  const userId = req.user!.id;
  const { currentPassword, newPassword } = req.body as {
    currentPassword: string;
    newPassword: string;
  };

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return res.status(404).json({ message: 'User not found' });

  const ok = await comparePassword(currentPassword, user.password);
  if (!ok) return res.status(400).json({ message: 'Aktuelles Passwort stimmt nicht' });

  const hashed = await hashPassword(newPassword);
  await prisma.user.update({ where: { id: userId }, data: { password: hashed } });

  res.json({ message: 'Passwort aktualisiert' });
}

export async function deleteAccount(req: Request, res: Response) {
  const userId = req.user!.id;

  await prisma.$transaction([
    prisma.refreshToken.deleteMany({ where: { userId } }),
    prisma.userPlayerLink.deleteMany({ where: { userId } }),
    prisma.user.delete({ where: { id: userId } }),
  ]);

  res.json({ message: 'Account gelöscht' });
}
