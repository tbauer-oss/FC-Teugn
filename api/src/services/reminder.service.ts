import {
  AccountStatus,
  EventCategory,
  EventStatus,
  NotificationCategory,
  Prisma,
  ReminderJobStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { notifyUsers } from './notification.service';

export async function reminderRecipientsForEvent(eventId: string) {
  const event = await prisma.event.findUnique({
    where: { id: eventId },
    include: {
      targetTeams: true,
      participants: {
        include: {
          player: {
            include: {
              parentLinks: {
                where: { receivesCommunication: true },
                select: { parentId: true },
              },
            },
          },
        },
      },
    },
  });
  if (!event) return { event: null, recipientIds: [] as string[] };
  const recipientIds = new Set<string>();
  if (event.participants.length) {
    for (const participant of event.participants) {
      if (participant.userId) recipientIds.add(participant.userId);
      if (participant.player?.userId) recipientIds.add(participant.player.userId);
      participant.player?.parentLinks.forEach((link) => recipientIds.add(link.parentId));
    }
  } else {
    const teamIds = event.targetTeams.length
      ? event.targetTeams.map((target) => target.teamId)
      : [event.teamId];
    const [players, staff] = await Promise.all([
      prisma.player.findMany({
        where: { teamId: { in: teamIds }, status: 'ACTIVE' },
        include: {
          parentLinks: {
            where: { receivesCommunication: true },
            select: { parentId: true },
          },
        },
      }),
      prisma.user.findMany({
        where: {
          status: AccountStatus.APPROVED,
          memberships: { some: { teamId: { in: teamIds }, status: AccountStatus.APPROVED } },
          role: { in: ['COACH', 'TRAINER', 'ASSISTANT_COACH', 'TEAM_MANAGER'] },
        },
        select: { id: true },
      }),
    ]);
    players.forEach((player) => {
      if (player.userId) recipientIds.add(player.userId);
      player.parentLinks.forEach((link) => recipientIds.add(link.parentId));
    });
    staff.forEach((user) => recipientIds.add(user.id));
  }
  return { event, recipientIds: [...recipientIds] };
}

export async function syncScheduledRemindersForEvent(eventId: string) {
  const { event, recipientIds } = await reminderRecipientsForEvent(eventId);
  if (!event) return;
  const team = await prisma.team.findUnique({
    where: { id: event.teamId },
    select: { defaultReminderMinutes: true },
  });
  const reminderMinutes = event.reminderMinutes.length
    ? event.reminderMinutes
    : event.category === EventCategory.TRAINING && event.seriesId
      ? team?.defaultReminderMinutes == null
        ? []
        : [team.defaultReminderMinutes]
      : [];
  const desiredKeys = new Set<string>();
  const writes: Prisma.PrismaPromise<unknown>[] = [];
  for (const recipientId of recipientIds) {
    for (const minutesBefore of reminderMinutes) {
      const dueAt = new Date(event.startAt.getTime() - minutesBefore * 60_000);
      const idempotencyKey = `event-reminder:${event.id}:${recipientId}:${minutesBefore}`;
      desiredKeys.add(idempotencyKey);
      writes.push(prisma.scheduledReminder.upsert({
        where: { idempotencyKey },
        update: {
          dueAt,
          status: event.status === EventStatus.CANCELLED
            ? ReminderJobStatus.CANCELLED
            : ReminderJobStatus.SCHEDULED,
          cancelledAt: event.status === EventStatus.CANCELLED ? new Date() : null,
          errorMessage: null,
        },
        create: {
          eventId: event.id,
          recipientId,
          dueAt,
          minutesBefore,
          idempotencyKey,
          status: event.status === EventStatus.CANCELLED
            ? ReminderJobStatus.CANCELLED
            : ReminderJobStatus.SCHEDULED,
          cancelledAt: event.status === EventStatus.CANCELLED ? new Date() : null,
        },
      }));
    }
  }
  writes.push(prisma.scheduledReminder.updateMany({
    where: {
      eventId,
      status: { in: [ReminderJobStatus.SCHEDULED, ReminderJobStatus.FAILED] },
      idempotencyKey: { notIn: [...desiredKeys] },
    },
    data: { status: ReminderJobStatus.CANCELLED, cancelledAt: new Date() },
  }));
  // Ein Kader kann mehrere Kinder, Eltern und Erinnerungszeitpunkte umfassen.
  // Die einzelnen Upserts in einer einzigen Prisma-Transaktion zu senden
  // verhindert dutzende serielle Netzwerk-Roundtrips und damit Timeouts nach
  // einer bereits erfolgreich abgeschlossenen Kaderspeicherung.
  await prisma.$transaction(writes);
}

export async function processDueReminders(now = new Date()) {
  const regularTrainingSent = await processRegularTrainingReminders(now);
  const due = await prisma.scheduledReminder.findMany({
    where: {
      status: { in: [ReminderJobStatus.SCHEDULED, ReminderJobStatus.FAILED] },
      dueAt: { lte: now },
      event: { status: EventStatus.SCHEDULED, startAt: { gt: now } },
    },
    orderBy: { dueAt: 'asc' },
    take: 100,
    include: { event: true },
  });
  let sent = 0;
  let failed = 0;
  for (const job of due) {
    const claimed = await prisma.scheduledReminder.updateMany({
      where: {
        id: job.id,
        status: { in: [ReminderJobStatus.SCHEDULED, ReminderJobStatus.FAILED] },
      },
      data: {
        status: ReminderJobStatus.PROCESSING,
        attemptCount: { increment: 1 },
        lastAttemptAt: now,
      },
    });
    if (!claimed.count) continue;
    try {
      await notifyUsers([job.recipientId], {
        category: NotificationCategory.EVENT_REMINDER,
        title: `${job.event.category === EventCategory.TRAINING ? 'Training' : 'Termin'} steht an`,
        body: `„${job.event.title}“ beginnt um ${job.event.startAt.toLocaleTimeString('de-DE', {
          timeZone: 'Europe/Berlin',
          hour: '2-digit',
          minute: '2-digit',
        })} Uhr.`,
        actionUrl: `/events/${job.eventId}`,
        entityType: 'Event',
        entityId: job.eventId,
        dedupeKey: job.idempotencyKey,
      });
      await prisma.scheduledReminder.update({
        where: { id: job.id },
        data: { status: ReminderJobStatus.SENT, sentAt: new Date(), errorMessage: null },
      });
      sent++;
    } catch (error) {
      await prisma.scheduledReminder.update({
        where: { id: job.id },
        data: {
          status: ReminderJobStatus.FAILED,
          errorMessage: error instanceof Error ? error.message.slice(0, 1000) : 'Unbekannter Fehler',
        },
      });
      failed++;
    }
  }
  return {
    processed: due.length,
    sent: sent + regularTrainingSent,
    failed,
    regularTrainingSent,
  };
}

const weekdays = new Map([
  ['sonntag', 0],
  ['montag', 1],
  ['dienstag', 2],
  ['mittwoch', 3],
  ['donnerstag', 4],
  ['freitag', 5],
  ['samstag', 6],
]);

export function parseRegularTrainingSlot(value: string) {
  const day = /(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)/i.exec(value);
  const time = /(\d{1,2}):(\d{2})\s*(?:-|–|—|bis)\s*(\d{1,2}):(\d{2})/i.exec(value);
  if (!day || !time) return null;
  const hour = Number(time[1]);
  const minute = Number(time[2]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return {
    weekday: weekdays.get(day[1].toLocaleLowerCase('de-DE'))!,
    hour,
    minute,
  };
}

async function processRegularTrainingReminders(now: Date) {
  // Intl liefert die Berliner Zivilzeit unabhängig von der Server-Zeitzone.
  const berlinNow = new Date(now.toLocaleString('en-US', {
    timeZone: 'Europe/Berlin',
  }));
  const teams = await prisma.team.findMany({
    where: { isActive: true, deletedAt: null },
    select: {
      id: true,
      name: true,
      defaultReminderMinutes: true,
      seasonStartDate: true,
      seasonEndDate: true,
      trainingTimes: true,
      indoorTrainingTimes: true,
      indoorSeasonStartDate: true,
      indoorSeasonEndDate: true,
      players: {
        where: { status: 'ACTIVE' },
        select: {
          userId: true,
          parentLinks: {
            where: { receivesCommunication: true },
            select: { parentId: true },
          },
        },
      },
      memberships: {
        where: {
          status: AccountStatus.APPROVED,
          user: {
            status: AccountStatus.APPROVED,
            role: { in: ['COACH', 'TRAINER', 'ASSISTANT_COACH', 'TEAM_MANAGER'] },
          },
        },
        select: { userId: true },
      },
    },
  });
  let sent = 0;
  for (const team of teams) {
    if (
      (team.seasonStartDate && berlinNow < team.seasonStartDate) ||
      (team.seasonEndDate && berlinNow > team.seasonEndDate)
    ) {
      continue;
    }
    const indoor = team.indoorSeasonStartDate && team.indoorSeasonEndDate &&
      berlinNow >= team.indoorSeasonStartDate && berlinNow <= team.indoorSeasonEndDate;
    const slots = indoor ? team.indoorTrainingTimes : team.trainingTimes;
    const minutesBefore = team.defaultReminderMinutes ?? 60;
    for (const raw of slots) {
      const slot = parseRegularTrainingSlot(raw);
      if (!slot || slot.weekday !== berlinNow.getDay()) continue;
      const start = new Date(
        berlinNow.getFullYear(),
        berlinNow.getMonth(),
        berlinNow.getDate(),
        slot.hour,
        slot.minute,
      );
      const minutesUntil = (start.getTime() - berlinNow.getTime()) / 60_000;
      if (minutesUntil > minutesBefore || minutesUntil <= minutesBefore - 5) continue;
      const recipients = new Set<string>();
      team.players.forEach((player) => {
        if (player.userId) recipients.add(player.userId);
        player.parentLinks.forEach((link) => recipients.add(link.parentId));
      });
      team.memberships.forEach((membership) => recipients.add(membership.userId));
      const occurrence = [
        start.getFullYear(),
        String(start.getMonth() + 1).padStart(2, '0'),
        String(start.getDate()).padStart(2, '0'),
        String(slot.hour).padStart(2, '0'),
        String(slot.minute).padStart(2, '0'),
      ].join('-');
      for (const recipientId of recipients) {
        const result = await notifyUsers([recipientId], {
          category: NotificationCategory.EVENT_REMINDER,
          title: 'Training steht an',
          body: `Das reguläre Training von ${team.name} beginnt um ${String(slot.hour).padStart(2, '0')}:${String(slot.minute).padStart(2, '0')} Uhr.`,
          actionUrl: '/events',
          entityType: 'Team',
          entityId: team.id,
          dedupeKey: `regular-training:${team.id}:${occurrence}:${recipientId}`,
        });
        if (result.notifications > 0) sent += 1;
      }
    }
  }
  return sent;
}
