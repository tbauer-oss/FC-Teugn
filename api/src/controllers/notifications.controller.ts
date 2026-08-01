import {
  ConsentDocumentType,
  NotificationCategory,
  NotificationDeliveryStatus,
  PushPlatform,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import {
  deliverPush,
  pushConfiguration,
  sendAdminTestPush,
} from '../services/notification.service';

function text(value: unknown, max = 1000) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, max) : null;
}

function enumValue<T extends Record<string, string>>(
  values: T,
  value: unknown,
  fallback: T[keyof T],
) {
  const normalized = String(value ?? '').toUpperCase();
  return (Object.values(values) as string[]).includes(normalized)
    ? (normalized as T[keyof T])
    : fallback;
}

export async function notificationConfiguration(_req: Request, res: Response) {
  return res.json(pushConfiguration());
}

export async function testPushBroadcast(req: Request, res: Response) {
  const actor = await prisma.user.findUnique({
    where: { id: req.user!.id },
    select: { name: true },
  });
  const result = await sendAdminTestPush(actor?.name || 'Systemadministration');
  return res.json(result);
}

export async function listNotifications(req: Request, res: Response) {
  const userId = req.user!.id;
  const disabled = await prisma.notificationPreference.findMany({
    where: { userId, inApp: false },
    select: { category: true },
  });
  const pending = await prisma.notificationDelivery.findMany({
    where: {
      userId,
      status: NotificationDeliveryStatus.PENDING,
      subscription: { isActive: true },
    },
    select: { id: true },
    take: 10,
  });
  await Promise.all(pending.map((delivery) => deliverPush(delivery.id).catch(() => undefined)));
  const notifications = await prisma.notification.findMany({
    where: {
      userId,
      category: { notIn: disabled.map((item) => item.category) },
      OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
    },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  return res.json(notifications);
}

export async function markNotificationRead(req: Request, res: Response) {
  const result = await prisma.notification.updateMany({
    where: { id: req.params.id, userId: req.user!.id },
    data: { readAt: new Date() },
  });
  if (!result.count) return res.status(404).json({ message: 'Benachrichtigung nicht gefunden.' });
  return res.status(204).send();
}

export async function markAllNotificationsRead(req: Request, res: Response) {
  const result = await prisma.notification.updateMany({
    where: { userId: req.user!.id, readAt: null },
    data: { readAt: new Date() },
  });
  return res.json({ updated: result.count });
}

export async function getNotificationPreferences(req: Request, res: Response) {
  const saved = await prisma.notificationPreference.findMany({
    where: { userId: req.user!.id },
  });
  const byCategory = new Map(saved.map((item) => [item.category, item]));
  return res.json(
    Object.values(NotificationCategory).map((category) => ({
      category,
      inApp: byCategory.get(category)?.inApp ?? true,
      push: byCategory.get(category)?.push ?? true,
    })),
  );
}

export async function saveNotificationPreferences(req: Request, res: Response) {
  const preferences = Array.isArray(req.body?.preferences) ? req.body.preferences : [];
  if (preferences.length > Object.values(NotificationCategory).length) {
    return res.status(400).json({ message: 'Zu viele Einstellungseinträge.' });
  }
  for (const preference of preferences as Record<string, unknown>[]) {
    const category = enumValue(
      NotificationCategory,
      preference.category,
      NotificationCategory.SYSTEM,
    );
    await prisma.notificationPreference.upsert({
      where: { userId_category: { userId: req.user!.id, category } },
      update: {
        inApp: preference.inApp !== false,
        push: preference.push !== false,
      },
      create: {
        userId: req.user!.id,
        category,
        inApp: preference.inApp !== false,
        push: preference.push !== false,
      },
    });
  }
  return getNotificationPreferences(req, res);
}

export async function registerPushSubscription(req: Request, res: Response) {
  const endpoint = text(req.body?.endpoint, 2000);
  if (!endpoint) return res.status(400).json({ message: 'Push-Endpunkt fehlt.' });
  const platform = enumValue(PushPlatform, req.body?.platform, PushPlatform.WEB);
  if (!validPushEndpoint(platform, endpoint)) {
    return res.status(400).json({ message: 'Push-Endpunkt ist ungültig.' });
  }
  const p256dh = text(req.body?.p256dh, 1000);
  const auth = text(req.body?.auth, 1000);
  if (platform === PushPlatform.WEB && (!p256dh || !auth)) {
    return res.status(400).json({ message: 'Web-Push-Schlüssel fehlen.' });
  }
  const subscription = await prisma.pushSubscription.upsert({
    where: { endpoint },
    update: {
      userId: req.user!.id,
      platform,
      p256dh,
      auth,
      deviceName: text(req.body?.deviceName, 160),
      isActive: true,
      lastUsedAt: new Date(),
    },
    create: {
      userId: req.user!.id,
      platform,
      endpoint,
      p256dh,
      auth,
      deviceName: text(req.body?.deviceName, 160),
    },
  });
  return res.status(201).json({ id: subscription.id, platform: subscription.platform });
}

export function validPushEndpoint(platform: PushPlatform, endpoint: string) {
  if (platform === PushPlatform.ANDROID) {
    return endpoint.length >= 20 && /^[A-Za-z0-9_:\-]+$/.test(endpoint);
  }
  try {
    return new URL(endpoint).protocol === 'https:';
  } catch {
    return false;
  }
}

export async function grantPushConsent(req: Request, res: Response) {
  const version = await prisma.consentTextVersion.findFirst({
    where: {
      type: ConsentDocumentType.PUSH_NOTIFICATIONS,
      isActive: true,
    },
    orderBy: { version: 'desc' },
  });
  if (!version) {
    return res.status(503).json({
      message: 'Der Einwilligungstext für Push-Benachrichtigungen fehlt.',
    });
  }
  await prisma.$transaction([
    prisma.userConsent.upsert({
      where: {
        userId_consentTextVersionId: {
          userId: req.user!.id,
          consentTextVersionId: version.id,
        },
      },
      update: {
        granted: true,
        grantedAt: new Date(),
        revokedAt: null,
        source: 'NOTIFICATION_SETTINGS',
      },
      create: {
        userId: req.user!.id,
        consentTextVersionId: version.id,
        granted: true,
        source: 'NOTIFICATION_SETTINGS',
      },
    }),
    prisma.registrationRequest.updateMany({
      where: { userId: req.user!.id },
      data: { pushOptIn: true },
    }),
  ]);
  return res.json({ granted: true, consentTextVersionId: version.id });
}

export async function removeCurrentPushSubscription(req: Request, res: Response) {
  const endpoint = text(req.body?.endpoint, 2000);
  if (!endpoint) return res.status(400).json({ message: 'Push-Endpunkt fehlt.' });
  await prisma.pushSubscription.updateMany({
    where: { endpoint, userId: req.user!.id },
    data: { isActive: false },
  });
  return res.status(204).send();
}

export async function removePushSubscription(req: Request, res: Response) {
  const result = await prisma.pushSubscription.updateMany({
    where: { id: req.params.id, userId: req.user!.id },
    data: { isActive: false },
  });
  if (!result.count) return res.status(404).json({ message: 'Push-Gerät nicht gefunden.' });
  return res.status(204).send();
}

export async function listPushSubscriptions(req: Request, res: Response) {
  const subscriptions = await prisma.pushSubscription.findMany({
    where: { userId: req.user!.id, isActive: true },
    select: {
      id: true,
      platform: true,
      deviceName: true,
      createdAt: true,
      lastUsedAt: true,
    },
    orderBy: { createdAt: 'desc' },
  });
  return res.json(subscriptions);
}
