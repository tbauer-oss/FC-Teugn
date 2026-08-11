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
import { objectStorage } from '../services/object-storage';
import { clubIdForTeam } from '../services/team-access';
import { Role } from '../types/enums';

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
          recordKind: true,
          source: true,
          consentTextVersion: {
            select: { type: true, version: true, title: true, checksum: true },
          },
        },
      },
      playerConsentEvidence: {
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          action: true,
          templateVersion: true,
          statement: true,
          signatureData: true,
          signerName: true,
          signerRole: true,
          guardianAuthorityConfirmed: true,
          childAssentName: true,
          documentHash: true,
          clientSignedAt: true,
          createdAt: true,
          consent: {
            select: {
              playerId: true,
              type: true,
              status: true,
              grantedAt: true,
              revokedAt: true,
            },
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

  const [
    attendanceReplies,
    auditTrail,
    pushDevices,
    supportRecords,
    carpoolRecords,
    assignedTasks,
    equipmentRecords,
    authoredTickerEvents,
    uploadedFiles,
  ] = await Promise.all([
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
        metadata: true,
        createdAt: true,
      },
    }),
    prisma.pushSubscription.findMany({
      where: { userId },
      select: {
        platform: true,
        endpoint: true,
        deviceName: true,
        isActive: true,
        administrativelyDisabledAt: true,
        lastUsedAt: true,
        createdAt: true,
      },
    }),
    prisma.supportTicket.findMany({
      where: { creatorId: userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        category: true,
        subject: true,
        description: true,
        appArea: true,
        contactRequested: true,
        technicalMetadata: true,
        status: true,
        resolvedAt: true,
        closedAt: true,
        createdAt: true,
        messages: {
          where: { internal: false },
          select: { body: true, authorId: true, createdAt: true },
        },
      },
    }),
    Promise.all([
      prisma.carpoolOffer.findMany({
        where: { driverId: userId },
        select: {
          eventId: true,
          seatsTotal: true,
          departureLocation: true,
          departureAt: true,
          notes: true,
          createdAt: true,
        },
      }),
      prisma.carpoolPassenger.findMany({
        where: { requestedById: userId },
        select: { offerId: true, playerId: true, status: true, createdAt: true },
      }),
      prisma.carpoolNeed.findMany({
        where: { requestedById: userId },
        select: { eventId: true, playerId: true, note: true, status: true, createdAt: true },
      }),
    ]).then(([offers, passengerRequests, needs]) => ({ offers, passengerRequests, needs })),
    prisma.teamTask.findMany({
      where: { OR: [{ assigneeUserId: userId }, { createdById: userId }] },
      select: {
        id: true,
        teamId: true,
        title: true,
        description: true,
        category: true,
        status: true,
        dueAt: true,
        completedAt: true,
        createdAt: true,
      },
    }),
    prisma.equipmentAssignment.findMany({
      where: { OR: [{ assignedToUserId: userId }, { assignedById: userId }] },
      select: {
        equipmentItemId: true,
        assignedToUserId: true,
        assignedToPlayerId: true,
        quantity: true,
        assignedAt: true,
        dueAt: true,
        returnedAt: true,
        conditionOut: true,
        conditionIn: true,
        notes: true,
      },
    }),
    prisma.liveTickerEvent.findMany({
      where: { authorId: userId },
      select: {
        tickerId: true,
        type: true,
        period: true,
        elapsedSeconds: true,
        scorerId: true,
        assistId: true,
        comment: true,
        revokedAt: true,
        createdAt: true,
      },
    }),
    prisma.fileAsset.findMany({
      where: { uploadedById: userId },
      select: {
        id: true,
        kind: true,
        originalName: true,
        contentType: true,
        size: true,
        deletedAt: true,
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
    exportVersion: 2,
    generatedAt: new Date().toISOString(),
    scope:
      'Eigenes Benutzerkonto sowie Daten verknüpfter Kinder, für die eine gesetzliche Vertretung hinterlegt ist.',
    user,
    attendanceReplies,
    auditTrail,
    pushDevices,
    supportRecords,
    carpoolRecords,
    assignedTasks,
    equipmentRecords,
    authoredTickerEvents,
    uploadedFiles,
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

export async function requestDataSubjectRight(req: Request, res: Response) {
  const type = String(req.body.type ?? '').toUpperCase() as DataSubjectRequestType;
  const reason = String(req.body.reason ?? '').trim().slice(0, 2000) || null;
  const allowed: DataSubjectRequestType[] = [
    DataSubjectRequestType.ACCESS,
    DataSubjectRequestType.PORTABILITY,
    DataSubjectRequestType.RECTIFICATION,
    DataSubjectRequestType.RESTRICTION,
    DataSubjectRequestType.OBJECTION,
    DataSubjectRequestType.CONSENT_WITHDRAWAL,
  ];
  if (!allowed.includes(type)) {
    return res.status(400).json({ message: 'Dieses Betroffenenrecht ist nicht verfügbar.' });
  }
  if (!reason && type !== DataSubjectRequestType.ACCESS && type !== DataSubjectRequestType.PORTABILITY) {
    return res.status(400).json({
      message: 'Bitte beschreiben Sie kurz, welche Daten oder Verarbeitung betroffen sind.',
    });
  }
  const existing = await prisma.dataSubjectRequest.findFirst({
    where: { userId: req.user!.id, type, status: { in: openRequestStatuses } },
  });
  if (existing) {
    return res.status(409).json({ message: 'Ein gleichartiger Antrag wird bereits geprüft.' });
  }
  const request = await prisma.$transaction(async (tx) => {
    const created = await tx.dataSubjectRequest.create({
      data: { userId: req.user!.id, type, reason },
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: req.user!.teamId,
        action: `DATA_SUBJECT_${type}_REQUESTED`,
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
  const unrestricted = req.user!.role === Role.SUPER_ADMIN;
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
      ...(!unrestricted && clubId
        ? { user: { team: { ageGroup: { season: { clubId } } } } }
        : {}),
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
      DataSubjectRequestStatus.COMPLETED,
  ];
  if (!reviewStatuses.includes(status)) {
    return res.status(400).json({ message: 'Ungültiger Prüfstatus.' });
  }
  const request = await scopedRequest(req, requestId);
  if (!request) return res.status(404).json({ message: 'Datenschutzantrag nicht gefunden.' });
  if (status === DataSubjectRequestStatus.COMPLETED && request.type === DataSubjectRequestType.ERASURE) {
    return res.status(400).json({
      message: 'Löschanträge müssen über den geschützten Anonymisierungsvorgang abgeschlossen werden.',
    });
  }
  const updated = await prisma.$transaction(async (tx) => {
    const result = await tx.dataSubjectRequest.update({
      where: { id: requestId },
      data: {
        status,
        reviewNote,
        reviewedById: req.user!.id,
        reviewedAt: new Date(),
        completedAt: status === DataSubjectRequestStatus.COMPLETED ? new Date() : null,
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
  if (request.user.role === Role.SUPER_ADMIN) {
    const remainingAdministrators = await prisma.user.count({
      where: {
        role: Role.SUPER_ADMIN,
        status: { notIn: [AccountStatus.ARCHIVED, AccountStatus.REJECTED] },
        id: { not: request.userId },
      },
    });
    if (remainingAdministrators === 0) {
      return res.status(409).json({
        message: 'Das letzte Systemadministrationskonto kann nicht anonymisiert werden.',
      });
    }
  }
  const supportAssets = await prisma.fileAsset.findMany({
    where: {
      supportAttachment: { is: { creatorId: request.userId } },
    },
    select: { id: true, pathname: true },
  });
  const password = await hashPassword(randomBytes(48).toString('base64url'));
  const anonymized = anonymizedUserData(request.userId, password);
  await prisma.$transaction(async (tx) => {
    await tx.refreshToken.updateMany({
      where: { userId: request.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    await tx.pushSubscription.deleteMany({ where: { userId: request.userId } });
    await tx.passwordResetToken.deleteMany({ where: { userId: request.userId } });
    await tx.idempotencyRecord.deleteMany({ where: { userId: request.userId } });
    await tx.notificationPreference.deleteMany({ where: { userId: request.userId } });
    await tx.notification.deleteMany({ where: { userId: request.userId } });
    await tx.registrationRequest.deleteMany({ where: { userId: request.userId } });
    await tx.userContextPreference.deleteMany({ where: { userId: request.userId } });
    await tx.userPermissionOverride.deleteMany({ where: { userId: request.userId } });
    await tx.parentPlayerLink.deleteMany({ where: { parentId: request.userId } });
    await tx.eventParticipant.deleteMany({ where: { userId: request.userId } });
    await tx.announcementRecipient.deleteMany({ where: { userId: request.userId } });
    await tx.announcementRead.deleteMany({ where: { userId: request.userId } });
    await tx.eventReminder.deleteMany({ where: { recipientId: request.userId } });
    await tx.scheduledReminder.deleteMany({ where: { recipientId: request.userId } });
    await tx.carpoolPassenger.deleteMany({ where: { requestedById: request.userId } });
    await tx.carpoolNeed.deleteMany({ where: { requestedById: request.userId } });
    await tx.carpoolOffer.deleteMany({ where: { driverId: request.userId } });
    await tx.matchTickerDelegate.deleteMany({ where: { userId: request.userId } });
    await tx.teamTask.updateMany({
      where: { assigneeUserId: request.userId },
      data: { assigneeUserId: null },
    });
    await tx.equipmentAssignment.updateMany({
      where: { assignedToUserId: request.userId },
      data: { assignedToUserId: null },
    });
    await tx.checklistRunItem.updateMany({
      where: { completedById: request.userId },
      data: { completedById: null },
    });
    await tx.supportTicket.deleteMany({ where: { creatorId: request.userId } });
    if (supportAssets.length > 0) {
      await tx.fileAsset.deleteMany({
        where: { id: { in: supportAssets.map((asset) => asset.id) } },
      });
    }
    await tx.player.updateMany({
      where: { userId: request.userId },
      data: { userId: null },
    });
    await tx.teamMembership.deleteMany({ where: { userId: request.userId } });
    await tx.userConsent.updateMany({
      where: { userId: request.userId, revokedAt: null },
      data: { granted: false, revokedAt: new Date() },
    });
    const consentEvidence = await tx.playerConsentEvidence.findMany({
      where: { signerId: request.userId },
      select: {
        id: true,
        action: true,
        templateVersion: true,
        documentHash: true,
      },
    });
    for (const evidence of consentEvidence) {
      await tx.playerConsentEvidence.update({
        where: { id: evidence.id },
        data: {
          signerName: 'Gelöschtes Konto',
          childAssentName: null,
          signatureData: Prisma.JsonNull,
          statement: {
            anonymized: true,
            action: evidence.action,
            templateVersion: evidence.templateVersion,
            originalDocumentHash: evidence.documentHash,
          },
        },
      });
    }
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
    await tx.dataSubjectRequest.updateMany({
      where: { userId: request.userId, id: { not: request.id } },
      data: { reason: null },
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
  await Promise.allSettled(
    supportAssets.map((asset) => objectStorage.delete(asset.pathname)),
  );
  return res.status(204).send();
}

async function scopedRequest(req: Request, requestId: string) {
  if (req.user!.role === Role.SUPER_ADMIN) {
    return prisma.dataSubjectRequest.findUnique({
      where: { id: requestId },
      include: { user: { select: { teamId: true, role: true } } },
    });
  }
  const clubId = await clubIdForTeam(req.user!.teamId);
  if (!clubId) return null;
  return prisma.dataSubjectRequest.findFirst({
    where: {
      id: requestId,
      user: { team: { ageGroup: { season: { clubId } } } },
    },
    include: { user: { select: { teamId: true, role: true } } },
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
