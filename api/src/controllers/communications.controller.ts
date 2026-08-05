import {
  AccountStatus,
  AnnouncementAudience,
  AnnouncementPriority,
  AnnouncementStatus,
  NotificationCategory,
  Prisma,
  Role as PrismaRole,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { accessibleTeamIds, contextualTeamIds } from '../services/team-access';
import { notifyUsers } from '../services/notification.service';
import { Role } from '../types/enums';

const staffRoles = new Set<string>([
  PrismaRole.SUPER_ADMIN,
  PrismaRole.CLUB_ADMIN,
  PrismaRole.YOUTH_DIRECTOR,
  PrismaRole.COACH,
  PrismaRole.ASSISTANT_COACH,
  PrismaRole.TEAM_MANAGER,
  PrismaRole.TRAINER_ADMIN,
  PrismaRole.TRAINER,
]);

const announcementInclude = {
  author: { select: { id: true, name: true } },
  targetTeams: {
    include: { team: { select: { id: true, name: true, shortName: true } } },
  },
  recipients: { select: { userId: true } },
  attachments: true,
  reads: { select: { userId: true, readAt: true } },
} as const;

function text(value: unknown, max = 1000) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, max) : null;
}

function date(value: unknown) {
  if (!value) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
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

function safeUrl(value: unknown) {
  const normalized = text(value, 500);
  if (!normalized) return null;
  try {
    const parsed = new URL(normalized);
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed.toString() : null;
  } catch {
    return null;
  }
}

export function audienceVisible(role: string, audience: AnnouncementAudience) {
  if (
    audience === AnnouncementAudience.ALL_MEMBERS ||
    audience === AnnouncementAudience.INDIVIDUALS
  ) {
    return true;
  }
  if (audience === AnnouncementAudience.PARENTS) return role === PrismaRole.PARENT;
  if (audience === AnnouncementAudience.PLAYERS) return role === PrismaRole.PLAYER;
  return staffRoles.has(role);
}

export function canPermanentlyDeleteAnnouncement(role: string) {
  return role === PrismaRole.SUPER_ADMIN;
}

async function usersForAnnouncement(
  teamIds: string[],
  audience: AnnouncementAudience,
  requestedRecipientIds: string[] = [],
) {
  const members = await prisma.user.findMany({
    where: {
      status: AccountStatus.APPROVED,
      OR: [
        { teamId: { in: teamIds } },
        {
          memberships: {
            some: { teamId: { in: teamIds }, status: AccountStatus.APPROVED },
          },
        },
      ],
    },
    select: { id: true, role: true },
  });
  const available = new Map(members.map((member) => [member.id, member]));
  if (audience === AnnouncementAudience.INDIVIDUALS) {
    return [...new Set(requestedRecipientIds)].filter((id) => available.has(id));
  }
  return members
    .filter((member) => audienceVisible(member.role, audience))
    .map((member) => member.id);
}

async function notifyAnnouncement(announcementId: string) {
  const announcement = await prisma.announcement.findUnique({
    where: { id: announcementId },
    include: { targetTeams: true, recipients: true },
  });
  if (!announcement) return;
  const userIds = await usersForAnnouncement(
    announcement.targetTeams.map((target) => target.teamId),
    announcement.audience,
    announcement.recipients.map((recipient) => recipient.userId),
  );
  await notifyUsers(userIds, {
    category:
      announcement.priority === AnnouncementPriority.URGENT
        ? NotificationCategory.URGENT
        : NotificationCategory.ANNOUNCEMENT,
    title: announcement.title,
    body: announcement.body,
    actionUrl: `/messages/${announcement.id}`,
    entityType: 'Announcement',
    entityId: announcement.id,
    expiresAt: announcement.expiresAt,
    pushEnabled: announcement.pushEnabled,
  });
}

export async function processDueAnnouncements() {
  const due = await prisma.announcement.findMany({
    where: {
      deletedAt: null,
      status: AnnouncementStatus.SCHEDULED,
      publishAt: { lte: new Date() },
      OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
    },
    select: { id: true },
    take: 20,
  });
  for (const item of due) {
    const updated = await prisma.announcement.updateMany({
      where: {
        id: item.id,
        deletedAt: null,
        status: AnnouncementStatus.SCHEDULED,
      },
      data: {
        status: AnnouncementStatus.PUBLISHED,
        publishedAt: new Date(),
      },
    });
    if (updated.count) await notifyAnnouncement(item.id);
  }
}

function serializeAnnouncement(
  announcement: Prisma.AnnouncementGetPayload<{ include: typeof announcementInclude }>,
  userId: string,
  staff: boolean,
) {
  return {
    ...announcement,
    isRead: announcement.reads.some((read) => read.userId === userId),
    readCount: staff ? announcement.reads.length : undefined,
    reads: staff && announcement.requireReadReceipt ? announcement.reads : undefined,
  };
}

export async function listAnnouncements(req: Request, res: Response) {
  await processDueAnnouncements();
  const user = req.user!;
  const teamIds = await contextualTeamIds(user);
  const staff = hasPermission(user.role as Role, Permission.SEND_ANNOUNCEMENTS);
  const announcements = await prisma.announcement.findMany({
    where: {
      deletedAt: null,
      targetTeams: { some: { teamId: { in: teamIds } } },
      ...(staff && req.query.includeDrafts === 'true'
        ? { status: { not: AnnouncementStatus.ARCHIVED } }
        : {
            status: AnnouncementStatus.PUBLISHED,
            AND: [
              { OR: [{ publishAt: null }, { publishAt: { lte: new Date() } }] },
              { OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] },
            ],
          }),
    },
    include: announcementInclude,
    orderBy: [{ priority: 'desc' }, { publishAt: 'desc' }, { createdAt: 'desc' }],
    take: 100,
  });
  return res.json(
    announcements
      .filter(
        (announcement) =>
          staff ||
          (audienceVisible(user.role, announcement.audience) &&
            (announcement.audience !== AnnouncementAudience.INDIVIDUALS ||
              announcement.recipients.some((item) => item.userId === user.id))),
      )
      .map((announcement) =>
        serializeAnnouncement(announcement, user.id, staff),
      ),
  );
}

