import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, ownPlayerIds } from '../services/team-access';
import { Permission } from '../security/permissions';
import { audit, dateOnly, DomainError, mutation, oneOf, permitted, requirePlayer, stringIds, textValue } from '../services/talents-domain';

export async function listGoals(req: Request, res: Response) {
  const own = await ownPlayerIds(req.user!);
  const teams = permitted(req.user!, Permission.MANAGE_DEVELOPMENT) ? await accessibleTeamIds(req.user!) : [];
  const goals = await prisma.learningGoal.findMany({ where: { OR: [
    { teamId: { in: teams } }, { playerId: { in: own }, visibility: 'FAMILY' },
  ] }, include: { player: { select: { id: true, firstName: true, lastName: true, preferredName: true } },
    observations: { orderBy: { createdAt: 'desc' } } }, orderBy: [{ status: 'asc' }, { endsOn: 'asc' }], take: 300 });
  return res.json(goals.map(goal => ({ ...goal, canManage: teams.includes(goal.teamId) })));
}
export async function saveGoal(req: Request, res: Response) {
  const { player, staff } = await requirePlayer(req.user!, String(req.body.playerId ?? ''), Permission.MANAGE_DEVELOPMENT);
  if (!staff || !player.teamId) throw new DomainError(403, 'Entwicklungsziele werden vom zuständigen Trainerteam gepflegt.');
  const startsOn = dateOnly(req.body.startsOn, 'Beginn'), endsOn = dateOnly(req.body.endsOn, 'Zieltermin');
  if (endsOn < startsOn) throw new DomainError(400, 'Der Zieltermin liegt vor dem Beginn.');
  const exerciseIds = stringIds(req.body.exerciseIds ?? [], 20);
  const trainingPlanIds = stringIds(req.body.trainingPlanIds ?? [], 20);
  const teamId = player.teamId;
  const responsibleUserId = String(req.body.responsibleUserId ?? req.user!.id);
  return mutation(req, res, async tx => {
    const responsible = await tx.user.findFirst({ where: { id: responsibleUserId, status: 'APPROVED',
      role: { in: ['SUPER_ADMIN', 'CLUB_ADMIN', 'YOUTH_DIRECTOR', 'TRAINER_ADMIN', 'COACH', 'TRAINER', 'ASSISTANT_COACH'] },
      OR: [{ teamId }, { memberships: { some: { teamId, status: 'APPROVED' } } }],
    } });
    if (!responsible) throw new DomainError(400, 'Bitte einen zuständigen Trainer auswählen.');
    if (await tx.trainingExercise.count({ where: { id: { in: exerciseIds }, teamId, isArchived: false } }) !== exerciseIds.length ||
      await tx.trainingPlan.count({ where: { id: { in: trainingPlanIds }, event: { teamId } } }) !== trainingPlanIds.length) throw new DomainError(400, 'Eine Übung oder ein Trainingsplan gehört nicht zur Mannschaft.');
    const id = req.params.id;
    if (id && !(await tx.learningGoal.findFirst({ where: { id, playerId: player.id, teamId } }))) throw new DomainError(404, 'Lernziel nicht gefunden.');
    const status = oneOf(req.body.status ?? 'ACTIVE', ['ACTIVE', 'COMPLETED', 'ARCHIVED']);
    if (status === 'ACTIVE' && await tx.learningGoal.count({ where: { playerId: player.id, status: 'ACTIVE', ...(id ? { id: { not: id } } : {}) } }) >= 3) throw new DomainError(409, 'Bitte zuerst ein Ziel abschließen. Pro Kind sind drei aktive Ziele möglich.');
    const data = { playerId: player.id, teamId, responsibleUserId,
      title: textValue(req.body.title, 'Lernziel', 160), description: textValue(req.body.description, 'Beschreibung', 2000),
      startsOn, endsOn, visibility: oneOf(req.body.visibility, ['STAFF_ONLY', 'FAMILY']), status, exerciseIds, trainingPlanIds };
    const result = id ? await tx.learningGoal.update({ where: { id }, data }) : await tx.learningGoal.create({ data: { ...data, authorId: req.user!.id } });
    await audit(tx, req.user!, teamId, 'LEARNING_GOAL_SAVED', result.id);
    return result;
  });
}
export async function observeGoal(req: Request, res: Response) {
  const goal = await prisma.learningGoal.findUnique({ where: { id: req.params.id } });
  if (!goal) throw new DomainError(404, 'Lernziel nicht gefunden.');
  const { staff } = await requirePlayer(req.user!, goal.playerId, Permission.MANAGE_DEVELOPMENT);
  if (!staff || !(await accessibleTeamIds(req.user!)).includes(goal.teamId)) throw new DomainError(403, 'Keine Berechtigung zur Beobachtung.');
  const progress = Number(req.body.progress);
  if (!Number.isInteger(progress) || progress < 0 || progress > 100) throw new DomainError(400, 'Fortschritt muss zwischen 0 und 100 liegen.');
  return mutation(req, res, async tx => {
    const current = await tx.learningGoal.findUniqueOrThrow({ where: { id: goal.id } });
    if (current.status !== 'ACTIVE') throw new DomainError(409, 'Das Ziel ist bereits abgeschlossen.');
    const result = await tx.goalObservation.create({ data: { goalId: goal.id, authorId: req.user!.id,
      note: textValue(req.body.note, 'Beobachtung', 2000), progress } });
    await audit(tx, req.user!, goal.teamId, 'LEARNING_GOAL_OBSERVED', goal.id);
    return result;
  });
}
