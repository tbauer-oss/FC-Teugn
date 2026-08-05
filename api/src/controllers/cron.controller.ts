import { Request, Response } from 'express';
import { processDueReminders } from '../services/reminder.service';
import { processDueAnnouncements } from './communications.controller';

export async function processScheduledJobs(req: Request, res: Response) {
  const configuredSecret = process.env.CRON_SECRET?.trim();
  const authorization = req.headers.authorization;
  if (!configuredSecret || authorization !== `Bearer ${configuredSecret}`) {
    return res.status(401).json({ message: 'Cron-Autorisierung fehlgeschlagen.' });
  }
  await processDueAnnouncements();
  return res.json(await processDueReminders());
}