export async function getAnnouncement(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const staff = hasPermission(user.role as Role, Permission.SEND_ANNOUNCEMENTS);
  const announcement = await prisma.announcement.findFirst({
    where: {
      id: req.params.id,
      deletedAt: null,
      targetTeams: { some: { teamId: { in: teamIds } } },
    },
    include: announcementInclude,
  });
  if (!announcement) return res.status(404).json({ message: 'Mitteilung nicht gefunden.' });
  if (
    !staff &&
    (announcement.status !== AnnouncementStatus.PUBLISHED ||
      (announcement.publishAt != null && announcement.publishAt > new Date()) ||
      (announcement.expiresAt != null && announcement.expiresAt <= new Date()) ||
      !audienceVisible(user.role, announcement.audience) ||
      (announcement.audience === AnnouncementAudience.INDIVIDUALS &&
        !announcement.recipients.some((item) => item.userId === user.id)))
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für diese Mitteilung.' });
  }
  return res.json(serializeAnnouncement(announcement, user.id, staff));
}

async function announcementInput(
  req: Request,
  existing?: { id: string; authorId: string },
) {
  const user = req.user!;
  const accessible = await accessibleTeamIds(user);
  const teamIds: string[] = Array.from(
    new Set<string>(
      (Array.isArray(req.body?.teamIds) ? req.body.teamIds : [user.teamId])
        .map((item: unknown) => text(item, 100))
        .filter((item: string | null): item is string => Boolean(item)),
    ),
  ).filter((id) => accessible.includes(id));
  if (!teamIds.length) throw new Error('NO_TEAM');
  const audience = enumValue(
    AnnouncementAudience,
    req.body?.audience,
    AnnouncementAudience.ALL_MEMBERS,
  );
  const recipientIds: string[] = Array.isArray(req.body?.recipientIds)
    ? req.body.recipientIds
        .map((item: unknown) => text(item, 100))
        .filter((item: string | null): item is string => Boolean(item))
    : [];
  const validRecipients = await usersForAnnouncement(teamIds, audience, recipientIds);
  if (audience === AnnouncementAudience.INDIVIDUALS && !validRecipients.length) {
    throw new Error('NO_RECIPIENT');
  }
  const attachments = (Array.isArray(req.body?.attachments) ? req.body.attachments : [])
    .slice(0, 10)
    .map((item: Record<string, unknown>) => ({
      name: text(item.name, 160),
      url: safeUrl(item.url),
      mimeType: text(item.mimeType, 100),
      sizeBytes:
        Number.isInteger(Number(item.sizeBytes)) && Number(item.sizeBytes) >= 0
          ? Math.min(Number(item.sizeBytes), 25_000_000)
          : null,
    }))
    .filter(
      (item: { name: string | null; url: string | null }) => item.name && item.url,
    ) as {
    name: string;
    url: string;
    mimeType: string | null;
    sizeBytes: number | null;
  }[];
  return {
    teamIds,
    recipientIds: validRecipients,
    attachments,
    data: {
      authorId: existing?.authorId ?? user.id,
      title: text(req.body?.title, 160),
      body: text(req.body?.body, 10_000),
      audience,
      priority: enumValue(
        AnnouncementPriority,
        req.body?.priority,
        AnnouncementPriority.NORMAL,
      ),
      status: enumValue(
        AnnouncementStatus,
        req.body?.status,
        AnnouncementStatus.DRAFT,
      ),
      publishAt: date(req.body?.publishAt),
      expiresAt: date(req.body?.expiresAt),
      requireReadReceipt: req.body?.requireReadReceipt === true,
      pushEnabled: req.body?.pushEnabled !== false,
    },
  };
}

