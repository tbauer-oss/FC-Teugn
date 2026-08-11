import { Request, Response } from 'express';
import { processDueReminders } from '../services/reminder.service';
import { processDueAnnouncements } from './communications.controller';
import { processDueBfvSyncs } from '../services/bfv-sync.service';
import { applyOperationalRetention } from '../services/privacy-retention.service';

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
  return res.json({ reminders, bfvSyncs, retention });
}
