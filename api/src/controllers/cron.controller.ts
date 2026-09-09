import { Request, Response } from 'express';
import { retryFileDeletions } from '../services/file-deletion.service';
import { processDueReminders } from '../services/reminder.service';
import { processDueAnnouncements } from './communications.controller';
import { processDueBfvSyncs } from '../services/bfv-sync.service';
import { applyOperationalRetention, purgeExpiredFamilyContacts } from '../services/privacy-retention.service';
import { retryPendingPushDeliveries } from '../services/notification.service';
import { prisma } from '../lib/prisma';
import { ensureNextRegularTrainingOccurrences } from '../services/regular-training-occurrence.service';
import { processKitLaundryReminders } from '../services/kit-laundry.service';
import { processEventChanges } from '../services/event-change.service';
import { reconcileActiveAbsences } from '../services/absence.service';
import { processTalentsNotices } from '../services/talents-notices';
import { scheduledWorkCache } from '../services/scheduled-work-cache.service';
import { nextScheduledWorkAt } from '../services/scheduled-work-deadline.service';

async function maintainRegularTrainings() {
  const teams = await prisma.team.findMany({
    where: { isActive: true, deletedAt: null }, select: { id: true },
  });
  await ensureNextRegularTrainingOccurrences(teams.map(team => team.id));
  return { processedTeams: teams.length };
}

export async function processScheduledJobs(req: Request, res: Response) {
  const configuredSecret = process.env.CRON_SECRET?.trim();
  const authorization = req.headers.authorization;
  if (!configuredSecret || authorization !== `Bearer ${configuredSecret}`) {
    return res.status(401).json({ message: 'Cron-Autorisierung fehlgeschlagen.' });
  }
  if (!(await scheduledWorkCache.shouldRun())) {
    console.info('[scheduled-work] idle: no database scan needed');
    return res.json({ status: 'idle', databaseScan: false });
  }
  const release = await scheduledWorkCache.acquireWorkerLease();
  if (!release) return res.json({ status: 'busy', databaseScan: false });
  let outcome;
  try {
    const regularTrainings = await scheduledWorkCache.maintenanceDue(
      'regular-trainings', 60 * 60_000, maintainRegularTrainings,
    ).catch(error => {
      // The former independent training job must not block due messages if its
      // maintenance fails. Its absent success marker keeps the next run due.
      console.error('[scheduled-work] training maintenance failed', error instanceof Error ? error.name : 'Error');
      return { status: 'retry-pending' };
    });
    const fileDeletions = await scheduledWorkCache.maintenanceDue(
      'file-deletions', 60 * 60_000, retryFileDeletions,
    );
    await processDueAnnouncements();
    await reconcileActiveAbsences();
    const [reminders, kitLaundry, bfvSyncs, retention, familyContacts] = await Promise.all([
      processDueReminders(),
      processKitLaundryReminders(),
      processDueBfvSyncs(new Date(), 1),
      scheduledWorkCache.maintenanceDue('retention', 24 * 60 * 60_000,
        () => applyOperationalRetention(new Date(), { includeFamilyContacts: false })),
      purgeExpiredFamilyContacts(),
    ]);
    // Erinnerungen und geplante Mitteilungen legen ihre Zustellungen oberhalb an.
    // Danach werden auch vorübergehend fehlgeschlagene Pushes aller Kategorien
    // erneut versendet, ohne dass der Empfänger zuerst die App öffnen muss.
    const eventChanges = await processEventChanges();
    await processTalentsNotices();
    const pushRetries = await retryPendingPushDeliveries();
    await scheduledWorkCache.checkpoint(async () => Math.min(
      await nextScheduledWorkAt(),
      await scheduledWorkCache.nextMaintenanceAt('regular-trainings', 60 * 60_000),
    ));
    console.info(`[scheduled-work] processed; idle guard ${scheduledWorkCache.enabled ? 'available' : 'unavailable'}`);
    outcome = { fileDeletions, reminders, kitLaundry, pushRetries, bfvSyncs, eventChanges, retention, familyContacts, regularTrainings };
  } finally {
    await release();
  }
  return res.json(outcome);
}

export async function processRegularTrainingJobs(req: Request, res: Response) {
  const configuredSecret = process.env.CRON_SECRET?.trim();
  const authorization = req.headers.authorization;
  if (!configuredSecret || authorization !== `Bearer ${configuredSecret}`) {
    return res.status(401).json({ message: 'Cron-Autorisierung fehlgeschlagen.' });
  }
  const result = await maintainRegularTrainings();
  await scheduledWorkCache.invalidate();
  return res.json(result);
}
