import {
  AccountStatus,
  NotificationCategory,
  NotificationDeliveryStatus,
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
  },
) {
  const preview = externalPushPreview(notification);
  return {
    token,
    notification: {
      title: preview.title,
      body: preview.body,
    },
    data: {
      title: preview.title,
      body: preview.body,
      actionUrl: notification.actionUrl ?? '',
      notificationId: notification.id,
      entityType: notification.entityType ?? '',
      entityId: notification.entityId ?? '',
    },
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

export async function notifyUsers(userIds: string[], input: NotificationInput) {
  const uniqueIds = [...new Set(userIds)];
  if (!uniqueIds.length) return {
    recipients: 0, notifications: 0, deliveries: 0,
    sent: 0, failed: 0, pending: 0, skipped: 0,
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
  let notificationCount = 0;
  let deliveryCount = 0;
  for (const userId of uniqueIds) {
    const preference = preferenceByUser.get(userId);
    const inApp = input.forceInApp || (preference?.inApp ?? true);
    const push = input.forcePush || ((preference?.push ?? true) && input.pushEnabled !== false);
    if (!inApp && !push) continue;
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
      } });
    notificationCount++;
    if (!push) continue;
    for (const subscription of subscriptions.filter((item) => item.userId === userId)) {
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
      if (!existingDelivery) deliveryCount++;
      if (delivery.status !== NotificationDeliveryStatus.SENT) {
        await deliverPush(delivery.id).catch(() => undefined);
      }
    }
  }
  const deliverySummary = deliveryCount
    ? summarizePushDeliveries(await prisma.notificationDelivery.findMany({
        where: {
          notification: {
            userId: { in: uniqueIds },
            ...(input.dedupeKey
              ? { dedupeKey: { startsWith: `${input.dedupeKey}:` } }
              : { createdAt: { gte: new Date(Date.now() - 60_000) } }),
          },
        },
        select: {
          status: true,
          errorCode: true,
          subscription: { select: { platform: true } },
        },
      }))
    : summarizePushDeliveries([]);
  return {
    recipients: uniqueIds.length,
    notifications: notificationCount,
    deliveries: deliveryCount,
    ...deliverySummary,
  };
}

export function externalPushPreview(notification: {
  category?: NotificationCategory;
  entityType?: string | null;
}) {
  const category = notification.category;
  const body = category === NotificationCategory.EVENT_REMINDER
    ? 'Eine neue Terminerinnerung ist in der App verfügbar.'
    : category === NotificationCategory.MATCH ||
        category === NotificationCategory.NOMINATION ||
        category === NotificationCategory.LINEUP ||
        category === NotificationCategory.LIVE_TICKER
      ? 'Eine neue Spielinformation ist in der App verfügbar.'
      : category === NotificationCategory.SUPPORT
        ? 'Eine neue Supportinformation ist in der App verfügbar.'
        : notification.entityType === 'PasswordReset'
          ? 'Eine Sicherheitsinformation ist in der App verfügbar.'
          : 'Eine neue Vereinsinformation ist in der App verfügbar.';
  return { title: 'FC Teugn Talents', body };
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

export async function deliverPush(deliveryId: string) {
  const delivery = await prisma.notificationDelivery.findUnique({
    where: { id: deliveryId },
    include: { notification: true, subscription: true },
  });
  if (!delivery?.subscription || !delivery.subscription.isActive) return;
  if (delivery.subscription.platform === PushPlatform.ANDROID) {
    const messaging = firebaseMessaging();
    if (!messaging) {
      await prisma.notificationDelivery.update({
        where: { id: delivery.id },
        data: {
          status: NotificationDeliveryStatus.PENDING,
          errorCode: 'ANDROID_PUSH_NOT_CONFIGURED',
        },
      });
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
      }
      await markDeliveryFailed(delivery.id, errorCode ?? 'ANDROID_DELIVERY_FAILED');
    }
    return;
  }
  if (delivery.subscription.platform !== PushPlatform.WEB) {
    await prisma.notificationDelivery.update({
      where: { id: delivery.id },
      data: {
        status: NotificationDeliveryStatus.SKIPPED,
        attemptCount: { increment: 1 },
        lastAttemptAt: new Date(),
        errorCode: 'UNSUPPORTED_PUSH_PLATFORM',
      },
    });
    return;
  }
  if (!webPushConfigured || !delivery.subscription.p256dh || !delivery.subscription.auth) {
    await prisma.notificationDelivery.update({
      where: { id: delivery.id },
      data: {
        status: NotificationDeliveryStatus.PENDING,
        errorCode: 'WEB_PUSH_NOT_CONFIGURED',
      },
    });
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
    }
    await markDeliveryFailed(
      delivery.id,
      statusCode ? `HTTP_${statusCode}` : 'DELIVERY_FAILED',
    );
  }
}

async function markDeliverySent(deliveryId: string, subscriptionId: string) {
  const now = new Date();
  await Promise.all([
    prisma.notificationDelivery.update({
      where: { id: deliveryId },
      data: {
        status: NotificationDeliveryStatus.SENT,
        attemptCount: { increment: 1 },
        lastAttemptAt: now,
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
      attemptCount: { increment: 1 },
      lastAttemptAt: new Date(),
      errorCode: errorCode.slice(0, 160),
    },
  });
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
