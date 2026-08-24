import { Request, Response, NextFunction } from 'express';
import { AccountStatus, Role } from '../types/enums';
import {
  effectivePermissionsForUser,
  hasEffectivePermission,
  Permission,
} from '../security/permissions';
import { prisma } from '../lib/prisma';
import { verifyAccessToken } from '../lib/jwt';

export interface AuthUser {
  id: string;
  role: Role;
  status: AccountStatus;
  teamId: string;
  permissions?: string[];
  previewActorId?: string;
  previewActorName?: string;
}

const previewHeader = 'x-view-as-user';
const safePreviewMethods = new Set(['GET', 'HEAD', 'OPTIONS']);

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
    const decoded = verifyAccessToken(token) as AuthUser;
    const requestedPreviewId = req.get(previewHeader)?.trim();
    if (requestedPreviewId) {
      if (decoded.role !== Role.SUPER_ADMIN) {
        return res.status(403).json({
          message: 'Die Vorschau steht nur der Systemadministration zur Verfügung.',
        });
      }
      if (!safePreviewMethods.has(req.method.toUpperCase())) {
        return res.status(403).json({
          message: 'Die Ansicht aus Sicht eines Mitglieds ist schreibgeschützt.',
          readOnlyPreview: true,
        });
      }
    }
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
      select: { id: true, name: true, role: true, status: true, teamId: true },
    });
  } catch (error) {
    next(error);
    return;
  }
  if (!current) {
    return res.status(401).json({ message: 'Account nicht gefunden.' });
  }
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

  const requestedPreviewId = req.get(previewHeader)?.trim();
  if (requestedPreviewId) {
    if (current.role !== Role.SUPER_ADMIN) {
      return res.status(403).json({
        message: 'Die Vorschau steht nur der Systemadministration zur Verfügung.',
      });
    }
    const target = await prisma.user.findUnique({
      where: { id: requestedPreviewId },
      select: { id: true, role: true, status: true, teamId: true },
    });
    if (!target || target.status !== AccountStatus.APPROVED) {
      return res.status(404).json({
        message: 'Das ausgewählte freigegebene Mitglied wurde nicht gefunden.',
      });
    }
    req.user = {
      id: target.id,
      role: target.role as Role,
      status: target.status as AccountStatus,
      teamId: target.teamId,
      permissions: await effectivePermissionsForUser(
        target.id,
        target.role as Role,
      ),
      previewActorId: current.id,
      previewActorName: current.name,
    };
    return next();
  }

  req.user = {
    id: current.id,
    role: current.role as Role,
    status: current.status as AccountStatus,
    teamId: current.teamId,
    permissions: await effectivePermissionsForUser(
      current.id,
      current.role as Role,
    ),
  };

  return next();
}
