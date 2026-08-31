import {
  AccountStatus,
  ConsentDocumentType,
  NotificationCategory,
  NotificationDeliveryStatus,
  PushPlatform,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import {
  defaultNotificationPreference,
  pushConfiguration,
  adminPushScenarios,
  AdminPushScenario,
  sendAdminScenarioTestPush,
  sendAdminTestPush,
} from '../services/notification.service';
import { standardNotificationScope } from '../services/notification-scope.service';

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
  const notifications = await prisma.notification.findMany({
    where: {
      userId,
      category: { notIn: disabled.map((item) => item.category) },
      AND: [
        standardNotificationScope,
        { OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] },
      ],
    },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  // Altversionen verwendeten teils die Registrierungs-ID, teils die Benutzer-
  // ID als Referenz. Der aktuelle Pending-Status ist deshalb die einzige
  // autoritative Quelle. So verschwinden auch historische Hinweise, deren
  // Freigabe längst abgeschlossen ist, ohne die Historie zu löschen.
  const registrationNotifications = notifications
    .filter(
      (item) =>
        item.category === NotificationCategory.REGISTRATION &&
        item.readAt === null,
    );
  const registrationReferences = registrationNotifications
    .map((item) => item.entityId)
    .filter((value): value is string => Boolean(value));
  const pendingRegistrations = registrationReferences.length === 0
    ? []
    : await prisma.registrationRequest.findMany({
        where: {
          user: { status: AccountStatus.PENDING },
          OR: [
            { id: { in: registrationReferences } },
            { userId: { in: registrationReferences } },
          ],
        },
        select: { id: true, userId: true },
      });
  const pendingReferences = new Set(
    pendingRegistrations.flatMap((registration) => [
      registration.id,
      registration.userId,
    ]),
  );
  const hasUnreferencedRegistration = registrationNotifications.some(
    (item) => !item.entityId,
  );
  const anyPendingRegistration = hasUnreferencedRegistration
    ? await prisma.registrationRequest.count({
        where: { user: { status: AccountStatus.PENDING } },
      }) > 0
    : false;
  const completedNotificationIds = registrationNotifications
    .filter((item) =>
      item.entityId
        ? !pendingReferences.has(item.entityId)
        : !anyPendingRegistration,
    )
    .map((item) => item.id);
  const completedAt = new Date();
  if (completedNotificationIds.length > 0) {
    await prisma.notification.updateMany({
      where: { id: { in: completedNotificationIds }, readAt: null },
      data: { readAt: completedAt },
    });
  }
  return res.json(
    notifications.map((item) =>
      completedNotificationIds.includes(item.id) && item.readAt === null
        ? { ...item, readAt: completedAt }
        : item,
    ),
  );
}

export async function testOwnPushScenario(req: Request, res: Response) {
  const scenario = String(req.body?.scenario ?? '').toUpperCase();
  if (!Object.prototype.hasOwnProperty.call(adminPushScenarios, scenario)) {
    return res.status(400).json({
      message: 'Unbekanntes Push-Testszenario.',
      scenarios: Object.keys(adminPushScenarios),
    });
  }
  const result = await sendAdminScenarioTestPush(
    req.user!.id,
    scenario as AdminPushScenario,
  );
  return res.json(result);
}

export async function markNotificationRead(req: Request, res: Response) {
  const result = await prisma.notification.updateMany({
    where: {
      id: req.params.id,
      userId: req.user!.id,
      ...standardNotificationScope,
    },
    data: { readAt: new Date() },
  });
  if (!result.count) return res.status(404).json({ message: 'Benachrichtigung nicht gefunden.' });
  return res.status(204).send();
}

export async function markAllNotificationsRead(req: Request, res: Response) {
  const result = await prisma.notification.updateMany({
    where: {
      userId: req.user!.id,
      readAt: null,
      ...standardNotificationScope,
    },
    data: { readAt: new Date() },
  });
  return res.json({ updated: result.count });
}

export async function deleteReadNotifications(req: Request, res: Response) {
  const result = await prisma.$transaction(async (tx) => {
    const deleted = await tx.notification.deleteMany({
      where: {
        userId: req.user!.id,
        readAt: { not: null },
        ...standardNotificationScope,
      },
    });
    if (deleted.count > 0) {
      await tx.auditLog.create({
        data: {
          actorId: req.user!.id,
          teamId: req.user!.teamId,
          action: 'READ_NOTIFICATIONS_BULK_DELETED',
          entityType: 'Notification',
          metadata: { deletedCount: deleted.count },
        },
      });
    }
    return deleted;
  });
  return res.json({ deletedCount: result.count });
}

export async function deleteNotification(req: Request, res: Response) {
  const notification = await prisma.notification.findFirst({
    where: {
      id: req.params.id,
      userId: req.user!.id,
      ...standardNotificationScope,
    },
    select: { id: true, category: true, title: true },
  });
  if (!notification) {
    return res.status(404).json({ message: 'Benachrichtigung nicht gefunden.' });
  }
  await prisma.$transaction(async (tx) => {
    await tx.notification.delete({ where: { id: notification.id } });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: 'NOTIFICATION_DELETED',
        entityType: 'Notification',
        entityId: notification.id,
        metadata: {
          category: notification.category,
          title: notification.title,
        },
      },
    });
  });
  return res.status(204).send();
}

