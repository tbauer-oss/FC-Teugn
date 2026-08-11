import { prisma } from '../lib/prisma';

const dayMs = 24 * 60 * 60 * 1000;

function days(name: string, fallback: number, minimum: number) {
  const parsed = Number.parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(parsed) && parsed >= minimum ? parsed : fallback;
}

function before(now: Date, value: number) {
  return new Date(now.getTime() - value * dayMs);
}

/**
 * Conservative operational retention. Domain records such as matches,
 * attendance, consents, incident documentation and audit evidence are not
 * deleted here because they require a formally approved club retention policy.
 */
export async function applyOperationalRetention(now = new Date()) {
  const sessionGraceDays = days('RETENTION_SESSION_GRACE_DAYS', 30, 7);
  const pushDeviceDays = days('RETENTION_INACTIVE_PUSH_DAYS', 180, 30);
  const readNotificationDays = days('RETENTION_READ_NOTIFICATION_DAYS', 365, 30);
  const notificationMaximumDays = days('RETENTION_NOTIFICATION_MAX_DAYS', 730, 90);

  const [idempotency, passwordResets, refreshTokens, pushSubscriptions, notifications] =
    await prisma.$transaction([
      prisma.idempotencyRecord.deleteMany({ where: { expiresAt: { lte: now } } }),
      prisma.passwordResetToken.deleteMany({
        where: {
          OR: [
            { expiresAt: { lte: before(now, sessionGraceDays) } },
            { consumedAt: { lte: before(now, sessionGraceDays) } },
          ],
        },
      }),
      prisma.refreshToken.deleteMany({
        where: {
          OR: [
            { expiresAt: { lte: before(now, sessionGraceDays) } },
            { revokedAt: { lte: before(now, sessionGraceDays) } },
          ],
        },
      }),
      prisma.pushSubscription.deleteMany({
        where: {
          isActive: false,
          updatedAt: { lte: before(now, pushDeviceDays) },
        },
      }),
      prisma.notification.deleteMany({
        where: {
          OR: [
            { expiresAt: { lte: now } },
            {
              readAt: { not: null },
              createdAt: { lte: before(now, readNotificationDays) },
            },
            { createdAt: { lte: before(now, notificationMaximumDays) } },
          ],
        },
      }),
    ]);

  return {
    idempotency: idempotency.count,
    passwordResets: passwordResets.count,
    refreshTokens: refreshTokens.count,
    pushSubscriptions: pushSubscriptions.count,
    notifications: notifications.count,
  };
}
