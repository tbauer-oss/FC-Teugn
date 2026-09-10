import { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { hasEffectivePermission, Permission } from '../security/permissions';
import { accessibleTeamIds, eventReadScope } from '../services/team-access';
import { validateTacticsDocument } from '../services/tactics-board';

async function mayAccess(req: Request, res: Response) {
  const user = req.user!;
  // Check in the controller as well as the route; a parent ticker delegation
  // or a family release never grants access to this private planning document.
  if (!hasEffectivePermission(user.role, Permission.MANAGE_LINEUPS, user.permissions)) {
    res.status(403).json({ message: 'Das Taktikboard ist nur für das Trainerteam verfügbar.' });
    return false;
  }
  const teams = await accessibleTeamIds(user);
  const match = await prisma.event.findFirst({
    where: { id: req.params.id, type: 'MATCH', ...eventReadScope(teams) }, select: { id: true },
  });
  if (!match) { res.status(404).json({ message: 'Spiel nicht gefunden.' }); return false; }
  return true;
}

export async function getTacticsBoard(req: Request, res: Response) {
  if (!await mayAccess(req, res)) return;
  res.setHeader('Cache-Control', 'private, no-store');
  const board = await prisma.matchTacticsBoard.findUnique({ where: { eventId: req.params.id },
    select: { document: true, revision: true, updatedAt: true } });
  return res.json(board ?? { document: null, revision: 0, updatedAt: null });
}

export async function saveTacticsBoard(req: Request, res: Response) {
  if (!await mayAccess(req, res)) return;
  const revision = req.body?.revision;
  if (!Number.isSafeInteger(revision) || revision < 0) {
    return res.status(400).json({ message: 'Ungültiger Speicherstand.' });
  }
  let document: Prisma.InputJsonObject;
  try { document = validateTacticsDocument(req.body?.document); }
  catch { return res.status(400).json({ message: 'Ungültiges Taktikboard oder Zeichenlimit erreicht.' }); }
  const conflict = () => res.status(409).json({ code: 'TACTICS_CONFLICT',
    message: 'Ein anderer Trainer hat das Board geändert. Dein Entwurf wurde nicht überschrieben. Bitte zuerst den aktuellen Stand laden.' });
  try {
    if (revision === 0) {
      // INSERT ON CONFLICT avoids both a failed transaction and a read/create
      // race when two coaches save a new board simultaneously.
      const created = await prisma.matchTacticsBoard.createMany({ data: [{ eventId: req.params.id,
        document, updatedById: req.user!.id }], skipDuplicates: true });
      if (!created.count) return conflict();
    } else {
      const result = await prisma.matchTacticsBoard.updateMany({
        where: { eventId: req.params.id, revision },
        data: { document, revision: { increment: 1 }, updatedById: req.user!.id },
      });
      if (!result.count) return conflict();
    }
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') return conflict();
    throw error;
  }
  // Return this write's version, not a subsequent concurrent trainer's save.
  return res.json({ revision: revision + 1 });
}
