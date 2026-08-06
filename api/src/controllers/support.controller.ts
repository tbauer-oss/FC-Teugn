import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import {
  AccountStatus,
  FileAssetKind,
  NotificationCategory,
  Prisma,
  Role,
  SupportCategory,
  SupportStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { mediaAssetUrl } from '../services/media-access';
import { notifyUsers } from '../services/notification.service';
import { objectStorage } from '../services/object-storage';

const allowedMetadataKeys = new Set([
  'appVersion',
  'buildNumber',
  'platform',
  'osVersion',
  'deviceModel',
  'windowSize',
  'route',
  'occurredAt',
  'online',
  'teamContext',
  'ageGroupContext',
  'permissionState',
]);

function clean(value: unknown, maximum = 1000) {
  return typeof value === 'string' && value.trim()
    ? value.trim().slice(0, maximum)
    : null;
}

function parsedJson(value: unknown) {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return {};
  }
}

export function sanitizeTechnicalMetadata(value: unknown) {
  const input = parsedJson(value);
  if (!input || typeof input !== 'object' || Array.isArray(input)) return {};
  return Object.fromEntries(
    Object.entries(input as Record<string, unknown>)
      .filter(([key]) => allowedMetadataKeys.has(key))
      .map(([key, item]) => [
        key,
        typeof item === 'string' ? item.slice(0, 300) : item,
      ]),
  );
}

const ticketInclude = {
  creator: { select: { id: true, name: true, email: true, phone: true } },
  assignedTo: { select: { id: true, name: true } },
  attachmentAsset: { select: { id: true, originalName: true, contentType: true, size: true } },
  messages: {
    orderBy: { createdAt: 'asc' as const },
    include: { author: { select: { id: true, name: true, role: true } } },
  },
} as const;

type Ticket = Prisma.SupportTicketGetPayload<{ include: typeof ticketInclude }>;

function serializeTicket(ticket: Ticket, administrator: boolean) {
  return {
    ...ticket,
    technicalMetadata: administrator ? ticket.technicalMetadata : undefined,
    attachment: ticket.attachmentAsset
      ? {
          ...ticket.attachmentAsset,
          downloadUrl: mediaAssetUrl(ticket.attachmentAsset.id, '15m'),
        }
      : null,
    attachmentAsset: undefined,
    messages: ticket.messages.filter((message) => administrator || !message.internal),
    capabilities: {
      canReply: administrator || ticket.status !== SupportStatus.CLOSED,
      canManage: administrator,
      canWriteInternalNote: administrator,
    },
  };
}

async function supportAdministrators() {
  const users = await prisma.user.findMany({
    where: { role: Role.SUPER_ADMIN, status: AccountStatus.APPROVED },
    select: { id: true },
  });
  return users.map((user) => user.id);
}

export async function createSupportTicket(req: Request, res: Response) {
  const category = String(req.body.category ?? '').toUpperCase() as SupportCategory;
  const subject = clean(req.body.subject, 160);
  const description = clean(req.body.description, 5000);
  if (!Object.values(SupportCategory).includes(category) || !subject || !description) {
    return res.status(400).json({
      message: 'Kategorie, Betreff und eine Beschreibung sind erforderlich.',
    });
  }

  let stored: Awaited<ReturnType<typeof objectStorage.uploadPrivate>> | null = null;
  if (req.file) {
    const extension = req.file.originalname.split('.').pop()?.replace(/[^a-z0-9]/gi, '') || 'bin';
    stored = await objectStorage.uploadPrivate(
      `support/${req.user!.id}/${randomUUID()}.${extension.toLowerCase()}`,
      req.file.buffer,
      req.file.mimetype,
    );
  }
  try {
    const ticketId = await prisma.$transaction(async (tx) => {
      const attachment = req.file && stored
        ? await tx.fileAsset.create({
            data: {
              kind: FileAssetKind.SUPPORT_ATTACHMENT,
              pathname: stored.pathname,
              storageUrl: stored.url,
              originalName: req.file.originalname.slice(0, 255),
              contentType: req.file.mimetype,
              size: req.file.size,
              checksum: createHash('sha256').update(req.file.buffer).digest('hex'),
              uploadedById: req.user!.id,
              isPrivate: true,
            },
          })
        : null;
      const created = await tx.supportTicket.create({
        data: {
          creatorId: req.user!.id,
          category,
          subject,
          description,
          appArea: clean(req.body.appArea, 160),
          contactRequested: req.body.contactRequested === true || req.body.contactRequested === 'true',
          technicalMetadata: sanitizeTechnicalMetadata(
            req.body.technicalMetadata,
          ) as Prisma.InputJsonValue,
          attachmentAssetId: attachment?.id,
        },
        include: ticketInclude,
      });
      await tx.auditLog.create({
        data: {
          actorId: req.user!.id,
          teamId: req.user!.teamId,
          action: 'SUPPORT_TICKET_CREATED',
          entityType: 'SupportTicket',
          entityId: created.id,
          metadata: { category, appArea: created.appArea, hasAttachment: Boolean(attachment) },
        },
      });
      return created.id;
    });
    const ticket = await prisma.supportTicket.findUniqueOrThrow({
      where: { id: ticketId },
      include: ticketInclude,
    });
    const admins = (await supportAdministrators()).filter((id) => id !== req.user!.id);
    await notifyUsers(admins, {
      category: NotificationCategory.SUPPORT,
      title: 'Neue Support-Anfrage',
      body: `${ticket.creator.name}: ${ticket.subject}`,
      actionUrl: `/support/${ticket.id}`,
      entityType: 'SupportTicket',
      entityId: ticket.id,
      dedupeKey: `support-created:${ticket.id}`,
      pushEnabled: req.body.pushEnabled !== false && req.body.pushEnabled !== 'false',
    });
    return res.status(201).json(serializeTicket(ticket, req.user!.role === Role.SUPER_ADMIN));
  } catch (error) {
    if (stored) objectStorage.delete(stored.pathname).catch(() => undefined);
    throw error;
  }
}

