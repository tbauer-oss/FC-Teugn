import {
  AccountStatus,
  NotificationCategory,
  NotificationDeliveryStatus,
  Prisma,
  PushPlatform,
} from '@prisma/client';
import webPush from 'web-push';
import { prisma } from '../lib/prisma';
import {
  firebaseMessaging,
  firebaseMessagingConfigured,
} from '../lib/firebase-admin';

const vapidPublicKey = process.env.VAPID_PUBLIC_KEY?.trim() ?? '';
const vapidPrivateKey = process.env.VAPID_PRIVATE_KEY?.trim() ?? '';
const vapidSubject = process.env.VAPID_SUBJECT?.trim() || 'mailto:admin@fc-teugn.de';
export const webPushConfigured = Boolean(vapidPublicKey && vapidPrivateKey);
const maxAutomaticDeliveryAttempts = 6;
const pendingDeliveryRetryDelayMs = 4 * 60 * 1000;

if (webPushConfigured) {
  webPush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
}

export type NotificationInput = {
  category: NotificationCategory;
  title: string;
  body: string;
  actionUrl?: string | null;
  entityType?: string | null;
  entityId?: string | null;
  expiresAt?: Date | null;
  pushEnabled?: boolean;
  forcePush?: boolean;
  forceInApp?: boolean;
  dedupeKey?: string | null;
  metadata?: Prisma.InputJsonValue;
};

export type QueuedNotificationBatch = {
  recipients: number;
  notifications: number;
  deliveries: number;
  deliveryIds: string[];
};

type PushDeliverySummaryInput = {
  status: NotificationDeliveryStatus;
  errorCode: string | null;
  subscription: { platform: PushPlatform } | null;
};

export function summarizePushDeliveries(deliveries: PushDeliverySummaryInput[]) {
  const errors = new Map<string, number>();
  const byPlatform = {
    WEB: { total: 0, sent: 0, failed: 0, pending: 0, skipped: 0 },
    ANDROID: { total: 0, sent: 0, failed: 0, pending: 0, skipped: 0 },
  };
  const result = {
    subscriptions: deliveries.length,
    sent: 0,
    failed: 0,
    pending: 0,
    skipped: 0,
  };
  for (const delivery of deliveries) {
    const key = delivery.status.toLowerCase() as
      | 'sent'
      | 'failed'
      | 'pending'
      | 'skipped';
    result[key]++;
    if (delivery.subscription) {
      byPlatform[delivery.subscription.platform].total++;
      byPlatform[delivery.subscription.platform][key]++;
    }
    if (delivery.errorCode) {
      errors.set(delivery.errorCode, (errors.get(delivery.errorCode) ?? 0) + 1);
    }
  }
  return {
    ...result,
    byPlatform,
    errors: [...errors.entries()].map(([code, count]) => ({ code, count })),
  };
}

