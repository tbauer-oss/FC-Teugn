import {
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
};

export function androidPushMessage(
  token: string,
  notification: {
    id: string;
    title: string;
    body: string;
    actionUrl?: string | null;
    entityType?: string | null;
    entityId?: string | null;
  },
) {
  return {
    token,
    notification: {
      title: notification.title,
      body: notification.body,
    },
    data: {
      title: notification.title,
      body: notification.body,
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
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
  };
}

export async function notifyUsers(userIds: string[], input: NotificationInput) {
  const uniqueIds = [...new Set(userIds)];
  if (!uniqueIds.length) return { notifications: 0, deliveries: 0 };
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
    const inApp = preference?.inApp ?? true;
    const push = (preference?.push ?? true) && input.pushEnabled !== false;
    if (!inApp && !push) continue;
    const notification = await prisma.notification.create({
      data: {
        userId,
        category: input.category,
        title: input.title.slice(0, 160),
        body: input.body.slice(0, 1000),
        actionUrl: input.actionUrl,
        entityType: input.entityType,
        entityId: input.entityId,
        expiresAt: input.expiresAt,
      },
    });
    notificationCount++;
    if (!push) continue;
    for (const subscription of subscriptions.filter((item) => item.userId === userId)) {
      const delivery = await prisma.notificationDelivery.create({
        data: {
          notificationId: notification.id,
          subscriptionId: subscription.id,
          userId,
        },
      });
      deliveryCount++;
      await deliverPush(delivery.id).catch(() => undefined);
    }
  }
  return { notifications: notificationCount, deliveries: deliveryCount };
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
        title: delivery.notification.title,
        body: delivery.notification.body,
        actionUrl: delivery.notification.actionUrl,
        notificationId: delivery.notification.id,
      }),
      { TTL: 3600, urgency: 'normal' },
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
