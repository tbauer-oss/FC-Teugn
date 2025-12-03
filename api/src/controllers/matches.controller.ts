import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { RSVPStatus } from '../types/enums';

export async function listMatches(req: Request, res: Response) {
  const { type } = req.query;
  const where: any = {};
  if (type) where.type = type;

  const matches = await prisma.match.findMany({
    where,
    orderBy: { date: 'asc' },
    include: {
      rsvps: true,
      goals: true,
      lineups: {
        include: { positions: true },
      },
    },
  });

  res.json(matches);
}

export async function createMatch(req: Request, res: Response) {
  const { type, date, kickOff, location, opponent, isHome, competition, notes } = req.body;

  const match = await prisma.match.create({
    data: {
      type,
      date: new Date(date),
      kickOff: new Date(kickOff),
      location,
      opponent,
      isHome,
      competition,
      notes,
    },
  });

  res.status(201).json(match);
}

export async function updateMatch(req: Request, res: Response) {
  const { matchId } = req.params;
  const { date, kickOff, location, opponent, isHome, competition, notes, ourGoals, theirGoals } = req.body;

  const match = await prisma.match.update({
    where: { id: matchId },
    data: {
      date: date ? new Date(date) : undefined,
      kickOff: kickOff ? new Date(kickOff) : undefined,
      location,
      opponent,
      isHome,
      competition,
      notes,
      ourGoals,
      theirGoals,
    },
  });

  res.json(match);
}

export async function deleteMatch(req: Request, res: Response) {
  const { matchId } = req.params;
  await prisma.match.delete({ where: { id: matchId } });
  res.status(204).send();
}

export async function setMatchRSVP(req: Request, res: Response) {
  const { matchId } = req.params;
  const { playerId, status } = req.body as { playerId: string; status: RSVPStatus };

  const rsvp = await prisma.matchRSVP.upsert({
    where: { matchId_playerId: { matchId, playerId } },
    update: { status },
    create: { matchId, playerId, status },
  });

  res.json(rsvp);
}

export async function saveLineup(req: Request, res: Response) {
  const { matchId } = req.params;
  const { name, formation, positions } = req.body as {
    name?: string;
    formation?: string;
    positions: { playerId: string; posX: number; posY: number; isSubstitute?: boolean }[];
  };

  const lineup = await prisma.matchLineup.create({
    data: {
      matchId,
      name,
      formation,
      positions: {
        create: positions.map((p) => ({
          playerId: p.playerId,
          posX: p.posX,
          posY: p.posY,
          isSubstitute: !!p.isSubstitute,
        })),
      },
    },
    include: { positions: true },
  });

  res.status(201).json(lineup);
}

export async function toggleGoal(req: Request, res: Response) {
  const { matchId } = req.params;
  const { playerId } = req.body as { playerId: string };

  const lastGoal = await prisma.matchGoal.findFirst({
    where: { matchId, playerId },
    orderBy: { createdAt: 'desc' },
  });

  if (lastGoal) {
    await prisma.matchGoal.delete({ where: { id: lastGoal.id } });
    return res.json({ removedGoalId: lastGoal.id });
  } else {
    const goal = await prisma.matchGoal.create({
      data: { matchId, playerId },
    });
    return res.status(201).json(goal);
  }
}
