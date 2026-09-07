import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { queueUserNotifications } from './notification.service';

export async function enqueueNotice(tx: Prisma.TransactionClient, recipients: string[],
  title: string, body: string, actionUrl: string, entityId: string) {
  if (!recipients.length) return;
  await tx.talentsNotice.create({ data: { recipients: [...new Set(recipients)], title, body, actionUrl, entityId } });
}
export async function processTalentsNotices() {
  const notices = await prisma.talentsNotice.findMany({ where: { deliveredAt: null }, orderBy: { createdAt: 'asc' }, take: 30 });
  for (const notice of notices) {
    try {
      let recipients = notice.recipients;
      if (notice.actionUrl === '/talents/polls') {
        const poll = await prisma.teamPoll.findUnique({ where: { id: notice.entityId }, include: { units: true } });
        const pending = poll && !poll.closedAt && !poll.archivedAt && poll.endsAt > new Date() ? poll.units.filter(u => !u.respondedAt) : [];
        const eligible = new Set(pending.flatMap(u => u.authorizedUserIds));
        const current = await prisma.user.findMany({ where: { id: { in: recipients.filter(id => eligible.has(id)) }, status: 'APPROVED' }, include: { parentLinks: true, playerProfile: { select: { id: true } }, memberships: { where: { status: 'APPROVED' } } } });
        recipients = current.filter(user => pending.some(unit => unit.authorizedUserIds.includes(user.id) &&
          (poll?.unitType === 'PERSON' ? [user.teamId, ...user.memberships.map(m => m.teamId)].some(id => poll!.teamIds.includes(id)) :
            [...user.parentLinks.map(l => l.playerId), user.playerProfile?.id].some(id => id && unit.playerIds.includes(id))))).map(u => u.id);
      }
      await queueUserNotifications(recipients, { category: notice.category,
        title: notice.title, body: notice.body, actionUrl: notice.actionUrl,
        entityId: notice.entityId, entityType: 'Talents', dedupeKey: `talents:${notice.id}` });
      await prisma.talentsNotice.update({ where: { id: notice.id }, data: { deliveredAt: new Date() } });
    } catch (error) { console.error('[talents-notice]', notice.id, error instanceof Error ? error.name : 'Error'); }
  }
}
