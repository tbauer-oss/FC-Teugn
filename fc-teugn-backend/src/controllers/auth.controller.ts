import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hashPassword, comparePassword } from '../lib/password';
import { signAccessToken, signRefreshToken } from '../lib/jwt';
import { Role } from '@prisma/client';
import jwt from 'jsonwebtoken';

export async function register(req: Request, res: Response) {
  const { email, password, name, phone, role } = req.body;
  if (!email || !password || !name) {
    return res.status(400).json({ message: 'Missing required fields' });
  }

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    return res.status(400).json({ message: 'E-Mail bereits vergeben' });
  }

  const normalizedRole =
    role === Role.COACH || role === 'COACH' ? Role.COACH : Role.PARENT;

  const hashed = await hashPassword(password);
  const user = await prisma.user.create({
    data: { email, password: hashed, name, phone, role: normalizedRole },
  });

  const accessToken = signAccessToken({ id: user.id, role: user.role });
  const refreshToken = signRefreshToken({ id: user.id, role: user.role });

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });

  return res.status(201).json({
    user: { id: user.id, email: user.email, name: user.name, role: user.role },
    accessToken,
    refreshToken,
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

  const accessToken = signAccessToken({ id: user.id, role: user.role });
  const refreshToken = signRefreshToken({ id: user.id, role: user.role });

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });

  return res.json({
    user: { id: user.id, email: user.email, name: user.name, role: user.role },
    accessToken,
    refreshToken,
  });
}

export async function refresh(req: Request, res: Response) {
  const { token } = req.body as { token?: string };
  if (!token) return res.status(400).json({ message: 'Kein Refresh Token übergeben' });

  const stored = await prisma.refreshToken.findUnique({ where: { token } });
  if (!stored || stored.expiresAt < new Date()) {
    return res.status(401).json({ message: 'Refresh Token ungültig' });
  }

  try {
    const decoded = jwt.verify(token, process.env.REFRESH_TOKEN_SECRET || 'refresh_secret') as {
      id: string;
      role: Role;
    };

    const accessToken = signAccessToken({ id: decoded.id, role: decoded.role });
    res.json({ accessToken });
  } catch (err) {
    res.status(401).json({ message: 'Refresh Token ungültig' });
  }
}
