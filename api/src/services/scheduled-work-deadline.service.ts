import { prisma } from '../lib/prisma';
import { parseRegularTrainingSlot } from './reminder.service';
import { schedulerSafetySweepMs } from './scheduled-work-cache.service';

type TrainingTiming = {
  trainingTimes: string[]; indoorTrainingTimes: string[];
  defaultReminderMinutes: number | null; secondaryReminderMinutes: number | null;
};

/** Use the same Berlin wall-clock reminder window as the delivery worker.
 * Checking both indoor/outdoor schedules is conservative at season boundaries:
 * an extra wake-up is preferable to missing a reminder. No recipients are read. */
export function nextTrainingReminderCheck(teams: TrainingTiming[], now: Date, until: number) {
  const timings = teams.flatMap(team => {
    const leads = [team.defaultReminderMinutes, team.secondaryReminderMinutes]
      .filter((lead): lead is number => lead != null);
    return [...new Set([...team.trainingTimes, ...team.indoorTrainingTimes])]
      .flatMap(raw => {
        const slot = parseRegularTrainingSlot(raw);
        return slot ? leads.map(lead => ({ ...slot, lead })) : [];
      });
  });
  // Round to the start of each minute: cron execution jitter must not skip the
  // first due run and then land outside the worker's five-minute window.
  for (let at = Math.floor(now.getTime() / 60_000) * 60_000 + 60_000; at <= until; at += 60_000) {
    const berlin = new Date(new Date(at).toLocaleString('en-US', { timeZone: 'Europe/Berlin' }));
    for (const timing of timings) {
      const start = new Date(berlin.getFullYear(), berlin.getMonth(),
        berlin.getDate() + (timing.weekday - berlin.getDay() + 7) % 7, timing.hour, timing.minute);
      if (start <= berlin) start.setDate(start.getDate() + 7);
      const remaining = (start.getTime() - berlin.getTime()) / 60_000;
      if (remaining <= timing.lead && remaining > timing.lead - 5) return at;
    }
  }
  return until;
}

export async function nextScheduledWorkAt(now = new Date(), db = prisma): Promise<number> {
  const limit = now.getTime() + schedulerSafetySweepMs;
  const [reminder, announcement, laundry, syncs, teams, pendingReminderSync,
    eventChange, notice, pushRetry, attachment, contactNotification] = await Promise.all([
    db.scheduledReminder.findFirst({
      where: { status: { in: ['SCHEDULED', 'FAILED'] }, event: { status: 'SCHEDULED', startAt: { gt: now } } },
      orderBy: { dueAt: 'asc' }, select: { dueAt: true },
    }),
    db.announcement.findFirst({
      where: { deletedAt: null, status: 'SCHEDULED', publishAt: { not: null },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
      orderBy: { publishAt: 'asc' }, select: { publishAt: true },
    }),
    db.event.findFirst({
      where: { type: 'MATCH', status: 'SCHEDULED', parentTournamentId: null,
        startAt: { gt: now }, OR: [{ kitLaundryDuty: null }, {
          kitLaundryDuty: { is: { status: { in: ['OPEN', 'PROPOSED'] }, reminderSentAt: null } },
        }] }, orderBy: { startAt: 'asc' }, select: { startAt: true },
    }),
    db.bfvTeamSync.findMany({
      where: { enabled: true, icalUrl: { not: null }, team: { deletedAt: null, isActive: true } },
      select: { lastAttemptAt: true, syncIntervalMinutes: true },
    }),
    db.team.findMany({
      where: { isActive: true, deletedAt: null },
      select: { trainingTimes: true, indoorTrainingTimes: true,
        defaultReminderMinutes: true, secondaryReminderMinutes: true },
    }),
    db.event.findFirst({ where: { reminderSyncPendingAt: { not: null } }, select: { id: true } }),
    db.eventChange.findFirst({ where: { deliveredAt: null }, select: { id: true } }),
    db.talentsNotice.findFirst({ where: { deliveredAt: null }, select: { id: true } }),
    db.notificationDelivery.findFirst({
      where: { status: 'PENDING', attemptCount: { lt: 6 }, subscription: { isActive: true } },
      select: { id: true },
    }),
    db.familyContactAttachment.findFirst({
      orderBy: { expiresAt: 'asc' }, select: { expiresAt: true },
    }),
    db.notification.findFirst({
      where: { entityType: { startsWith: 'FamilyContact:' }, expiresAt: { not: null } },
      orderBy: { expiresAt: 'asc' }, select: { expiresAt: true },
    }),
  ]);
  if (pendingReminderSync || eventChange || notice || pushRetry) return now.getTime();
  const candidates = [limit, nextTrainingReminderCheck(teams, now, limit)];
  if (reminder) candidates.push(reminder.dueAt.getTime());
  if (announcement?.publishAt) candidates.push(announcement.publishAt.getTime());
  if (laundry) candidates.push(laundry.startAt.getTime() - 65 * 60_000);
  if (attachment) candidates.push(attachment.expiresAt.getTime());
  if (contactNotification?.expiresAt) candidates.push(contactNotification.expiresAt.getTime());
  for (const sync of syncs) {
    candidates.push(sync.lastAttemptAt
      ? sync.lastAttemptAt.getTime() + Math.max(15, sync.syncIntervalMinutes) * 60_000
      : now.getTime());
  }
  // Reconcile date-dependent absences at Berlin midnight, including DST days.
  const today = now.toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' });
  for (let at = Math.floor(now.getTime() / 60_000) * 60_000 + 60_000; at < limit; at += 60_000) {
    if (new Date(at).toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' }) !== today) {
      candidates.push(at);
      break;
    }
  }
  return Math.min(...candidates);
}
