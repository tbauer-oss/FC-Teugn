import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export async function listTrainings(_req: Request, res: Response) {
  const trainings = await prisma.training.findMany({
    orderBy: { date: 'asc' },
  });
  res.json(trainings);
}

export async function createTraining(req: Request, res: Response) {
  const { date, startTime, endTime, location, note } = req.body;

  const training = await prisma.training.create({
    data: {
      date: new Date(date),
      startTime: new Date(startTime),
      endTime: endTime ? new Date(endTime) : undefined,
      location,
      note,
    },
  });

  res.status(201).json(training);
}

export async function updateTraining(req: Request, res: Response) {
  const { trainingId } = req.params;
  const { date, startTime, endTime, location, note } = req.body;

  const training = await prisma.training.update({
    where: { id: trainingId },
    data: {
      date: date ? new Date(date) : undefined,
      startTime: startTime ? new Date(startTime) : undefined,
      endTime: endTime ? new Date(endTime) : undefined,
      location,
      note,
    },
  });

  res.json(training);
}

export async function deleteTraining(req: Request, res: Response) {
  const { trainingId } = req.params;
  await prisma.training.delete({ where: { id: trainingId } });
  res.status(204).send();
}
