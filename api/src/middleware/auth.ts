import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AccountStatus, Role } from '../types/enums';

const ACCESS_SECRET = process.env.ACCESS_TOKEN_SECRET || 'access_secret';

export interface AuthUser {
  id: string;
  role: Role;
  status: AccountStatus;
  teamId: string;
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

export function requireApproved(req: Request, res: Response, next: NextFunction) {
  if (!req.user) {
    return res.status(401).json({ message: 'No user in request' });
  }

  if (req.user.status === AccountStatus.BLOCKED) {
    return res.status(403).json({ message: 'Account blocked' });
  }

  if (req.user.status !== AccountStatus.APPROVED) {
    return res.status(403).json({ message: 'Account pending approval' });
  }

  return next();
}
