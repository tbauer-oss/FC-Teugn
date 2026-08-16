import {
  AccountStatus,
  AttendanceStatus,
  EventCategory,
  EventStatus,
  EventType,
  NotificationCategory,
  Prisma,
  ReminderJobStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { notifyUsers } from './notification.service';

export async function reminderRecipientsForEvent(
  eventId: string,
  options: { includeDeclined?: boolean } = {},
) {
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
      attendance: {
        select: { playerId: true, status: true },
      },
    },
  });
  if (!event) return { event: null, recipientIds: [] as string[] };
  const recipientIds = new Set<string>();
  const declinedPlayerIds = new Set(
    event.attendance
      .filter((entry) => entry.status === AttendanceStatus.NO)
      .map((entry) => entry.playerId),
  );
  if (event.participants.length) {
    for (const participant of event.participants) {
      if (participant.userId) recipientIds.add(participant.userId);
      if (
        !options.includeDeclined &&
        participant.playerId &&
        declinedPlayerIds.has(participant.playerId)
      ) {
        continue;
      }
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
      if (!options.includeDeclined && declinedPlayerIds.has(player.id)) return;
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
    select: {
      defaultReminderMinutes: true,
      secondaryReminderMinutes: true,
      defaultReminderPushEnabled: true,
    },
  });
  const reminderMinutes = event.reminderMinutes.length
    ? event.reminderMinutes
    : event.category === EventCategory.TRAINING && event.seriesId
      ? [...new Set([
          team?.secondaryReminderMinutes,
          team?.defaultReminderMinutes,
        ].filter((value): value is number => value != null))]
      : [];
  const desiredJobs: Prisma.ScheduledReminderCreateManyInput[] = [];
  for (const recipientId of recipientIds) {
    for (const minutesBefore of reminderMinutes) {
      const dueAt = new Date(event.startAt.getTime() - minutesBefore * 60_000);
      const idempotencyKey = `event-reminder:${event.id}:${recipientId}:${minutesBefore}`;
      desiredJobs.push({
        eventId: event.id,
        recipientId,
        dueAt,
        minutesBefore,
        idempotencyKey,
        status: event.status === EventStatus.CANCELLED
          ? ReminderJobStatus.CANCELLED
          : ReminderJobStatus.SCHEDULED,
        cancelledAt: event.status === EventStatus.CANCELLED ? new Date() : null,
      });
    }
  }
  const writes: Prisma.PrismaPromise<unknown>[] = [
    prisma.scheduledReminder.deleteMany({
      where: {
        eventId,
        status: {
          in: [
            ReminderJobStatus.SCHEDULED,
            ReminderJobStatus.FAILED,
            ReminderJobStatus.CANCELLED,
          ],
        },
      },
    }),
  ];
  if (!event.isHiddenRegularOccurrence && desiredJobs.length > 0) {
    writes.push(
      prisma.scheduledReminder.createMany({
        data: desiredJobs,
        skipDuplicates: true,
      }),
    );
  }
  // Zwei Bulk-Operationen ersetzen einen Upsert pro Elternteil, Kind und
  // Erinnerungszeitpunkt. Bereits versendete oder gerade verarbeitete Jobs
  // bleiben durch ihren Idempotenzschlüssel unverändert.
  await prisma.$transaction(writes);
}

export async function processPendingReminderSyncs(limit = 20) {
  const pendingEvents = await prisma.event.findMany({
    where: { reminderSyncPendingAt: { not: null } },
    orderBy: { reminderSyncPendingAt: 'asc' },
    take: limit,
    select: { id: true, reminderSyncPendingAt: true },
  });
  let synchronized = 0;
  let failed = 0;
  for (const event of pendingEvents) {
    try {
      await syncScheduledRemindersForEvent(event.id);
      const cleared = await prisma.event.updateMany({
        where: {
          id: event.id,
          reminderSyncPendingAt: event.reminderSyncPendingAt,
        },
        data: { reminderSyncPendingAt: null },
      });
      synchronized += cleared.count;
    } catch (error) {
      console.error(`[reminder-sync] event ${event.id} failed`, error);
      failed += 1;
    }
  }
  return { pending: pendingEvents.length, synchronized, failed };
}

