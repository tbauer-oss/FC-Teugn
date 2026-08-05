import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AccountStatus, Role } from '../types/enums';
import {
  effectivePermissionsForUser,
  hasEffectivePermission,
  Permission,
} from '../security/permissions';
import { prisma } from '../lib/prisma';

const ACCESS_SECRET =
  process.env.ACCESS_TOKEN_SECRET || process.env.JWT_SECRET || 'access_secret';

export interface AuthUser {
  id: string;
  role: Role;
  status: AccountStatus;
  teamId: string;
  permissions?: string[];
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'No token provided' });
  }

  const token = header.substring(7);
  try {
    const decoded = jwt.verify(token, ACCESS_SECRET) as AuthUser;
    req.user = decoded;
    return next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

export function requireRoles(roles: Role[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    return next();
  };
}

export function requirePermission(permission: Permission) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user || !hasEffectivePermission(
      req.user.role,
      permission,
      req.user.permissions,
    )) {
      return res.status(403).json({
        message: 'Für diese Aktion fehlt die erforderliche Berechtigung.',
        permission,
      });
    }
    return next();
  };
}

export async function requireApproved(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  if (!req.user) {
    return res.status(401).json({ message: 'No user in request' });
  }

  let current;
  try {
    current = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { role: true, status: true, teamId: true },
    });
  } catch (error) {
    next(error);
    return;
  }
  if (!current) {
    return res.status(401).json({ message: 'Account nicht gefunden.' });
  }
  const permissions = await effectivePermissionsForUser(
    req.user.id,
    current.role as Role,
  );
  req.user = {
    id: req.user.id,
    role: current.role as Role,
    status: current.status as AccountStatus,
    teamId: current.teamId,
    permissions,
  };

  if (
    current.status === AccountStatus.BLOCKED ||
    current.status === AccountStatus.REJECTED ||
    current.status === AccountStatus.ARCHIVED
  ) {
    return res.status(403).json({ message: 'Account not active' });
  }

  if (current.status !== AccountStatus.APPROVED) {
    return res.status(403).json({ message: 'Account pending approval' });
  }

  return next();
}
