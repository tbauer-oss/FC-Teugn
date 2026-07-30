import { Request, Response } from 'express';
import {
  HomeAway,
  NotificationCategory,
  PitchConflictRequestStatus,
  Role,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { accessibleTeamIds } from '../services/team-access';
import { notifyUsers } from '../services/notification.service';
import {
  CLUB_MATCH_PITCHES,
  findPitchConflicts,
} from '../services/pitch-conflict.service';

const responseStatuses = new Set<PitchConflictRequestStatus>([
  PitchConflictRequestStatus.APPROVED,
  PitchConflictRequestStatus.DECLINED,
  PitchConflictRequestStatus.CALLBACK_REQUESTED,
]);

const administrativeRoles = new Set<Role>([
  Role.SUPER_ADMIN,
  Role.CLUB_ADMIN,
  Role.YOUTH_DIRECTOR,
]);

function date(value: unknown) {
  if (!value) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function text(value: unknown, maximum = 1000) {
  return typeof value === 'string' && value.trim()
    ? value.trim().slice(0, maximum)
    : null;
}

function durationEnd(
  startAt: Date,
  endAt: Date | null,
  periodCount: unknown,
  periodMinutes: unknown,
) {
  if (endAt && endAt > startAt) return endAt;
  const count = Math.max(1, Math.min(8, Number(periodCount) || 2));
  const minutes = Math.max(1, Math.min(90, Number(periodMinutes) || 30));
  return new Date(startAt.getTime() + count * minutes * 60_000);
}

export async function checkPitchConflicts(req: Request, res: Response) {
  const startAt = date(req.body?.startAt);
  const explicitEnd = date(req.body?.endAt);
  const pitch = text(req.body?.pitch, 160);
  const homeAway = String(req.body?.homeAway ?? 'HOME').toUpperCase();
  if (!startAt || !pitch) {
    return res.status(400).json({ message: 'Beginn und Platz sind erforderlich.' });
  }
  if (homeAway === HomeAway.AWAY) {
    return res.json({ conflicts: [], pitchOptions: CLUB_MATCH_PITCHES });
  }
  const accessible = await accessibleTeamIds(req.user!);
  const requestedTeamIds = Array.isArray(req.body?.teamIds)
    ? req.body.teamIds.map(String).filter((id: string) => accessible.includes(id))
    : [req.user!.teamId];
  if (!requestedTeamIds.length) {
    return res.status(403).json({ message: 'Keine erlaubte Mannschaft ausgewählt.' });
  }
  const endAt = durationEnd(
    startAt,
    explicitEnd,
    req.body?.periodCount,
    req.body?.periodMinutes,
  );
  const conflicts = await findPitchConflicts({
    startAt,
    endAt,
    pitch,
    targetTeamIds: requestedTeamIds,
  });
  return res.json({ conflicts, pitchOptions: CLUB_MATCH_PITCHES });
}

export async function createPitchConflictRequestsForEvent(input: {
  eventId: string;
  requesterId: string;
  message?: string | null;
}) {
  const event = await prisma.event.findUnique({
    where: { id: input.eventId },
    include: {
      targetTeams: true,
      matchDetails: true,
    },
  });
  if (
    !event ||
    event.type !== 'MATCH' ||
    event.homeAway === HomeAway.AWAY
  ) {
    return [];
  }
  const pitch = event.matchDetails?.pitch || event.venue;
  if (!pitch) return [];
  const endAt = durationEnd(
    event.startAt,
    event.endAt,
    event.matchDetails?.periodCount,
    event.matchDetails?.periodMinutes,
  );
  const conflicts = await findPitchConflicts({
    startAt: event.startAt,
    endAt,
    pitch,
    targetTeamIds:
      event.targetTeams.length > 0
        ? event.targetTeams.map((item) => item.teamId)
        : [event.teamId],
  });
  const created = [];
  for (const conflict of conflicts) {
    if (!conflict.headCoach || conflict.headCoach.id === input.requesterId) continue;
    const request = await prisma.pitchConflictRequest.upsert({
      where: {
        eventId_trainingTeamId_trainingScheduleValue: {
          eventId: event.id,
          trainingTeamId: conflict.trainingTeamId,
          trainingScheduleValue: conflict.trainingScheduleValue,
        },
      },
      update: {
        recipientId: conflict.headCoach.id,
        pitch,
        conflictStartAt: event.startAt,
        conflictEndAt: endAt,
        message: input.message,
        status: PitchConflictRequestStatus.PENDING,
        respondedAt: null,
        respondedById: null,
        responseMessage: null,
      },
      create: {
        eventId: event.id,
        trainingTeamId: conflict.trainingTeamId,
        requesterId: input.requesterId,
        recipientId: conflict.headCoach.id,
        pitch,
        trainingScheduleValue: conflict.trainingScheduleValue,
        conflictStartAt: event.startAt,
        conflictEndAt: endAt,
        message: input.message,
      },
    });
    created.push(request);
    await prisma.auditLog.create({
      data: {
        actorId: input.requesterId,
        teamId: conflict.trainingTeamId,
        action: 'PITCH_CONFLICT_REQUEST_CREATED',
        entityType: 'PitchConflictRequest',
        entityId: request.id,
        metadata: {
          eventId: event.id,
          pitch,
          trainingScheduleValue: conflict.trainingScheduleValue,
          recipientId: conflict.headCoach.id,
        },
      },
    });
    await notifyUsers([conflict.headCoach.id], {
      category: NotificationCategory.MATCH,
      title: `Platzfreigabe: ${event.title}`,
      body:
        `${conflict.trainingTeamName} trainiert ${conflict.weekday} ` +
        `${conflict.startLabel}–${conflict.endLabel} Uhr auf ${conflict.pitch}. ` +
        'Bitte freigeben, ablehnen oder um Rückruf bitten.',
      actionUrl: '/trainer/messages',
      entityType: 'PitchConflictRequest',
      entityId: request.id,
    });
  }
  return created;
}

const requestInclude = {
  event: {
    select: {
      id: true,
      title: true,
      startAt: true,
      endAt: true,
      opponent: true,
      venue: true,
      team: { select: { id: true, name: true, shortName: true } },
    },
  },
  trainingTeam: {
    select: {
      id: true,
      name: true,
      shortName: true,
      ageGroup: { select: { code: true } },
    },
  },
  requester: { select: { id: true, name: true, phone: true, email: true } },
  recipient: { select: { id: true, name: true, phone: true, email: true } },
  respondedBy: { select: { id: true, name: true } },
} as const;

export async function listPitchConflictRequests(req: Request, res: Response) {
  const user = req.user!;
  const accessible = await accessibleTeamIds(user);
  const canViewTeamRequests = hasPermission(
    user.role,
    Permission.MANAGE_ORGANIZATION,
  );
  const requests = await prisma.pitchConflictRequest.findMany({
    where: {
      OR: [
        { requesterId: user.id },
        { recipientId: user.id },
        ...(canViewTeamRequests
          ? [{ trainingTeamId: { in: accessible } }]
          : []),
      ],
    },
    include: requestInclude,
    orderBy: [{ status: 'asc' }, { createdAt: 'desc' }],
    take: 100,
  });
  return res.json(
    requests.map((item) => ({
      ...item,
      direction: item.recipientId === user.id ? 'INCOMING' : 'OUTGOING',
      canRespond:
        item.status === PitchConflictRequestStatus.PENDING &&
        (item.recipientId === user.id ||
          administrativeRoles.has(user.role as Role)),
    })),
  );
}

export async function respondToPitchConflictRequest(req: Request, res: Response) {
  const user = req.user!;
  const status = String(req.body?.status ?? '').toUpperCase() as PitchConflictRequestStatus;
  if (!responseStatuses.has(status)) {
    return res.status(400).json({
      message: 'Bitte Freigeben, Ablehnen oder Rückruf anfordern auswählen.',
    });
  }
  const existing = await prisma.pitchConflictRequest.findUnique({
    where: { id: req.params.requestId },
    include: requestInclude,
  });
  if (!existing) return res.status(404).json({ message: 'Anfrage nicht gefunden.' });
  if (
    existing.recipientId !== user.id &&
    !administrativeRoles.has(user.role as Role)
  ) {
    return res.status(403).json({ message: 'Diese Anfrage ist nicht für dich bestimmt.' });
  }
  if (existing.status !== PitchConflictRequestStatus.PENDING) {
    return res.status(409).json({ message: 'Die Anfrage wurde bereits beantwortet.' });
  }
  const responseMessage = text(req.body?.responseMessage, 1000);
  const updated = await prisma.pitchConflictRequest.update({
    where: { id: existing.id },
    data: {
      status,
      responseMessage,
      respondedAt: new Date(),
      respondedById: user.id,
    },
    include: requestInclude,
  });
  const statusText =
    status === PitchConflictRequestStatus.APPROVED
      ? 'freigegeben'
      : status === PitchConflictRequestStatus.DECLINED
        ? 'abgelehnt'
        : 'mit Rückrufwunsch beantwortet';
  const callback =
    status === PitchConflictRequestStatus.CALLBACK_REQUESTED &&
    existing.recipient.phone
      ? ` Rückruf unter ${existing.recipient.phone}.`
      : '';
  await notifyUsers([existing.requesterId], {
    category: NotificationCategory.MATCH,
    title: `Platzanfrage ${statusText}`,
    body: `${existing.recipient.name} hat die Anfrage für ${existing.event.title} ${statusText}.${callback}`,
    actionUrl: '/trainer/messages',
    entityType: 'PitchConflictRequest',
    entityId: existing.id,
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: existing.trainingTeamId,
      action: 'PITCH_CONFLICT_REQUEST_RESPONDED',
      entityType: 'PitchConflictRequest',
      entityId: existing.id,
      metadata: { status, responseMessage },
    },
  });
  return res.json({
    ...updated,
    direction: updated.recipientId === user.id ? 'INCOMING' : 'OUTGOING',
    canRespond: false,
  });
}
