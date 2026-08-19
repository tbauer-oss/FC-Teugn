import { Request, Response } from 'express';
import { processDueReminders } from '../services/reminder.service';
import { processDueAnnouncements } from './communications.controller';
import { processDueBfvSyncs } from '../services/bfv-sync.service';
import { applyOperationalRetention } from '../services/privacy-retention.service';
import { retryPendingPushDeliveries } from '../services/notification.service';
import { prisma } from '../lib/prisma';
import { ensureNextRegularTrainingOccurrences } from '../services/regular-training-occurrence.service';

export async function processScheduledJobs(req: Request, res: Response) {
  const configuredSecret = process.env.CRON_SECRET?.trim();
  const authorization = req.headers.authorization;
  if (!configuredSecret || authorization !== `Bearer ${configuredSecret}`) {
    return res.status(401).json({ message: 'Cron-Autorisierung fehlgeschlagen.' });
  }
  await processDueAnnouncements();
  const [reminders, bfvSyncs, retention] = await Promise.all([
    processDueReminders(),
    processDueBfvSyncs(new Date(), 1),
    applyOperationalRetention(),
  ]);
  // Erinnerungen und geplante Mitteilungen legen ihre Zustellungen oberhalb an.
  // Danach werden auch vorübergehend fehlgeschlagene Pushes aller Kategorien
  // erneut versendet, ohne dass der Empfänger zuerst die App öffnen muss.
  const pushRetries = await retryPendingPushDeliveries();
  return res.json({ reminders, pushRetries, bfvSyncs, retention });
}

export async function processRegularTrainingJobs(req: Request, res: Response) {
  const configuredSecret = process.env.CRON_SECRET?.trim();
  const authorization = req.headers.authorization;
  if (!configuredSecret || authorization !== `Bearer ${configuredSecret}`) {
    return res.status(401).json({ message: 'Cron-Autorisierung fehlgeschlagen.' });
  }
  const teams = await prisma.team.findMany({
    where: { isActive: true, deletedAt: null },
    select: { id: true },
  });
  await ensureNextRegularTrainingOccurrences(teams.map((team) => team.id));
  return res.json({ processedTeams: teams.length });
}
