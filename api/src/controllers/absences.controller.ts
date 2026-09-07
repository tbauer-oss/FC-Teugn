import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, ownPlayerIds } from '../services/team-access';
import { audit, dateOnly, DomainError, mutation, oneOf, permitted, requirePlayer, stringIds } from '../services/talents-domain';
import { Permission } from '../security/permissions';
import { reconcilePlayerAbsences } from '../services/absence.service';

export async function listAbsences(req: Request, res: Response) {
  const own = await ownPlayerIds(req.user!);
  const staffTeams = permitted(req.user!, Permission.MANAGE_PLAYERS) ? await accessibleTeamIds(req.user!) : [];
  const players = await prisma.player.findMany({ where: { OR: [{ id: { in: own } }, { teamId: { in: staffTeams } }] },
    select: { id: true, teamId: true, firstName: true, lastName: true, preferredName: true,
      absences: { orderBy: { startsOn: 'desc' }, take: 100 } } });
  return res.json({ players });
}
export async function saveAbsence(req: Request, res: Response) {
  if (!permitted(req.user!, Permission.RESPOND_ATTENDANCE)) throw new DomainError(403, 'Keine Berechtigung für Rückmeldungen.');
  const playerId = String(req.body?.playerId ?? '');
  const { player } = await requirePlayer(req.user!, playerId);
  const startsOn = dateOnly(req.body.startsOn, 'Beginn');
  const endsOn = dateOnly(req.body.endsOn, 'Ende');
  if (endsOn < startsOn || new Date(endsOn).getTime() - new Date(startsOn).getTime() > 366 * 86400000) throw new DomainError(400, 'Eine Abwesenheit darf höchstens ein Jahr dauern; das Ende muss nach dem Beginn liegen.');
  const weekdays = req.body.weekdays ?? [];
  if (!Array.isArray(weekdays) || weekdays.length > 7 || weekdays.some(v => !Number.isInteger(v) || v < 0 || v > 6)) throw new DomainError(400, 'Ungültige Wochentage.');
  const teamIds = stringIds(req.body.teamIds ?? []);
  const assignments = await prisma.playerSeasonAssignment.findMany({ where: { playerId }, select: { teamId: true } });
  const allowedTeams = new Set([player.teamId, ...assignments.map(a => a.teamId)]);
  if (teamIds.some(id => !allowedTeams.has(id))) throw new DomainError(400, 'Die Auswahl enthält eine fremde Mannschaft.');
  const eventTypes = stringIds(req.body.eventTypes, 2).map(v => oneOf(v, ['TRAINING', 'MATCH']));
  if (!eventTypes.length) throw new DomainError(400, 'Mindestens eine Terminart auswählen.');
  const data = { playerId, startsOn, endsOn, weekdays: [...new Set(weekdays)] as number[], teamIds, eventTypes,
    reason: typeof req.body.reason === 'string' ? req.body.reason.trim().slice(0, 500) || null : null };
  return mutation(req, res, async tx => {
    const id = req.params.id;
    if (id && !(await tx.playerAbsence.findFirst({ where: { id, playerId, endedAt: null } }))) throw new DomainError(404, 'Abwesenheit nicht gefunden.');
    const absence = id ? await tx.playerAbsence.update({ where: { id }, data })
      : await tx.playerAbsence.create({ data: { ...data, createdById: req.user!.id } });
    await reconcilePlayerAbsences(tx, [playerId]);
    await audit(tx, req.user!, player.teamId, 'ABSENCE_SAVED', absence.id);
    return absence;
  });
}
export async function endAbsence(req: Request, res: Response) {
  if (!permitted(req.user!, Permission.RESPOND_ATTENDANCE)) throw new DomainError(403, 'Keine Berechtigung für Rückmeldungen.');
  const absence = await prisma.playerAbsence.findUnique({ where: { id: req.params.id } });
  if (!absence) throw new DomainError(404, 'Abwesenheit nicht gefunden.');
  const { player } = await requirePlayer(req.user!, absence.playerId);
  return mutation(req, res, async tx => {
    const result = await tx.playerAbsence.update({ where: { id: absence.id }, data: { endedAt: new Date() } });
    await reconcilePlayerAbsences(tx, [absence.playerId]);
    await audit(tx, req.user!, player.teamId, 'ABSENCE_ENDED', absence.id);
    return result;
  });
}
