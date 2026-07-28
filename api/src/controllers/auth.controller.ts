import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hashPassword, comparePassword } from '../lib/password';
import { signAccessToken } from '../lib/jwt';
import { AccountStatus, Role } from '../types/enums';

async function resolveTeamId(teamName?: string, teamId?: string) {
  if (teamId) {
    const selected = await prisma.team.findFirst({
      where: { id: teamId, isActive: true },
    });
    if (selected) return selected.id;
  }

  const name = teamName?.trim() || 'FC Teugn';
  const existing = await prisma.team.findFirst({
    where: { name: { equals: name, mode: 'insensitive' }, isActive: true },
  });
  if (existing) return existing.id;
  const fallback = await prisma.team.findFirst({
    where: { isActive: true, ageGroup: { season: { isActive: true } } },
    orderBy: { createdAt: 'asc' },
  });
  if (!fallback) {
    throw new Error('No active team configured');
  }
  return fallback.id;
}

export async function register(req: Request, res: Response) {
  const { email, password, name, phone, role, teamName, teamId } = req.body;
  if (!email || !password || !name) {
    return res.status(400).json({ message: 'Missing required fields' });
  }

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    return res.status(400).json({ message: 'E-Mail bereits vergeben' });
  }

  const normalizedRole =
    role === Role.COACH ||
    role === Role.TRAINER ||
    role === Role.TRAINER_ADMIN ||
    role === 'TRAINER'
      ? Role.COACH
      : role === Role.ASSISTANT_COACH
        ? Role.ASSISTANT_COACH
        : role === Role.TEAM_MANAGER
          ? Role.TEAM_MANAGER
          : role === Role.PLAYER
            ? Role.PLAYER
            : Role.PARENT;

  const resolvedTeamId = await resolveTeamId(teamName, teamId);
  const resolvedTeam = await prisma.team.findUnique({
    where: { id: resolvedTeamId },
    include: { ageGroup: { include: { season: true } } },
  });
  if (!resolvedTeam) {
    return res.status(400).json({ message: 'Mannschaft nicht gefunden' });
  }
  const isFirstClubUser =
    (await prisma.user.count({
      where: {
        team: {
          ageGroup: { season: { clubId: resolvedTeam.ageGroup.season.clubId } },
        },
      },
    })) === 0;
  const hashed = await hashPassword(password);
  const user = await prisma.$transaction(async (tx) => {
    const created = await tx.user.create({
      data: {
        email,
        password: hashed,
        name,
        phone,
        role: isFirstClubUser ? Role.CLUB_ADMIN : normalizedRole,
        status: isFirstClubUser ? AccountStatus.APPROVED : AccountStatus.PENDING,
        teamId: resolvedTeamId,
      },
    });
    await tx.teamMembership.create({
      data: {
        userId: created.id,
        teamId: created.teamId,
        role: created.role,
        status: created.status,
      },
    });
    return created;
  });

  const accessToken = signAccessToken({
    id: user.id,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  });

  return res.status(201).json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      role: user.role,
      status: user.status,
      teamId: user.teamId,
    },
    accessToken,
  });
}

export async function login(req: Request, res: Response) {
  const { email, password } = req.body;

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    return res.status(400).json({ message: 'Ungültige Zugangsdaten' });
  }

  const ok = await comparePassword(password, user.password);
  if (!ok) {
    return res.status(400).json({ message: 'Ungültige Zugangsdaten' });
  }

  if (user.status === AccountStatus.BLOCKED) {
    return res.status(403).json({ message: 'Account blockiert' });
  }

  const accessToken = signAccessToken({
    id: user.id,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  });

  return res.json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      role: user.role,
      status: user.status,
      teamId: user.teamId,
    },
    accessToken,
  });
}

export async function me(req: Request, res: Response) {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return res.status(404).json({ message: 'User not found' });

  return res.json({
    id: user.id,
    email: user.email,
    name: user.name,
    phone: user.phone,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  });
}