export function androidPushMessage(
  token: string,
  notification: {
    id: string;
    category?: NotificationCategory;
    title: string;
    body: string;
    actionUrl?: string | null;
    entityType?: string | null;
    entityId?: string | null;
    metadata?: unknown;
  },
) {
  const preview = externalPushPreview(notification);
  const metadata = notification.metadata &&
      typeof notification.metadata === 'object' &&
      !Array.isArray(notification.metadata)
    ? notification.metadata as Record<string, unknown>
    : {};
  const liveMatch = notification.category === NotificationCategory.LIVE_TICKER &&
    metadata.kind === 'LIVE_MATCH';
  const homeTeam = String(metadata.homeTeam ?? 'Heim');
  const awayTeam = String(metadata.awayTeam ?? 'Gast');
  const homeScore = String(metadata.homeScore ?? 0);
  const awayScore = String(metadata.awayScore ?? 0);
  const minute = String(metadata.minute ?? 1);
  const status = String(metadata.status ?? 'Live');
  const data = {
    // Live-Match-Daten sind auch im FCM-Payload strikt kinder-namensfrei.
    // Dadurch kann weder ein OEM-Fallback noch ein Diagnose-Preview versehentlich
    // einen Ereignistext mit Spielernamen auf dem Sperrbildschirm verwenden.
    title: liveMatch
      ? `${homeTeam} ${homeScore}:${awayScore} ${awayTeam}`
      : preview.title,
    body: liveMatch ? `${status} · ${minute}. Minute` : preview.body,
    actionUrl: notification.actionUrl ?? '',
    notificationId: notification.id,
    entityType: notification.entityType ?? '',
    entityId: notification.entityId ?? '',
    ...(liveMatch
      ? {
          liveMatch: 'true',
          matchId: String(metadata.matchId ?? ''),
          homeTeam,
          awayTeam,
          homeScore,
          awayScore,
          minute,
          status,
          finished: String(metadata.finished === true),
        }
      : {}),
  };
  if (liveMatch) {
    return {
      token,
      data,
      android: {
        priority: 'high' as const,
        ttl: 60 * 60 * 1000,
      },
    };
  }
  return {
    token,
    notification: {
      title: preview.title,
      body: preview.body,
    },
    data,
    android: {
      priority: 'high' as const,
      ttl: 60 * 60 * 1000,
      notification: {
        channelId: 'fc_teugn_important',
        sound: 'default',
        color: '#FFE600',
        icon: 'ic_stat_fc_teugn',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
  };
}

export async function queueUserNotifications(
  userIds: string[],
  input: NotificationInput,
): Promise<QueuedNotificationBatch> {
  const uniqueIds = [...new Set(userIds)];
  if (!uniqueIds.length) return {
    recipients: 0,
    notifications: 0,
    deliveries: 0,
    deliveryIds: [],
  };
  const [preferences, subscriptions] = await Promise.all([
    prisma.notificationPreference.findMany({
      where: { userId: { in: uniqueIds }, category: input.category },
    }),
    prisma.pushSubscription.findMany({
      where: { userId: { in: uniqueIds }, isActive: true },
    }),
  ]);
  const preferenceByUser = new Map(
    preferences.map((preference) => [preference.userId, preference]),
  );
  const subscriptionsByUser = new Map<string, typeof subscriptions>();
  for (const subscription of subscriptions) {
    const existing = subscriptionsByUser.get(subscription.userId) ?? [];
    existing.push(subscription);
    subscriptionsByUser.set(subscription.userId, existing);
  }
  let notificationCount = 0;
  let deliveryCount = 0;
  const deliveryIds: string[] = [];
  // Die Empfänger werden in kleinen parallelen Gruppen vorbereitet. Dadurch
  // bleibt die Bestätigung auch bei größeren Mannschaften schnell, ohne den
  // Datenbank-Pool mit unbegrenzt vielen gleichzeitigen Abfragen zu belasten.
  const concurrency = 8;
  for (let index = 0; index < uniqueIds.length; index += concurrency) {
    const results = await Promise.all(
      uniqueIds.slice(index, index + concurrency).map(async (userId) => {
        const preference = preferenceByUser.get(userId);
        const defaults = defaultNotificationPreference(input.category);
        const inApp = input.forceInApp || (preference?.inApp ?? defaults.inApp);
        const push = input.forcePush || (
          (preference?.push ?? defaults.push) && input.pushEnabled !== false
        );
        if (!inApp && !push) {
          return { notifications: 0, deliveries: 0, deliveryIds: [] as string[] };
        }
        const notification = input.dedupeKey
          ? await prisma.notification.upsert({
              where: { dedupeKey: `${input.dedupeKey}:${userId}` },
              update: {},
              create: {
                userId,
                category: input.category,
                title: input.title.slice(0, 160),
                body: input.body.slice(0, 1000),
                actionUrl: input.actionUrl,
                entityType: input.entityType,
                entityId: input.entityId,
                expiresAt: input.expiresAt,
                dedupeKey: `${input.dedupeKey}:${userId}`,
                metadata: input.metadata,
              },
            })
          : await prisma.notification.create({ data: {
              userId,
              category: input.category,
              title: input.title.slice(0, 160),
              body: input.body.slice(0, 1000),
              actionUrl: input.actionUrl,
              entityType: input.entityType,
              entityId: input.entityId,
              expiresAt: input.expiresAt,
              metadata: input.metadata,
            } });
        if (!push) {
          return { notifications: 1, deliveries: 0, deliveryIds: [] as string[] };
        }
        const prepared = await Promise.all(
          (subscriptionsByUser.get(userId) ?? []).map(async (subscription) => {
            const existingDelivery = await prisma.notificationDelivery.findUnique({
              where: {
                notificationId_subscriptionId: {
                  notificationId: notification.id,
                  subscriptionId: subscription.id,
                },
              },
              select: { id: true, status: true },
            });
            const delivery = existingDelivery ?? await prisma.notificationDelivery.upsert({
              where: {
                notificationId_subscriptionId: {
                  notificationId: notification.id,
                  subscriptionId: subscription.id,
                },
              },
              update: {},
              create: {
                notificationId: notification.id,
                subscriptionId: subscription.id,
                userId,
              },
              select: { id: true, status: true },
            });
            return {
              created: existingDelivery == null ? 1 : 0,
              deliveryId: delivery.status !== NotificationDeliveryStatus.SENT
                ? delivery.id
                : null,
            };
          }),
        );
        return {
          notifications: 1,
          deliveries: prepared.reduce((sum, item) => sum + item.created, 0),
          deliveryIds: prepared
            .map((item) => item.deliveryId)
            .filter((id): id is string => id != null),
        };
      }),
    );
    for (const result of results) {
      notificationCount += result.notifications;
      deliveryCount += result.deliveries;
      deliveryIds.push(...result.deliveryIds);
    }
  }
  return {
    recipients: uniqueIds.length,
    notifications: notificationCount,
    deliveries: deliveryCount,
    deliveryIds,
  };
}

export async function deliverQueuedPushes(deliveryIds: string[]) {
  const uniqueIds = [...new Set(deliveryIds)];
  // Eine kleine Parallelisierung verhindert lange HTTP-Laufzeiten, ohne die
  // Push-Anbieter oder die Datenbank mit unbegrenzt vielen Requests zu fluten.
  const concurrency = 8;
  for (let index = 0; index < uniqueIds.length; index += concurrency) {
    await Promise.allSettled(
      uniqueIds
        .slice(index, index + concurrency)
        .map((deliveryId) => deliverPush(deliveryId)),
    );
  }
  if (!uniqueIds.length) return summarizePushDeliveries([]);
  return summarizePushDeliveries(await prisma.notificationDelivery.findMany({
    where: { id: { in: uniqueIds } },
    select: {
      status: true,
      errorCode: true,
      subscription: { select: { platform: true } },
    },
  }));
}

export async function notifyUsers(userIds: string[], input: NotificationInput) {
  const queued = await queueUserNotifications(userIds, input);
  const deliverySummary = await deliverQueuedPushes(queued.deliveryIds);
  return {
    recipients: queued.recipients,
    notifications: queued.notifications,
    deliveries: queued.deliveries,
    ...deliverySummary,
  };
}

export function externalPushPreview(notification: {
  category?: NotificationCategory;
  entityType?: string | null;
  title?: string;
  body?: string;
}) {
  const title = notification.title?.trim();
  const body = notification.body?.trim();
  return {
    title: title || 'FC Teugn Talents',
    body: body || 'Eine neue Information ist in der App verfügbar.',
  };
}

export function defaultNotificationPreference(category: NotificationCategory) {
  return {
    inApp: true,
    push: category !== NotificationCategory.LIVE_TICKER,
  };
}

export async function sendAdminTestPush(actorName: string) {
  const subscriptions = await prisma.pushSubscription.findMany({
    where: {
      isActive: true,
      user: { status: AccountStatus.APPROVED },
    },
    select: { id: true, userId: true },
  });
  const userIds = [...new Set(subscriptions.map((item) => item.userId))];
  if (!subscriptions.length) {
    return {
      recipients: 0,
      ...summarizePushDeliveries([]),
    };
  }

  const notificationByUser = new Map<string, string>();
  for (const userId of userIds) {
    const notification = await prisma.notification.create({
      data: {
        userId,
        category: NotificationCategory.SYSTEM,
        title: 'FC Teugn Talents · Push-Test',
        body: `Testnachricht der Systemadministration (${actorName}). Der Push-Empfang funktioniert.`,
        actionUrl: '/messages',
        entityType: 'ADMIN_PUSH_TEST',
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      },
      select: { id: true },
    });
    notificationByUser.set(userId, notification.id);
  }

  const deliveryIds: string[] = [];
  for (const subscription of subscriptions) {
    const delivery = await prisma.notificationDelivery.create({
      data: {
        notificationId: notificationByUser.get(subscription.userId)!,
        subscriptionId: subscription.id,
        userId: subscription.userId,
      },
      select: { id: true },
    });
    deliveryIds.push(delivery.id);
  }
  await Promise.all(deliveryIds.map((id) => deliverPush(id)));
  const deliveries = await prisma.notificationDelivery.findMany({
    where: { id: { in: deliveryIds } },
    select: {
      status: true,
      errorCode: true,
      subscription: { select: { platform: true } },
    },
  });
  return {
    recipients: userIds.length,
    ...summarizePushDeliveries(deliveries),
  };
}

export const adminPushScenarios = {
  TRAINING: {
    category: NotificationCategory.EVENT_REMINDER,
    title: 'Rückmeldung fehlt: Training E-Jugend',
    body: 'Bitte gib für das Training am Dienstag um 17:15 Uhr eine Zu- oder Absage ab.',
    actionUrl: '/family',
    entityType: 'ADMIN_PUSH_SCENARIO_TRAINING',
  },
  MATCH: {
    category: NotificationCategory.MATCH,
    title: 'Spieltag: FC Teugn – Testgegner',
    body: 'Anstoß ist am Samstag um 10:00 Uhr. Treffpunkt: 09:15 Uhr am Sportplatz.',
    actionUrl: '/matches',
    entityType: 'ADMIN_PUSH_SCENARIO_MATCH',
  },
  LIVE_TICKER: {
    category: NotificationCategory.LIVE_TICKER,
    title: 'Tor für FC Teugn! 1:0',
    body: 'FC Teugn geht in der 12. Minute in Führung. Liveticker jetzt öffnen.',
    actionUrl: '/matches',
    entityType: 'ADMIN_PUSH_SCENARIO_LIVE_TICKER',
  },
  NOMINATION: {
    category: NotificationCategory.NOMINATION,
    title: 'Neue Nominierung für den Spieltag',
    body: 'Der Kader für das Spiel am Samstag wurde freigegeben. Nominierung jetzt ansehen.',
    actionUrl: '/matches',
    entityType: 'ADMIN_PUSH_SCENARIO_NOMINATION',
  },
  REGISTRATION: {
    category: NotificationCategory.REGISTRATION,
    title: 'Neue Registrierung wartet auf Freigabe',
    body: 'Max Mustermann hat sich registriert und wartet auf deine Prüfung.',
    actionUrl: '/trainer/approvals',
    entityType: 'ADMIN_PUSH_SCENARIO_REGISTRATION',
  },
  MESSAGE: {
    category: NotificationCategory.ANNOUNCEMENT,
    title: 'Neue Nachricht vom Trainerteam',
    body: 'Bitte beachte die aktuelle Information zum Training der E-Jugend.',
    actionUrl: '/messages',
    entityType: 'ADMIN_PUSH_SCENARIO_MESSAGE',
  },
  SUPPORT: {
    category: NotificationCategory.SUPPORT,
    title: 'Antwort vom technischen Support',
    body: 'Zu deiner Supportanfrage liegt eine neue Antwort vor.',
    actionUrl: '/support',
    entityType: 'ADMIN_PUSH_SCENARIO_SUPPORT',
  },
} as const;

export type AdminPushScenario = keyof typeof adminPushScenarios;

export async function sendAdminScenarioTestPush(
  userId: string,
  scenario: AdminPushScenario,
) {
  const subscriptions = await prisma.pushSubscription.findMany({
    where: {
      userId,
      isActive: true,
      user: { status: AccountStatus.APPROVED },
    },
    select: { id: true },
  });
  if (!subscriptions.length) {
    return {
      scenario,
      recipients: 0,
      ...summarizePushDeliveries([]),
    };
  }
  const selected = adminPushScenarios[scenario];
  const notification = await prisma.notification.create({
    data: {
      userId,
      ...selected,
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
    },
    select: { id: true },
  });
  const deliveryIds: string[] = [];
  for (const subscription of subscriptions) {
    const delivery = await prisma.notificationDelivery.create({
      data: {
        notificationId: notification.id,
        subscriptionId: subscription.id,
        userId,
      },
      select: { id: true },
    });
    deliveryIds.push(delivery.id);
  }
  await Promise.all(deliveryIds.map((id) => deliverPush(id)));
  const deliveries = await prisma.notificationDelivery.findMany({
    where: { id: { in: deliveryIds } },
    select: {
      status: true,
      errorCode: true,
      subscription: { select: { platform: true } },
    },
  });
  return {
    scenario,
    recipients: 1,
    ...summarizePushDeliveries(deliveries),
  };
}

export async function deliverPush(deliveryId: string) {
  const claimedAt = new Date();
  const retryBefore = new Date(claimedAt.getTime() - pendingDeliveryRetryDelayMs);
  const claim = await prisma.notificationDelivery.updateMany({
    where: {
      id: deliveryId,
      status: NotificationDeliveryStatus.PENDING,
      attemptCount: { lt: maxAutomaticDeliveryAttempts },
      OR: [
        { lastAttemptAt: null },
        { lastAttemptAt: { lte: retryBefore } },
      ],
    },
    data: {
      attemptCount: { increment: 1 },
      lastAttemptAt: claimedAt,
    },
  });
  // Hintergrundversand, Cron und ein gleichzeitig geöffneter Client können
  // denselben Datensatz sehen. Nur der Gewinner dieses atomaren Claims darf
  // tatsächlich an Firebase bzw. Web Push senden.
  if (!claim.count) return;
  const delivery = await prisma.notificationDelivery.findUnique({
    where: { id: deliveryId },
    include: { notification: true, subscription: true },
  });
  if (!delivery?.subscription || !delivery.subscription.isActive) {
    await prisma.notificationDelivery.update({
      where: { id: deliveryId },
      data: {
        status: NotificationDeliveryStatus.SKIPPED,
        errorCode: 'PUSH_SUBSCRIPTION_INACTIVE',
      },
    }).catch(() => undefined);
    return;
  }
  if (delivery.subscription.platform === PushPlatform.ANDROID) {
    const messaging = firebaseMessaging();
    if (!messaging) {
      await markDeliveryPending(delivery.id, 'ANDROID_PUSH_NOT_CONFIGURED');
      return;
    }
    try {
      await messaging.send(
        androidPushMessage(
          delivery.subscription.endpoint,
          delivery.notification,
        ),
      );
      await markDeliverySent(delivery.id, delivery.subscription.id);
    } catch (error) {
      const errorCode = firebaseErrorCode(error);
      if (
        errorCode === 'messaging/registration-token-not-registered' ||
        errorCode === 'messaging/invalid-registration-token'
      ) {
        await prisma.pushSubscription.update({
          where: { id: delivery.subscription.id },
          data: { isActive: false },
        });
        await markDeliveryFailed(
          delivery.id,
          errorCode ?? 'ANDROID_DELIVERY_FAILED',
        );
      } else {
        await markDeliveryPending(
          delivery.id,
          errorCode ?? 'ANDROID_DELIVERY_FAILED',
        );
      }
    }
    return;
  }
  if (delivery.subscription.platform !== PushPlatform.WEB) {
    await prisma.notificationDelivery.update({
      where: { id: delivery.id },
      data: {
        status: NotificationDeliveryStatus.SKIPPED,
        errorCode: 'UNSUPPORTED_PUSH_PLATFORM',
      },
    });
    return;
  }
  if (!webPushConfigured || !delivery.subscription.p256dh || !delivery.subscription.auth) {
    await markDeliveryPending(delivery.id, 'WEB_PUSH_NOT_CONFIGURED');
    return;
  }
  try {
    await webPush.sendNotification(
      {
        endpoint: delivery.subscription.endpoint,
        keys: {
          p256dh: delivery.subscription.p256dh,
          auth: delivery.subscription.auth,
        },
      },
      JSON.stringify({
        ...externalPushPreview(delivery.notification),
        actionUrl: delivery.notification.actionUrl,
        notificationId: delivery.notification.id,
      }),
      { TTL: 3600, urgency: 'high' },
    );
    await markDeliverySent(delivery.id, delivery.subscription.id);
  } catch (error) {
    const statusCode =
      typeof error === 'object' && error && 'statusCode' in error
        ? Number(error.statusCode)
        : 0;
    if ([404, 410].includes(statusCode)) {
      await prisma.pushSubscription.update({
        where: { id: delivery.subscription.id },
        data: { isActive: false },
      });
      await markDeliveryFailed(delivery.id, `HTTP_${statusCode}`);
    } else {
      await markDeliveryPending(
        delivery.id,
        statusCode ? `HTTP_${statusCode}` : 'DELIVERY_FAILED',
      );
    }
  }
}

export async function retryPendingPushDeliveries(limit = 100) {
  const retryBefore = new Date(Date.now() - pendingDeliveryRetryDelayMs);
  const pending = await prisma.notificationDelivery.findMany({
    where: {
      status: NotificationDeliveryStatus.PENDING,
      attemptCount: { lt: maxAutomaticDeliveryAttempts },
      subscription: { isActive: true },
      OR: [
        { lastAttemptAt: null },
        { lastAttemptAt: { lte: retryBefore } },
      ],
    },
    orderBy: [{ lastAttemptAt: 'asc' }, { createdAt: 'asc' }],
    select: { id: true },
    take: Math.max(1, Math.min(limit, 250)),
  });
  for (const delivery of pending) {
    await deliverPush(delivery.id).catch(() => undefined);
  }
  if (!pending.length) {
    return { processed: 0, ...summarizePushDeliveries([]) };
  }
  const deliveries = await prisma.notificationDelivery.findMany({
    where: { id: { in: pending.map((delivery) => delivery.id) } },
    select: {
      status: true,
      errorCode: true,
      subscription: { select: { platform: true } },
    },
  });
  return {
    processed: pending.length,
    ...summarizePushDeliveries(deliveries),
  };
}

async function markDeliverySent(deliveryId: string, subscriptionId: string) {
  const now = new Date();
  await Promise.all([
    prisma.notificationDelivery.update({
      where: { id: deliveryId },
      data: {
        status: NotificationDeliveryStatus.SENT,
        sentAt: now,
        errorCode: null,
      },
    }),
    prisma.pushSubscription.update({
      where: { id: subscriptionId },
      data: { lastUsedAt: now },
    }),
  ]);
}

async function markDeliveryFailed(deliveryId: string, errorCode: string) {
  await prisma.notificationDelivery.update({
    where: { id: deliveryId },
    data: {
      status: NotificationDeliveryStatus.FAILED,
      errorCode: errorCode.slice(0, 160),
    },
  });
}

async function markDeliveryPending(deliveryId: string, errorCode: string) {
  const delivery = await prisma.notificationDelivery.update({
    where: { id: deliveryId },
    data: {
      status: NotificationDeliveryStatus.PENDING,
      errorCode: errorCode.slice(0, 160),
    },
    select: { attemptCount: true },
  });
  if (delivery.attemptCount >= maxAutomaticDeliveryAttempts) {
    await prisma.notificationDelivery.update({
      where: { id: deliveryId },
      data: { status: NotificationDeliveryStatus.FAILED },
    });
  }
}

function firebaseErrorCode(error: unknown) {
  if (typeof error !== 'object' || !error || !('code' in error)) return null;
  const code = String(error.code ?? '').trim();
  return code || null;
}

export function pushConfiguration() {
  return {
    webPushConfigured,
    vapidPublicKey: webPushConfigured ? vapidPublicKey : null,
    androidConfigured: firebaseMessagingConfigured(),
  };
}