export async function getNotificationPreferences(req: Request, res: Response) {
  const saved = await prisma.notificationPreference.findMany({
    where: { userId: req.user!.id },
  });
  const byCategory = new Map(saved.map((item) => [item.category, item]));
  return res.json(
    Object.values(NotificationCategory).map((category) => ({
      category,
      inApp:
        byCategory.get(category)?.inApp ??
        defaultNotificationPreference(category).inApp,
      push:
        byCategory.get(category)?.push ??
        defaultNotificationPreference(category).push,
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
  const existing = await prisma.pushSubscription.findUnique({
    where: { endpoint },
    select: { id: true, administrativelyDisabledAt: true },
  });
  const subscription = await prisma.pushSubscription.upsert({
    where: { endpoint },
    update: {
      userId: req.user!.id,
      platform,
      p256dh,
      auth,
      deviceName: text(req.body?.deviceName, 160),
      // An administrative block must not be undone by an automatic token
      // refresh when the app starts again.
      isActive: pushDeviceMayAutoReactivate(
        existing?.administrativelyDisabledAt ?? null,
      ),
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
  return res.status(201).json({
    id: subscription.id,
    platform: subscription.platform,
    isActive: subscription.isActive,
    administrativelyDisabled: subscription.administrativelyDisabledAt != null,
  });
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

export const PUSH_DEVICE_STALE_AFTER_DAYS = 60;

export function pushDeviceMayAutoReactivate(
  administrativelyDisabledAt: Date | null,
) {
  return administrativelyDisabledAt == null;
}

export function pushDeviceHealth(
  isActive: boolean,
  lastUsedAt: Date,
  now = new Date(),
) {
  if (!isActive) return 'DISABLED' as const;
  const staleAt = new Date(now);
  staleAt.setUTCDate(staleAt.getUTCDate() - PUSH_DEVICE_STALE_AFTER_DAYS);
  return lastUsedAt < staleAt ? ('STALE' as const) : ('ACTIVE' as const);
}

export const disabledPushDeviceWhere = { isActive: false } as const;

export async function listAdminPushDevices(_req: Request, res: Response) {
  const devices = await prisma.pushSubscription.findMany({
    select: {
      id: true,
      platform: true,
      deviceName: true,
      isActive: true,
      administrativelyDisabledAt: true,
      lastUsedAt: true,
      createdAt: true,
      updatedAt: true,
      user: {
        select: {
          id: true,
          name: true,
          email: true,
          role: true,
          status: true,
          team: { select: { name: true } },
        },
      },
      _count: { select: { deliveries: true } },
      deliveries: {
        orderBy: { createdAt: 'desc' },
        take: 1,
        select: {
          status: true,
          errorCode: true,
          createdAt: true,
          sentAt: true,
        },
      },
    },
    orderBy: [{ isActive: 'desc' }, { lastUsedAt: 'desc' }],
  });
  const now = new Date();
  return res.json(
    devices.map(({ _count, deliveries, ...device }) => ({
      ...device,
      health: pushDeviceHealth(device.isActive, device.lastUsedAt, now),
      deliveryCount: _count.deliveries,
      lastDelivery: deliveries[0] ?? null,
    })),
  );
}

export async function setAdminPushDeviceState(req: Request, res: Response) {
  if (typeof req.body?.isActive !== 'boolean') {
    return res.status(400).json({ message: 'Der gewünschte Gerätestatus fehlt.' });
  }
  const device = await prisma.pushSubscription.findUnique({
    where: { id: req.params.id },
    select: {
      id: true,
      userId: true,
      deviceName: true,
      platform: true,
      user: { select: { teamId: true } },
    },
  });
  if (!device) return res.status(404).json({ message: 'Push-Gerät nicht gefunden.' });

  const isActive = req.body.isActive;
  const now = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.pushSubscription.update({
      where: { id: device.id },
      data: {
        isActive,
        administrativelyDisabledAt: isActive ? null : now,
        administrativelyDisabledByUserId: isActive ? null : req.user!.id,
      },
    });
    if (!isActive) {
      await tx.notificationDelivery.updateMany({
        where: {
          subscriptionId: device.id,
          status: NotificationDeliveryStatus.PENDING,
        },
        data: {
          status: NotificationDeliveryStatus.SKIPPED,
          lastAttemptAt: now,
          errorCode: 'DEVICE_DISABLED_BY_ADMIN',
        },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: device.user.teamId,
        action: isActive ? 'PUSH_DEVICE_ENABLED' : 'PUSH_DEVICE_DISABLED',
        entityType: 'PushSubscription',
        entityId: device.id,
        metadata: {
          ownerUserId: device.userId,
          deviceName: device.deviceName,
          platform: device.platform,
        },
      },
    });
  });
  return res.json({ id: device.id, isActive });
}

export async function deleteAdminPushDevice(req: Request, res: Response) {
  const device = await prisma.pushSubscription.findUnique({
    where: { id: req.params.id },
    select: {
      id: true,
      userId: true,
      deviceName: true,
      platform: true,
      user: { select: { teamId: true } },
    },
  });
  if (!device) return res.status(404).json({ message: 'Push-Gerät nicht gefunden.' });
  await prisma.$transaction(async (tx) => {
    await tx.pushSubscription.delete({ where: { id: device.id } });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: device.user.teamId,
        action: 'PUSH_DEVICE_DELETED',
        entityType: 'PushSubscription',
        entityId: device.id,
        metadata: {
          ownerUserId: device.userId,
          deviceName: device.deviceName,
          platform: device.platform,
        },
      },
    });
  });
  return res.status(204).send();
}

export async function deleteAllDisabledAdminPushDevices(
  req: Request,
  res: Response,
) {
  const result = await prisma.$transaction(async (tx) => {
    const devices = await tx.pushSubscription.findMany({
      where: disabledPushDeviceWhere,
      select: {
        id: true,
        userId: true,
        platform: true,
      },
    });
    if (!devices.length) return { count: 0 };

    const deleted = await tx.pushSubscription.deleteMany({
      where: {
        id: { in: devices.map((device) => device.id) },
        ...disabledPushDeviceWhere,
      },
    });
    if (deleted.count > 0) {
      await tx.auditLog.create({
        data: {
          actorId: req.user!.id,
          action: 'DISABLED_PUSH_DEVICES_BULK_DELETED',
          entityType: 'PushSubscription',
          metadata: {
            deletedCount: deleted.count,
            affectedUserCount: new Set(
              devices.map((device) => device.userId),
            ).size,
            platforms: [...new Set(devices.map((device) => device.platform))],
          },
        },
      });
    }
    return deleted;
  });

  return res.json({ deletedCount: result.count });
}
