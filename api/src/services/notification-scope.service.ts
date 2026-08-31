import { Prisma } from '@prisma/client';

/**
 * Direktkontakte gehören nie in den fachlichen Benachrichtigungsbestand und
 * dürfen von dessen Sammelaktionen weder gelesen noch gelöscht werden.
 */
export const familyContactEntityPrefix = 'FamilyContact:';

export const standardNotificationScope = {
  OR: [
    { entityType: null },
    { entityType: { not: { startsWith: familyContactEntityPrefix } } },
  ],
} satisfies Prisma.NotificationWhereInput;
