import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, ownPlayerIds } from '../services/team-access';
import { permitted } from '../services/talents-domain';
import { Permission } from '../security/permissions';

export async function talentsOptions(req: Request, res: Response) {
  const teamIds = await accessibleTeamIds(req.user!);
  const own = await ownPlayerIds(req.user!);
  const canDevelop = permitted(req.user!, Permission.MANAGE_DEVELOPMENT);
  const canManage = permitted(req.user!, Permission.MANAGE_PLAYERS);
  const [teams, players, members, exercises, plans] = await Promise.all([
    prisma.team.findMany({ where: { id: { in: teamIds }, deletedAt: null }, select: { id: true, name: true, isActive: true } }),
    prisma.player.findMany({ where: { OR: [{ id: { in: own } }, ...(canManage || canDevelop ? [{ teamId: { in: teamIds } }] : [])] }, select: { id: true, teamId: true, firstName: true, lastName: true, preferredName: true, seasonAssignments: { select: { teamId: true } } } }),
    canManage || canDevelop || permitted(req.user!, Permission.MANAGE_ORGANIZATION) ? prisma.user.findMany({ where: { status: 'APPROVED', OR: [{ teamId: { in: teamIds } }, { memberships: { some: { teamId: { in: teamIds }, status: 'APPROVED' } } }] }, select: { id: true, name: true, role: true, teamId: true, memberships: { where: { status: 'APPROVED', teamId: { in: teamIds } }, select: { teamId: true } } } }) : [],
    canDevelop ? prisma.trainingExercise.findMany({ where: { teamId: { in: teamIds }, isArchived: false }, select: { id: true, title: true, teamId: true }, take: 500 }) : [],
    canDevelop ? prisma.trainingPlan.findMany({ where: { event: { teamId: { in: teamIds } } }, select: { id: true, event: { select: { title: true, startAt: true, teamId: true } } }, take: 100, orderBy: { createdAt: 'desc' } }) : [],
  ]);
  return res.json({ teams, players, members, exercises, plans, ownPlayerIds: own,
    capabilities: { polls: permitted(req.user!, Permission.SEND_ANNOUNCEMENTS), goals: canDevelop,
      invitations: permitted(req.user!, Permission.MANAGE_MEMBERS) } });
}
