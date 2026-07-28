import { randomBytes } from 'crypto';
import { Request, Response } from 'express';
import {
  AccountStatus,
  DataSubjectRequestStatus,
  DataSubjectRequestType,
  Prisma,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { hashPassword } from '../lib/password';
import { clubIdForTeam } from '../services/team-access';

const openRequestStatuses = [
  DataSubjectRequestStatus.RECEIVED,
  DataSubjectRequestStatus.IN_REVIEW,
];

export async function exportPersonalData(req: Request, res: Response) {
  const userId = req.user!.id;
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      email: true,
      name: true,
      firstName: true,
      lastName: true,
      phone: true,
      role: true,
      status: true,
      createdAt: true,
      updatedAt: true,
      memberships: {
        select: {
          role: true,
          status: true,
          createdAt: true,
          team: {
            select: {
              id: true,
              name: true,
              ageGroup: { select: { name: true, code: true } },
            },
          },
        },
      },
      consents: {
        select: {
          granted: true,
          grantedAt: true,
          revokedAt: true,
          source: true,
          consentTextVersion: {
            select: { type: true, version: true, title: true, checksum: true },
          },
        },
      },
      registrationRequest: {
        include: {
          requestedTeams: {
            select: { team: { select: { id: true, name: true } } },
          },
          history: {
            select: {
              fromStatus: true,
              toStatus: true,
              fromReviewStatus: true,
              toReviewStatus: true,
              note: true,
              createdAt: true,
            },
          },
        },
      },
      notificationPreferences: true,
      notifications: {
        orderBy: { createdAt: 'desc' },
        select: {
          category: true,
          title: true,
          body: true,
          readAt: true,
          createdAt: true,
        },
      },
      parentLinks: {
        where: { isLegalGuardian: true },
        select: {
          relationship: true,
          isLegalGuardian: true,
          canPickup: true,
          receivesCommunication: true,
          player: {
            include: {
              medicalProfile: true,
              emergencyContacts: true,
              consents: true,
              documents: {
                select: {
                  type: true,
                  title: true,
                  version: true,
                  status: true,
                  validFrom: true,
                  validUntil: true,
                  createdAt: true,
                },
              },
            },
          },
        },
      },
      playerProfile: {
        include: {
          medicalProfile: true,
          emergencyContacts: true,
          consents: true,
          documents: {
            select: {
              type: true,
              title: true,
              version: true,
              status: true,
              validFrom: true,
              validUntil: true,
              createdAt: true,
            },
          },
        },
      },
      dataSubjectRequests: {
        select: {
          id: true,
          type: true,
          status: true,
          reason: true,
          reviewNote: true,
          createdAt: true,
          reviewedAt: true,
          completedAt: true,
        },
      },
    },
  });
  if (!user) return res.status(404).json({ message: 'Benutzerkonto nicht gefunden.' });

  const [attendanceReplies, auditTrail] = await Promise.all([
    prisma.attendance.findMany({
      where: { respondedById: userId },
      select: {
        eventId: true,
        playerId: true,
        status: true,
        reason: true,
        respondedAt: true,
      },
    }),
    prisma.auditLog.findMany({
      where: { actorId: userId },
      orderBy: { createdAt: 'desc' },
      select: {
        action: true,
        entityType: true,
        entityId: true,
        createdAt: true,
      },
    }),
  ]);
  await prisma.auditLog.create({
    data: {
      actorId: userId,
      teamId: req.user!.teamId,
      action: 'PERSONAL_DATA_EXPORTED',
      entityType: 'User',
      entityId: userId,
    },
  });
  res.setHeader('Content-Disposition', `attachment; filename="fc-teugn-daten-${userId}.json"`);
  return res.json({
    exportVersion: 1,
    generatedAt: new Date().toISOString(),
    scope:
      'Eigenes Benutzerkonto sowie Daten verknüpfter Kinder, für die eine gesetzliche Vertretung hinterlegt ist.',
    user,
    attendanceReplies,
    auditTrail,
  });
}

export async function listOwnPrivacyRequests(req: Request, res: Response) {
  const requests = await prisma.dataSubjectRequest.findMany({
    where: { userId: req.user!.id },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      type: true,
      status: true,
      reason: true,
      reviewNote: true,
      createdAt: true,
      reviewedAt: true,
      completedAt: true,
    },
  });
  return res.json(requests);
}

export async function requestErasure(req: Request, res: Response) {
  const confirmation = String(req.body.confirmation ?? '');
  const reason = String(req.body.reason ?? '').trim().slice(0, 1000) || null;
  if (confirmation !== 'KONTO LÖSCHEN') {
    return res.status(400).json({
      message: 'Bitte die Sicherheitsbestätigung „KONTO LÖSCHEN“ exakt eingeben.',
    });
  }
  const existing = await prisma.dataSubjectRequest.findFirst({
    where: {
      userId: req.user!.id,
      type: DataSubjectRequestType.ERASURE,
      status: { in: openRequestStatuses },
    },
  });
  if (existing) {
    return res.status(409).json({ message: 'Ein Löschantrag wird bereits geprüft.' });
  }
  const request = await prisma.$transaction(async (tx) => {
    const created = await tx.dataSubjectRequest.create({
      data: {
        userId: req.user!.id,
        type: DataSubjectRequestType.ERASURE,
        reason,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: 'ERASURE_REQUESTED',
        entityType: 'DataSubjectRequest',
        entityId: created.id,
      },
    });
    return created;
  });
  return res.status(201).json(request);
}

