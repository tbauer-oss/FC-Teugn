import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';

export async function exportTalentsData(userId: string) {
  const players = await prisma.player.findMany({ where: { OR: [{ userId }, { parentLinks: { some: { parentId: userId, isLegalGuardian: true } } }] }, select: { id: true } });
  const ids = players.map(p => p.id);
  const [absences, goals, votes, invitationClaims] = await Promise.all([
    prisma.playerAbsence.findMany({ where: { OR: [{ playerId: { in: ids } }, { createdById: userId }] } }),
    prisma.learningGoal.findMany({ where: { playerId: { in: ids }, visibility: 'FAMILY' }, include: { observations: true } }),
    prisma.pollUnit.findMany({ where: { authorizedUserIds: { has: userId } }, select: { label: true, choices: true, respondedAt: true,
      poll: { select: { question: true, options: true, endsAt: true, unitType: true } } } }),
    prisma.invitationClaim.findMany({ where: { userId }, select: { createdAt: true, invitation: { select: { teamId: true, role: true, expiresAt: true, revokedAt: true } } } }),
  ]);
  return { absences, goals, votes, invitationClaims };
}
export async function removeTalentsAccountAccess(tx: Prisma.TransactionClient, userId: string) {
  await tx.invitationClaim.deleteMany({ where: { userId } });
  await tx.teamInvitation.updateMany({ where: { createdById: userId, revokedAt: null }, data: { revokedAt: new Date() } });
  const units = await tx.pollUnit.findMany({ where: { authorizedUserIds: { has: userId } }, include: { poll: { select: { unitType: true } } } });
  for (const unit of units) await tx.pollUnit.update({ where: { id: unit.id }, data: {
    authorizedUserIds: unit.authorizedUserIds.filter(id => id !== userId),
    ...(unit.respondedById === userId ? { respondedById: null } : {}),
    ...(unit.poll.unitType === 'PERSON' ? { label: 'Gelöschtes Konto' } : {}),
  } });
  const notices = await tx.talentsNotice.findMany({ where: { recipients: { has: userId } } });
  for (const notice of notices) await tx.talentsNotice.update({ where: { id: notice.id }, data: { recipients: notice.recipients.filter(id => id !== userId) } });
}
