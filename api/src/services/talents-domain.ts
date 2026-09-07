import { createHash } from 'node:crypto';
import { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { AuthUser } from '../middleware/auth';
import { accessibleTeamIds, ownPlayerIds } from './team-access';
import { hasEffectivePermission, Permission } from '../security/permissions';

export class DomainError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export function textValue(value: unknown, label: string, max = 500) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) {
    throw new DomainError(400, `${label}: Bitte 1 bis ${max} Zeichen eingeben.`);
  }
  return value.trim();
}
export function dateOnly(value: unknown, label = 'Datum') {
  const text = String(value ?? '');
  const parsed = new Date(`${text}T12:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text) || !Number.isFinite(parsed.getTime()) ||
      parsed.toISOString().slice(0, 10) !== text) throw new DomainError(400, `${label} ist ungültig.`);
  return text;
}
export function oneOf<T extends string>(value: unknown, values: readonly T[]): T {
  if (!values.includes(value as T)) throw new DomainError(400, 'Ungültige Auswahl.');
  return value as T;
}
export function stringIds(value: unknown, max = 100): string[] {
  if (!Array.isArray(value) || value.length > max || value.some(v => typeof v !== 'string' || !v || v.length > 100)) {
    throw new DomainError(400, 'Ungültige Auswahl.');
  }
  return [...new Set(value as string[])];
}
export function permitted(user: AuthUser, permission: Permission) {
  return hasEffectivePermission(user.role, permission, user.permissions);
}
export async function requireTeam(user: AuthUser, teamId: string, permission?: Permission) {
  if (!(await accessibleTeamIds(user)).includes(teamId) || (permission && !permitted(user, permission))) {
    throw new DomainError(403, 'Für diese Mannschaft fehlt die Berechtigung.');
  }
  return teamId;
}
export async function requirePlayer(user: AuthUser, id: string, permission: Permission = Permission.MANAGE_PLAYERS) {
  const player = await prisma.player.findUnique({ where: { id } });
  if (!player) throw new DomainError(404, 'Spieler nicht gefunden.');
  const own = (await ownPlayerIds(user)).includes(id);
  const staff = player.teamId != null && permitted(user, permission) &&
    (await accessibleTeamIds(user)).includes(player.teamId);
  if (!own && !staff) throw new DomainError(403, 'Für dieses Spielerprofil fehlt die Berechtigung.');
  return { player, own, staff };
}

/** Persist the operation and its response atomically. Retrying an uncertain
 * request cannot duplicate votes, goals or invitations. */
export async function mutation(req: Request, res: Response,
  operation: (tx: Prisma.TransactionClient) => Promise<unknown>) {
  const key = req.get('x-idempotency-key');
  if (!key || key.length > 160) throw new DomainError(400, 'Die Anfrage benötigt eine eindeutige Vorgangskennung.');
  const userId = req.user!.id;
  const requestHash = createHash('sha256').update(JSON.stringify({
    path: req.originalUrl, method: req.method, body: req.body,
  })).digest('hex');
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const result = await prisma.$transaction(async tx => {
        const existing = await tx.idempotencyRecord.findUnique({
          where: { userId_idempotencyKey: { userId, idempotencyKey: key } },
        });
        if (existing) {
          if (existing.requestHash !== requestHash) throw new DomainError(409, 'Dieser Vorgang wurde bereits anders übermittelt.');
          return existing.responseBody;
        }
        const value = JSON.parse(JSON.stringify(await operation(tx))) as Prisma.InputJsonValue;
        await tx.idempotencyRecord.create({ data: {
          userId, idempotencyKey: key, method: req.method, path: req.originalUrl,
          requestHash, responseStatus: 200, responseBody: value,
          expiresAt: new Date(Date.now() + 7 * 86400000),
        } });
        return value;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 15000 });
      return res.json(result);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError &&
          ['P2034', 'P2002'].includes(error.code) && attempt < 2) continue;
      throw error;
    }
  }
}
export async function audit(tx: Prisma.TransactionClient, user: AuthUser, teamId: string | null,
  action: string, entityId: string, metadata: Prisma.InputJsonValue = {}) {
  await tx.auditLog.create({ data: { actorId: user.id, teamId, action,
    entityType: 'Talents', entityId, metadata } });
}