export async function listPrivacyRequests(req: Request, res: Response) {
  const clubId = await clubIdForTeam(req.user!.teamId);
  const status =
    typeof req.query.status === 'string' &&
    Object.values(DataSubjectRequestStatus).includes(
      req.query.status as DataSubjectRequestStatus,
    )
      ? (req.query.status as DataSubjectRequestStatus)
      : undefined;
  const requests = await prisma.dataSubjectRequest.findMany({
    where: {
      ...(status ? { status } : {}),
      ...(clubId ? { user: { team: { ageGroup: { season: { clubId } } } } } : {}),
    },
    orderBy: { createdAt: 'asc' },
    include: {
      user: { select: { id: true, name: true, email: true, status: true } },
      reviewedBy: { select: { id: true, name: true } },
    },
  });
  return res.json(requests);
}

export async function reviewPrivacyRequest(req: Request, res: Response) {
  const requestId = req.params.id;
  const status = req.body.status as DataSubjectRequestStatus;
  const reviewNote = String(req.body.reviewNote ?? '').trim().slice(0, 1500) || null;
  const reviewStatuses: DataSubjectRequestStatus[] = [
      DataSubjectRequestStatus.IN_REVIEW,
      DataSubjectRequestStatus.REJECTED,
  ];
  if (!reviewStatuses.includes(status)) {
    return res.status(400).json({ message: 'Ungültiger Prüfstatus.' });
  }
  const request = await scopedRequest(req, requestId);
  if (!request) return res.status(404).json({ message: 'Datenschutzantrag nicht gefunden.' });
  const updated = await prisma.$transaction(async (tx) => {
    const result = await tx.dataSubjectRequest.update({
      where: { id: requestId },
      data: {
        status,
        reviewNote,
        reviewedById: req.user!.id,
        reviewedAt: new Date(),
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: request.user.teamId,
        action: `DATA_SUBJECT_REQUEST_${status}`,
        entityType: 'DataSubjectRequest',
        entityId: requestId,
      },
    });
    return result;
  });
  return res.json(updated);
}

export async function completeErasure(req: Request, res: Response) {
  const request = await scopedRequest(req, req.params.id);
  if (!request || request.type !== DataSubjectRequestType.ERASURE) {
    return res.status(404).json({ message: 'Löschantrag nicht gefunden.' });
  }
  if (request.status === DataSubjectRequestStatus.COMPLETED) {
    return res.status(409).json({ message: 'Der Antrag wurde bereits abgeschlossen.' });
  }
  const password = await hashPassword(randomBytes(48).toString('base64url'));
  const anonymized = anonymizedUserData(request.userId, password);
  await prisma.$transaction(async (tx) => {
    await tx.refreshToken.updateMany({
      where: { userId: request.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    await tx.pushSubscription.deleteMany({ where: { userId: request.userId } });
    await tx.notificationPreference.deleteMany({ where: { userId: request.userId } });
    await tx.notification.deleteMany({ where: { userId: request.userId } });
    await tx.registrationRequest.deleteMany({ where: { userId: request.userId } });
    await tx.parentPlayerLink.deleteMany({ where: { parentId: request.userId } });
    await tx.player.updateMany({
      where: { userId: request.userId },
      data: { userId: null },
    });
    await tx.teamMembership.deleteMany({ where: { userId: request.userId } });
    await tx.userConsent.updateMany({
      where: { userId: request.userId, revokedAt: null },
      data: { granted: false, revokedAt: new Date() },
    });
    await tx.fileAsset.updateMany({
      where: { uploadedById: request.userId },
      data: { originalName: 'anonymisiert' },
    });
    await tx.user.update({ where: { id: request.userId }, data: anonymized });
    await tx.dataSubjectRequest.update({
      where: { id: request.id },
      data: {
        status: DataSubjectRequestStatus.COMPLETED,
        reviewNote: String(req.body.reviewNote ?? '').trim().slice(0, 1500) || request.reviewNote,
        reviewedById: req.user!.id,
        reviewedAt: new Date(),
        completedAt: new Date(),
        reason: null,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: request.user.teamId,
        action: 'USER_ANONYMIZED',
        entityType: 'User',
        entityId: request.userId,
        metadata: { requestId: request.id },
      },
    });
  });
  return res.status(204).send();
}

async function scopedRequest(req: Request, requestId: string) {
  const clubId = await clubIdForTeam(req.user!.teamId);
  if (!clubId) return null;
  return prisma.dataSubjectRequest.findFirst({
    where: {
      id: requestId,
      user: { team: { ageGroup: { season: { clubId } } } },
    },
    include: { user: { select: { teamId: true } } },
  });
}

export function anonymizedUserData(userId: string, password: string): Prisma.UserUpdateInput {
  return {
    email: `deleted+${userId}@anonymized.invalid`,
    password,
    name: 'Gelöschtes Konto',
    firstName: null,
    lastName: null,
    phone: null,
    calendarToken: null,
    status: AccountStatus.ARCHIVED,
  };
}
