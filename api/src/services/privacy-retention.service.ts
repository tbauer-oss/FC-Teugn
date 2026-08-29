import { prisma } from '../lib/prisma';
import { objectStorage } from './object-storage';

const dayMs = 24 * 60 * 60 * 1000;

function days(name: string, fallback: number, minimum: number) {
  const parsed = Number.parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(parsed) && parsed >= minimum ? parsed : fallback;
}

function before(now: Date, value: number) {
  return new Date(now.getTime() - value * dayMs);
}

export const familyContactRetentionDays = 30;

export async function purgeExpiredFamilyContacts(now = new Date()) {
  const expiredAttachments = await prisma.familyContactAttachment.findMany({
    where: { expiresAt: { lte: now } },
    select: {
      id: true,
      fileAssetId: true,
      fileAsset: { select: { pathname: true } },
    },
    take: 200,
  });
  let deletedAttachments = 0;
  for (const attachment of expiredAttachments) {
    try {
      // Erst das private Speicherobjekt entfernen. Bei einem vorübergehenden
      // Speicherfehler bleiben die Metadaten für einen sicheren Retry erhalten.
      await objectStorage.delete(attachment.fileAsset.pathname);
      await prisma.$transaction([
        prisma.familyContactAttachment.deleteMany({
          where: { id: attachment.id },
        }),
        prisma.fileAsset.deleteMany({ where: { id: attachment.fileAssetId } }),
      ]);
      deletedAttachments++;
    } catch {
      // Der nächste Cron-Lauf versucht genau dieses Objekt erneut.
    }
  }
  const notifications = await prisma.notification.deleteMany({
    where: {
      entityType: { startsWith: 'FamilyContact:' },
      expiresAt: { lte: now },
    },
  });
  return {
    notifications: notifications.count,
    attachments: deletedAttachments,
    pendingAttachmentRetries: expiredAttachments.length - deletedAttachments,
  };
}

export function messengerBackupRetentionPolicy() {
  const configured = Number.parseInt(
    process.env.MESSENGER_BACKUP_RETENTION_DAYS ?? '30',
    10,
  );
  const retentionDays = Number.isFinite(configured) ? configured : 30;
  return {
    maximumDays: familyContactRetentionDays,
    configuredDays: retentionDays,
    compliant: retentionDays > 0 && retentionDays <= familyContactRetentionDays,
  };
}

export function assertMessengerBackupRetentionPolicy() {
  const policy = messengerBackupRetentionPolicy();
  if (!policy.compliant) {
    throw new Error(
      `MESSENGER_BACKUP_RETENTION_DAYS muss zwischen 1 und ${familyContactRetentionDays} liegen.`,
    );
  }
  return policy;
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

  const familyContact = await purgeExpiredFamilyContacts(now);
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
    familyContact,
    backupPolicy: messengerBackupRetentionPolicy(),
  };
}