export async function saveAnnouncement(req: Request, res: Response) {
  const user = req.user!;
  const accessible = await accessibleTeamIds(user);
  const existing = req.params.id
    ? await prisma.announcement.findFirst({
        where: {
          id: req.params.id,
          deletedAt: null,
          targetTeams: { some: { teamId: { in: accessible } } },
        },
        select: { id: true, authorId: true, status: true },
      })
    : null;
  if (req.params.id && !existing) {
    return res.status(404).json({ message: 'Mitteilung nicht gefunden.' });
  }
  try {
    const input = await announcementInput(req, existing ?? undefined);
    if (!input.data.title || !input.data.body) {
      return res.status(400).json({ message: 'Titel und Nachricht sind erforderlich.' });
    }
    const title = input.data.title;
    const body = input.data.body;
    if (input.data.expiresAt && input.data.publishAt &&
        input.data.expiresAt <= input.data.publishAt) {
      return res.status(400).json({ message: 'Das Ablaufdatum muss nach der Veröffentlichung liegen.' });
    }
    const shouldPublish =
      input.data.status === AnnouncementStatus.PUBLISHED ||
      (input.data.status === AnnouncementStatus.SCHEDULED &&
        input.data.publishAt &&
        input.data.publishAt <= new Date());
    const announcement = await prisma.$transaction(async (tx) => {
      const saved = existing
        ? await tx.announcement.update({
            where: { id: existing.id },
            data: {
              ...input.data,
              title,
              body,
              status: shouldPublish
                ? AnnouncementStatus.PUBLISHED
                : input.data.status,
              publishAt: shouldPublish
                ? input.data.publishAt ?? new Date()
                : input.data.publishAt,
              publishedAt: shouldPublish ? new Date() : undefined,
            },
          })
        : await tx.announcement.create({
            data: {
              ...input.data,
              title,
              body,
              status: shouldPublish
                ? AnnouncementStatus.PUBLISHED
                : input.data.status,
              publishAt: shouldPublish
                ? input.data.publishAt ?? new Date()
                : input.data.publishAt,
              publishedAt: shouldPublish ? new Date() : null,
            },
          });
      await Promise.all([
        tx.announcementTargetTeam.deleteMany({ where: { announcementId: saved.id } }),
        tx.announcementRecipient.deleteMany({ where: { announcementId: saved.id } }),
        tx.announcementAttachment.deleteMany({ where: { announcementId: saved.id } }),
      ]);
      await tx.announcementTargetTeam.createMany({
        data: input.teamIds.map((teamId) => ({ announcementId: saved.id, teamId })),
      });
      if (input.recipientIds.length) {
        await tx.announcementRecipient.createMany({
          data: input.recipientIds.map((userId) => ({
            announcementId: saved.id,
            userId,
          })),
        });
      }
      if (input.attachments.length) {
        await tx.announcementAttachment.createMany({
          data: input.attachments.map((attachment) => ({
            announcementId: saved.id,
            ...attachment,
          })),
        });
      }
      return saved;
    });
    if (shouldPublish && existing?.status !== AnnouncementStatus.PUBLISHED) {
      await notifyAnnouncement(announcement.id);
    }
    await prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: input.teamIds[0],
        action: existing ? 'ANNOUNCEMENT_UPDATED' : 'ANNOUNCEMENT_CREATED',
        entityType: 'Announcement',
        entityId: announcement.id,
        metadata: {
          status: announcement.status,
          audience: announcement.audience,
          priority: announcement.priority,
        },
      },
    });
    return res.status(existing ? 200 : 201).json(announcement);
  } catch (error) {
    const code = error instanceof Error ? error.message : '';
    if (code === 'NO_TEAM') {
      return res.status(403).json({ message: 'Keine zulässige Mannschaft ausgewählt.' });
    }
    if (code === 'NO_RECIPIENT') {
      return res.status(400).json({ message: 'Mindestens einen gültigen Empfänger auswählen.' });
    }
    throw error;
  }
}

