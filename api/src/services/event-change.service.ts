import { prisma } from '../lib/prisma';
import { reminderRecipientsForEvent, syncScheduledRemindersForEvent } from './reminder.service';
import { queueUserNotifications } from './notification.service';
import { ImportSnapshot, importFieldLabels } from './competition-merge';
import { responseDeadlineMessage } from './response-deadline';

const dateFormatter = new Intl.DateTimeFormat('de-DE', {
  timeZone: 'Europe/Berlin', dateStyle: 'short', timeStyle: 'short',
});
export function eventChangeMessage(before: ImportSnapshot, after: ImportSnapshot, fields: string[]) {
  const display = (key: string, value: ImportSnapshot[string]) =>
    value == null ? 'nicht angegeben' : key.endsWith('At') || key === 'responseDeadline' ? dateFormatter.format(new Date(String(value)))
      : value === 'CANCELLED' ? 'abgesagt' : value === 'SCHEDULED' ? 'geplant' : String(value);
  return fields.map(key => `${importFieldLabels[key] ?? key}: ${display(key, before[key])} → ${display(key, after[key])}`).join(' · ');
}
export async function processEventChanges(limit = 30) {
  const changes = await prisma.eventChange.findMany({ where: { deliveredAt: null }, orderBy: { createdAt: 'asc' }, take: limit });
  let processed = 0;
  for (const change of changes) {
    try {
      await syncScheduledRemindersForEvent(change.eventId);
      const { event, recipientIds } = await reminderRecipientsForEvent(change.eventId, { includeDeclined: true });
      if (event && event.startAt > new Date()) {
        const visible = event.visibility !== 'STAFF_ONLY' &&
          (event.type !== 'MATCH' || event.familyReleasedAt != null);
        const recipients = visible ? recipientIds : (await prisma.user.findMany({ where: {
          id: { in: recipientIds }, role: { in: ['SUPER_ADMIN', 'CLUB_ADMIN', 'YOUTH_DIRECTOR', 'COACH', 'TRAINER', 'ASSISTANT_COACH', 'TEAM_MANAGER', 'TRAINER_ADMIN'] },
        }, select: { id: true } })).map(user => user.id);
        await queueUserNotifications(recipients, {
          category: 'EVENT', title: `${event.status === 'CANCELLED' ? 'Termin abgesagt' : 'Termin geändert'}: ${event.title}`,
          body: `${eventChangeMessage(change.before as ImportSnapshot, change.after as ImportSnapshot, change.fields)}. ${event.responseDeadline ? responseDeadlineMessage(event.responseDeadline) : change.fields.includes('responseDeadline') ? 'Die Rückmeldefrist wurde aufgehoben. Zu- und Absagen sind wieder möglich, sofern die Rückmeldungen nicht bereits abgeschlossen wurden.' : ''}`.trim(),
          actionUrl: event.type === 'MATCH' ? `/matches/${event.id}` : `/events/${event.id}`,
          entityType: 'Event', entityId: event.id, dedupeKey: `event-change:${change.id}`,
          metadata: { before: change.before, after: change.after, fields: change.fields },
        });
      }
      await prisma.eventChange.update({ where: { id: change.id }, data: { deliveredAt: new Date() } });
      processed++;
    } catch (error) {
      console.error('[event-change] pending', change.id, error instanceof Error ? error.name : 'Error');
    }
  }
  return { processed, pending: changes.length - processed };
}