export async function processDueReminders(now = new Date()) {
  const pendingSync = await processPendingReminderSyncs();
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
  const currentRecipients = new Map<string, Set<string>>();
  for (const job of due) {
    if (!currentRecipients.has(job.eventId)) {
      const current = await reminderRecipientsForEvent(job.eventId);
      currentRecipients.set(job.eventId, new Set(current.recipientIds));
    }
    if (!currentRecipients.get(job.eventId)!.has(job.recipientId)) {
      await prisma.scheduledReminder.updateMany({
        where: { id: job.id, status: job.status },
        data: {
          status: ReminderJobStatus.CANCELLED,
          cancelledAt: now,
          errorMessage: 'Empfänger ist für diesen Termin nicht mehr relevant.',
        },
      });
      continue;
    }
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
      const eventLabel = job.event.type === EventType.MATCH
        ? 'Spiel'
        : job.event.category === EventCategory.TRAINING
          ? 'Training'
          : 'Termin';
      await notifyUsers([job.recipientId], {
        category: NotificationCategory.EVENT_REMINDER,
        title: `${eventLabel} steht an`,
        body: `„${job.event.title}“ beginnt um ${job.event.startAt.toLocaleTimeString('de-DE', {
          timeZone: 'Europe/Berlin',
          hour: '2-digit',
          minute: '2-digit',
        })} Uhr.`,
        actionUrl: job.event.type === EventType.MATCH
          ? `/matches/${job.eventId}`
          : `/events/${job.eventId}`,
        entityType: 'Event',
        entityId: job.eventId,
        dedupeKey: job.idempotencyKey,
        pushEnabled: job.event.reminderPushEnabled,
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
    reminderSync: pendingSync,
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
      secondaryReminderMinutes: true,
      defaultReminderPushEnabled: true,
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
      events: {
        where: {
          category: EventCategory.TRAINING,
          isSeriesException: true,
          status: EventStatus.CANCELLED,
        },
        select: { startAt: true },
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
    const reminderMinutes = [...new Set([
      team.secondaryReminderMinutes,
      team.defaultReminderMinutes,
    ].filter((value): value is number => value != null))];
    if (reminderMinutes.length === 0) continue;
    for (const raw of slots) {
      const slot = parseRegularTrainingSlot(raw);
      if (!slot) continue;
      const dayOffset = (slot.weekday - berlinNow.getDay() + 7) % 7;
      const start = new Date(
        berlinNow.getFullYear(),
        berlinNow.getMonth(),
        berlinNow.getDate() + dayOffset,
        slot.hour,
        slot.minute,
      );
      if (start <= berlinNow) start.setDate(start.getDate() + 7);
      const occurrenceKey = [
        start.getFullYear(),
        String(start.getMonth() + 1).padStart(2, '0'),
        String(start.getDate()).padStart(2, '0'),
        String(start.getHours()).padStart(2, '0'),
        String(start.getMinutes()).padStart(2, '0'),
      ].join('-');
      const cancelled = team.events.some((event) => {
        const parts = new Intl.DateTimeFormat('en-CA', {
          timeZone: 'Europe/Berlin',
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
          hourCycle: 'h23',
        }).formatToParts(event.startAt);
        const value = (type: Intl.DateTimeFormatPartTypes) =>
          parts.find((part) => part.type === type)?.value ?? '';
        return [value('year'), value('month'), value('day'), value('hour'), value('minute')]
          .join('-') === occurrenceKey;
      });
      if (cancelled) continue;
      const recipients = new Set<string>();
      team.players.forEach((player) => {
        if (player.userId) recipients.add(player.userId);
        player.parentLinks.forEach((link) => recipients.add(link.parentId));
      });
      team.memberships.forEach((membership) => recipients.add(membership.userId));
      const occurrence = occurrenceKey;
      for (const minutesBefore of reminderMinutes) {
        const minutesUntil = (start.getTime() - berlinNow.getTime()) / 60_000;
        if (minutesUntil > minutesBefore || minutesUntil <= minutesBefore - 5) continue;
        for (const recipientId of recipients) {
          const result = await notifyUsers([recipientId], {
            category: NotificationCategory.EVENT_REMINDER,
            title: 'Training steht an',
            body: `Das reguläre Training von ${team.name} beginnt um ${String(slot.hour).padStart(2, '0')}:${String(slot.minute).padStart(2, '0')} Uhr.`,
            actionUrl: '/events',
            entityType: 'Team',
            entityId: team.id,
            dedupeKey: `regular-training:${team.id}:${occurrence}:${minutesBefore}:${recipientId}`,
            pushEnabled: team.defaultReminderPushEnabled,
          });
          if (result.notifications > 0) sent += 1;
        }
      }
    }
  }
  return sent;
}
