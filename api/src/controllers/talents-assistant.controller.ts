import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, ownPlayerIds } from '../services/team-access';

export async function assistantTasks(req: Request, res: Response) {
  const teams = await accessibleTeamIds(req.user!);
  const own = await ownPlayerIds(req.user!);
  const [tasks, duties] = await Promise.all([
    prisma.teamTask.findMany({ where: { teamId: { in: teams }, assigneeUserId: req.user!.id,
      status: { notIn: ['DONE', 'CANCELLED'] } }, orderBy: { dueAt: 'asc' }, take: 200 }),
    prisma.kitLaundryDuty.findMany({ where: { assignedPlayerId: { in: own }, status: { in: ['PROPOSED', 'CONFIRMED'] },
      event: { status: { not: 'CANCELLED' }, visibility: { not: 'STAFF_ONLY' }, familyReleasedAt: { not: null },
        startAt: { gte: new Date(Date.now() - 14 * 86400000) } } }, include: { event: { select: { title: true, startAt: true } },
        assignedPlayer: { select: { firstName: true, lastName: true } } }, take: 100 }),
  ]);
  return res.json([
    ...tasks.map(t => ({ id: `task:${t.id}`, title: t.title, detail: 'Übernommene Teamaufgabe', dueAt: t.dueAt,
      route: `/operations?teamId=${t.teamId}&taskId=${t.id}` })),
    ...duties.map(d => ({ id: `duty:${d.id}`, title: d.status === 'PROPOSED' ? 'Trikotdienst bestätigen' : 'Trikotdienst erledigen',
      detail: `${d.assignedPlayer?.firstName ?? ''} · ${d.event.title}`, dueAt: d.event.startAt, playerId: d.assignedPlayerId,
      route: `/matches/${d.eventId}?tab=overview` })),
  ]);
}
