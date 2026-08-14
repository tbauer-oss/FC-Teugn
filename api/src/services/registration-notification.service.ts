import {
  AccountStatus,
  NotificationCategory,
  Role,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import {
  NotificationInput,
  notifyUsers,
} from './notification.service';

type PendingRegistrationNotificationInput = {
  registrationRequestId: string;
  applicantName: string;
};

export function pendingRegistrationNotification(
  input: PendingRegistrationNotificationInput,
): NotificationInput {
  return {
    category: NotificationCategory.REGISTRATION,
    title: 'Neue Registrierung wartet auf Freigabe',
    body: `${input.applicantName} hat sich registriert und wartet auf deine Prüfung.`,
    actionUrl: '/trainer/approvals',
    entityType: 'RegistrationRequest',
    entityId: input.registrationRequestId,
    dedupeKey: `registration-pending:${input.registrationRequestId}`,
    forcePush: true,
    forceInApp: true,
  };
}

export async function notifyPendingRegistrationAdministrators(
  input: PendingRegistrationNotificationInput,
) {
  const administrators = await prisma.user.findMany({
    where: {
      role: Role.SUPER_ADMIN,
      status: AccountStatus.APPROVED,
    },
    select: { id: true },
  });
  return notifyUsers(
    administrators.map((administrator) => administrator.id),
    pendingRegistrationNotification(input),
  );
}
