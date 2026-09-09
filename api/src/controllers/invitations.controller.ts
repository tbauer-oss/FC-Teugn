import { createHash, randomBytes } from 'node:crypto';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds } from '../services/team-access';
import { Permission } from '../security/permissions';
import { audit, DomainError, mutation, oneOf, permitted, requireTeam } from '../services/talents-domain';
import { enqueueNotice } from '../services/talents-notices';

const digest = (token: string) => createHash('sha256').update(token).digest('hex');
async function validInvitation(token: unknown) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) throw new DomainError(404, 'Die Einladung ist ungültig.');
  const invitation = await prisma.teamInvitation.findUnique({ where: { tokenHash: digest(token) }, include: { team: true } });
  if (!invitation || invitation.revokedAt || invitation.expiresAt <= new Date() || !invitation.team.isActive || invitation.team.deletedAt) throw new DomainError(410, 'Diese Einladung ist abgelaufen oder wurde zurückgezogen. Bitte eine neue Einladung anfordern.');
  return invitation;
}
export async function previewInvitation(req: Request, res: Response) {
  const invitation = await validInvitation(req.query.token);
  res.set('Cache-Control', 'no-store');
  return res.json({ teamId: invitation.teamId, teamName: invitation.team.name, role: invitation.role, expiresAt: invitation.expiresAt });
}
export async function listInvitations(req: Request, res: Response) {
  if (!permitted(req.user!, Permission.MANAGE_MEMBERS)) throw new DomainError(403, 'Keine Berechtigung für Einladungen.');
  const teamIds = await accessibleTeamIds(req.user!);
  const invitations = await prisma.teamInvitation.findMany({ where: { teamId: { in: teamIds } },
    include: { team: { select: { name: true } }, claims: { include: { user: { select: { id: true, name: true } } } } },
    orderBy: { createdAt: 'desc' }, take: 100 });
  const pending = await prisma.teamMembership.findMany({ where: { teamId: { in: teamIds }, status: 'PENDING',
    user: { invitationClaims: { some: { invitation: { teamId: { in: teamIds } } } } } },
    include: { user: { select: { name: true, status: true } }, team: { select: { name: true } } } });
  return res.json({ invitations: invitations.map(({ tokenHash: _, ...invitation }) => invitation), pending });
}
export async function createInvitation(req: Request, res: Response) {
  const teamId = String(req.body.teamId ?? '');
  await requireTeam(req.user!, teamId, Permission.MANAGE_MEMBERS);
  const role = oneOf(req.body.role, ['PARENT', 'PLAYER', 'COACH', 'ASSISTANT_COACH', 'TEAM_MANAGER']);
  const days = Number(req.body.days ?? 7);
  if (!Number.isInteger(days) || days < 1 || days > 30) throw new DomainError(400, 'Die Gültigkeit muss zwischen 1 und 30 Tagen liegen.');
  return mutation(req, res, async tx => {
    const token = randomBytes(32).toString('hex');
    const invitation = await tx.teamInvitation.create({ data: { teamId, role, tokenHash: digest(token),
      createdById: req.user!.id, expiresAt: new Date(Date.now() + days * 86400000) } });
    await audit(tx, req.user!, teamId, 'INVITATION_CREATED', invitation.id);
    const base = (process.env.PUBLIC_APP_URL?.trim() || 'https://app.fc-teugn-talents.de').replace(/\/+$/, '');
    return { id: invitation.id, expiresAt: invitation.expiresAt, url: `${base}/#/join?token=${token}` };
  });
}
export async function revokeInvitation(req: Request, res: Response) {
  const invitation = await prisma.teamInvitation.findUnique({ where: { id: req.params.id } });
  if (!invitation) throw new DomainError(404, 'Einladung nicht gefunden.');
  await requireTeam(req.user!, invitation.teamId, Permission.MANAGE_MEMBERS);
  return mutation(req, res, async tx => {
    await tx.teamInvitation.update({ where: { id: invitation.id }, data: { revokedAt: new Date() } });
    await audit(tx, req.user!, invitation.teamId, 'INVITATION_REVOKED', invitation.id);
    return { revoked: true };
  });
}
export async function claimInvitation(req: Request, res: Response) {
  const invitation = await validInvitation(req.body.token);
  return mutation(req, res, async tx => {
    const current = await tx.teamInvitation.findUniqueOrThrow({ where: { id: invitation.id } });
    if (current.revokedAt || current.expiresAt <= new Date()) throw new DomainError(410, 'Einladung nicht mehr gültig.');
    const existing = await tx.teamMembership.findUnique({ where: { userId_teamId: { userId: req.user!.id, teamId: current.teamId } } });
    if (existing?.status === 'APPROVED') return { status: 'APPROVED', teamName: invitation.team.name };
    await tx.invitationClaim.upsert({ where: { invitationId_userId: { invitationId: current.id, userId: req.user!.id } }, update: {},
      create: { invitationId: current.id, userId: req.user!.id } });
    await tx.teamMembership.upsert({ where: { userId_teamId: { userId: req.user!.id, teamId: current.teamId } },
      update: { status: 'PENDING', role: current.role }, create: { userId: req.user!.id, teamId: current.teamId, role: current.role, status: 'PENDING' } });
    await enqueueNotice(tx, [current.createdById], 'Mannschaftszugang prüfen', 'Eine Einladung wurde angenommen. Bitte die Mannschaftszuordnung prüfen.', '/talents/invitations', current.id);
    await audit(tx, req.user!, current.teamId, 'INVITATION_CLAIMED', current.id);
    return { status: 'PENDING', teamName: invitation.team.name };
  });
}
export async function reviewInvitationClaim(req: Request, res: Response) {
  const membership = await prisma.teamMembership.findUnique({ where: { id: req.params.id } });
  if (!membership) throw new DomainError(404, 'Mannschaftsanfrage nicht gefunden.');
  await requireTeam(req.user!, membership.teamId, Permission.MANAGE_MEMBERS);
  const status = oneOf(req.body.status, ['APPROVED', 'REJECTED']);
  return mutation(req, res, async tx => {
    const account = await tx.user.findUniqueOrThrow({ where: { id: membership.userId } });
    const current = await tx.teamMembership.findUniqueOrThrow({ where: { id: membership.id } });
    if (current.status !== 'PENDING' || !await tx.invitationClaim.findFirst({ where: { userId: membership.userId, invitation: { teamId: membership.teamId } } })) throw new DomainError(409, 'Diese Anfrage wurde bereits bearbeitet. Bitte neu laden.');
    if (status === 'APPROVED' && account.status !== 'APPROVED') throw new DomainError(409, 'Zuerst den App-Zugang in der Mitgliederverwaltung prüfen und freigeben.');
    if (status === 'APPROVED' && ['COACH', 'ASSISTANT_COACH', 'TEAM_MANAGER'].includes(current.role) && ['PARENT', 'PLAYER'].includes(account.role)) throw new DomainError(409, 'Dieser Zugang hat noch eine Familienrolle. Zuerst die passende Trainer- oder Betreuerrolle in der Mitgliederverwaltung prüfen; anschließend die Mannschaftsanfrage freigeben.');
    if (membership.userId === req.user!.id) throw new DomainError(403, 'Die eigene zusätzliche Rolle muss eine andere zuständige Person bestätigen.');
    const result = await tx.teamMembership.update({ where: { id: membership.id }, data: { status } });
    await audit(tx, req.user!, membership.teamId, 'INVITATION_MEMBERSHIP_REVIEWED', result.id, { status });
    await enqueueNotice(tx, [membership.userId], 'Mannschaftszugang geprüft', status === 'APPROVED' ? 'Dein zusätzlicher Mannschaftszugang wurde freigegeben.' : 'Deine Mannschaftsanfrage wurde abgelehnt. Bitte wende dich an das Trainerteam.', '/talents/assistant', result.id);
    return { status };
  });
}