export async function publishAnnouncement(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const announcement = await prisma.announcement.findFirst({
    where: {
      id: req.params.id,
      deletedAt: null,
      targetTeams: { some: { teamId: { in: teamIds } } },
    },
  });
  if (!announcement) return res.status(404).json({ message: 'Mitteilung nicht gefunden.' });
  if (announcement.status === AnnouncementStatus.PUBLISHED) return res.json(announcement);
  const updated = await prisma.announcement.update({
    where: { id: announcement.id },
    data: {
      status: AnnouncementStatus.PUBLISHED,
      publishAt: new Date(),
      publishedAt: new Date(),
    },
  });
  await notifyAnnouncement(updated.id);
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: teamIds[0],
      action: 'ANNOUNCEMENT_PUBLISHED',
      entityType: 'Announcement',
      entityId: updated.id,
    },
  });
  return res.json(updated);
}

export async function archiveAnnouncement(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const announcement = await prisma.announcement.findFirst({
    where: {
      id: req.params.id,
      deletedAt: null,
      targetTeams: { some: { teamId: { in: teamIds } } },
    },
    include: { targetTeams: true },
  });
  if (!announcement) return res.status(404).json({ message: 'Mitteilung nicht gefunden.' });
  if (
    user.role !== Role.SUPER_ADMIN &&
    announcement.authorId !== user.id &&
    !announcement.targetTeams.every((target) => teamIds.includes(target.teamId))
  ) {
    return res.status(403).json({ message: 'Diese Mitteilung darf nicht gelöscht werden.' });
  }
  await prisma.$transaction(async (tx) => {
    await tx.announcement.update({
      where: { id: announcement.id },
      data: {
        status: AnnouncementStatus.ARCHIVED,
        archivedAt: new Date(),
        deletedAt: new Date(),
        deletedById: user.id,
      },
    });
    await tx.notification.deleteMany({
      where: { entityType: 'Announcement', entityId: announcement.id },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: announcement.targetTeams[0]?.teamId ?? user.teamId,
        action: 'ANNOUNCEMENT_SOFT_DELETED',
        entityType: 'Announcement',
        entityId: announcement.id,
        metadata: {
          wasPublished: announcement.status === AnnouncementStatus.PUBLISHED,
        },
      },
    });
  });
  return res.status(204).send();
}

export async function permanentlyDeleteAnnouncement(req: Request, res: Response) {
  const user = req.user!;
  if (!canPermanentlyDeleteAnnouncement(user.role)) {
    return res.status(403).json({
      message: 'Nur die Systemadministration darf Mitteilungen endgültig löschen.',
    });
  }
  const announcement = await prisma.announcement.findUnique({
    where: { id: req.params.id },
    select: {
      id: true,
      title: true,
      targetTeams: { select: { teamId: true }, take: 1 },
    },
  });
  if (!announcement) {
    return res.status(404).json({ message: 'Mitteilung nicht gefunden.' });
  }
  await prisma.$transaction(async (tx) => {
    await tx.notification.deleteMany({
      where: { entityType: 'Announcement', entityId: announcement.id },
    });
    await tx.announcement.delete({ where: { id: announcement.id } });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: announcement.targetTeams[0]?.teamId ?? user.teamId,
        action: 'ANNOUNCEMENT_DELETED',
        entityType: 'Announcement',
        entityId: announcement.id,
        metadata: { title: announcement.title },
      },
    });
  });
  return res.status(204).send();
}

export async function markAnnouncementRead(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const announcement = await prisma.announcement.findFirst({
    where: {
      id: req.params.id,
      deletedAt: null,
      status: AnnouncementStatus.PUBLISHED,
      AND: [
        { OR: [{ publishAt: null }, { publishAt: { lte: new Date() } }] },
        { OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] },
      ],
      targetTeams: { some: { teamId: { in: teamIds } } },
    },
    include: { recipients: true },
  });
  if (
    !announcement ||
    !audienceVisible(user.role, announcement.audience) ||
    (announcement.audience === AnnouncementAudience.INDIVIDUALS &&
      !announcement.recipients.some((item) => item.userId === user.id))
  ) {
    return res.status(404).json({ message: 'Mitteilung nicht gefunden.' });
  }
  const read = await prisma.announcementRead.upsert({
    where: {
      announcementId_userId: { announcementId: announcement.id, userId: user.id },
    },
    update: { readAt: new Date() },
    create: { announcementId: announcement.id, userId: user.id },
  });
  return res.json(read);
}
