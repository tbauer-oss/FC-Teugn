import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export async function getLeagueTables(_req: Request, res: Response) {
  const tables = await prisma.leagueTable.findMany({
    include: { rows: true },
  });
  res.json(tables);
}

export async function createLeagueTable(req: Request, res: Response) {
  const { name, season, sourceUrl } = req.body;

  const table = await prisma.leagueTable.create({
    data: {
      name,
      season,
      sourceUrl,
    },
  });

  res.status(201).json(table);
}