export async function listSupportTickets(req: Request, res: Response) {
  const administrator = req.user!.role === Role.SUPER_ADMIN;
  const status = String(req.query.status ?? '').toUpperCase() as SupportStatus;
  const tickets = await prisma.supportTicket.findMany({
    where: {
      ...(!administrator ? { creatorId: req.user!.id } : {}),
      ...(Object.values(SupportStatus).includes(status) ? { status } : {}),
    },
    orderBy: { updatedAt: 'desc' },
    include: ticketInclude,
  });
  return res.json(tickets.map((ticket) => serializeTicket(ticket, administrator)));
}

export async function getSupportTicket(req: Request, res: Response) {
  const administrator = req.user!.role === Role.SUPER_ADMIN;
  const ticket = await prisma.supportTicket.findFirst({
    where: { id: req.params.id, ...(!administrator ? { creatorId: req.user!.id } : {}) },
    include: ticketInclude,
  });
  if (!ticket) return res.status(404).json({ message: 'Support-Anfrage nicht gefunden.' });
  return res.json(serializeTicket(ticket, administrator));
}

export async function replySupportTicket(req: Request, res: Response) {
  const administrator = req.user!.role === Role.SUPER_ADMIN;
  const body = clean(req.body.body, 5000);
  const internal = administrator && req.body.internal === true;
  if (!body) return res.status(400).json({ message: 'Bitte eine Nachricht eingeben.' });
  const existing = await prisma.supportTicket.findFirst({
    where: { id: req.params.id, ...(!administrator ? { creatorId: req.user!.id } : {}) },
  });
  if (!existing) return res.status(404).json({ message: 'Support-Anfrage nicht gefunden.' });
  if (!administrator && existing.status === SupportStatus.CLOSED) {
    return res.status(409).json({ message: 'Diese Support-Anfrage ist bereits geschlossen.' });
  }
  const ticket = await prisma.$transaction(async (tx) => {
    await tx.supportMessage.create({
      data: { ticketId: existing.id, authorId: req.user!.id, body, internal },
    });
    const nextStatus = administrator && !internal
      ? SupportStatus.QUESTION
      : !administrator && existing.status !== SupportStatus.CLOSED
        ? SupportStatus.OPEN
        : existing.status;
    const updated = await tx.supportTicket.update({
      where: { id: existing.id },
      data: {
        status: nextStatus,
        ...(administrator && !existing.assignedToId ? { assignedToId: req.user!.id } : {}),
      },
      include: ticketInclude,
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: internal ? 'SUPPORT_INTERNAL_NOTE_ADDED' : 'SUPPORT_REPLY_ADDED',
        entityType: 'SupportTicket',
        entityId: existing.id,
        metadata: { status: nextStatus },
      },
    });
    return updated;
  });
  if (!internal) {
    const recipients = administrator
      ? [existing.creatorId]
      : (await supportAdministrators()).filter((id) => id !== req.user!.id);
    await notifyUsers(recipients, {
      category: NotificationCategory.SUPPORT,
      title: administrator ? 'Antwort vom technischen Support' : 'Neue Antwort auf Support-Anfrage',
      body: ticket.subject,
      actionUrl: `/support/${ticket.id}`,
      entityType: 'SupportTicket',
      entityId: ticket.id,
      dedupeKey: `support-reply:${ticket.id}:${ticket.messages[ticket.messages.length - 1]?.id ?? randomUUID()}`,
      pushEnabled: req.body.pushEnabled !== false && req.body.pushEnabled !== 'false',
    });
  }
  return res.json(serializeTicket(ticket, administrator));
}

export async function updateSupportStatus(req: Request, res: Response) {
  if (req.user!.role !== Role.SUPER_ADMIN) {
    return res.status(403).json({ message: 'Nur die Systemadministration darf den Status ändern.' });
  }
  const status = String(req.body.status ?? '').toUpperCase() as SupportStatus;
  if (!Object.values(SupportStatus).includes(status)) {
    return res.status(400).json({ message: 'Ungültiger Support-Status.' });
  }
  const existing = await prisma.supportTicket.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ message: 'Support-Anfrage nicht gefunden.' });
  const now = new Date();
  const ticket = await prisma.$transaction(async (tx) => {
    const updated = await tx.supportTicket.update({
      where: { id: existing.id },
      data: {
        status,
        assignedToId: clean(req.body.assignedToId) ?? existing.assignedToId ?? req.user!.id,
        resolvedAt: status === SupportStatus.RESOLVED ? now : existing.resolvedAt,
        closedAt: status === SupportStatus.CLOSED ? now : null,
      },
      include: ticketInclude,
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: 'SUPPORT_STATUS_CHANGED',
        entityType: 'SupportTicket',
        entityId: existing.id,
        metadata: { previousStatus: existing.status, status },
      },
    });
    return updated;
  });
  await notifyUsers([existing.creatorId], {
    category: NotificationCategory.SUPPORT,
    title: 'Support-Status aktualisiert',
    body: `„${ticket.subject}“: ${status}`,
    actionUrl: `/support/${ticket.id}`,
    entityType: 'SupportTicket',
    entityId: ticket.id,
    dedupeKey: `support-status:${ticket.id}:${status}:${now.getTime()}`,
  });
  return res.json(serializeTicket(ticket, true));
}
