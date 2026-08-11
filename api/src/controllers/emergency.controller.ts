import { Request, Response } from 'express';
import {
  AttendanceStatus,
  ConsentStatus,
  ConsentType,
  Prisma,
  Role as PrismaRole,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { comparePassword } from '../lib/password';
import {
  signEmergencyAccessToken,
  verifyEmergencyAccessToken,
} from '../lib/jwt';
import { hasPermission, Permission } from '../security/permissions';
import { Role } from '../types/enums';
import { accessibleTeamIds } from '../services/team-access';
import {
  ConsentSnapshot,
  hasActiveConsent,
  medicalProfileForConsent,
} from '../services/consent-policy';
import { mediaAssetUrl } from '../services/media-access';

const EMERGENCY_ACCESS_MS = 5 * 60 * 1000;

function eventScope(teamIds: string[]): Prisma.EventWhereInput {
  return {
    OR: [
      { teamId: { in: teamIds } },
      { targetTeams: { some: { teamId: { in: teamIds } } } },
    ],
  };
}

export function selectPresentAttendance<
  T extends {
    status: AttendanceStatus;
    actualAttendance: AttendanceStatus | null;
  },
>(attendance: T[]) {
  const actualWasRecorded = attendance.some(
    (item) =>
      item.actualAttendance !== null &&
      item.actualAttendance !== AttendanceStatus.UNKNOWN,
  );
  return attendance.filter((item) =>
    actualWasRecorded
      ? item.actualAttendance === AttendanceStatus.YES
      : item.status === AttendanceStatus.YES,
  );
}

async function findAccessibleEvent(req: Request) {
  const teamIds = await accessibleTeamIds(req.user!);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    select: {
      id: true,
      teamId: true,
      title: true,
      startAt: true,
      endAt: true,
      meetingAt: true,
      location: true,
      address: true,
      targetTeams: { select: { teamId: true } },
    },
  });
  if (!event) return null;
  const targetIds = event.targetTeams.length
    ? event.targetTeams.map((target) => target.teamId)
    : [event.teamId];
  return targetIds.every((teamId) => teamIds.includes(teamId)) ? event : null;
}

async function audit(
  req: Request,
  action: string,
  event: { id: string; teamId: string },
  metadata: Prisma.InputJsonValue,
) {
  await prisma.auditLog.create({
    data: {
      actorId: req.user!.id,
      teamId: event.teamId,
      action,
      entityType: 'EventEmergencyView',
      entityId: event.id,
      metadata,
    },
  });
}

export async function requestEmergencyAccess(req: Request, res: Response) {
  const password =
    typeof req.body?.password === 'string' ? req.body.password : '';
  if (!password || password.length > 200) {
    return res.status(400).json({ message: 'Passwort ist erforderlich.' });
  }
  const event = await findAccessibleEvent(req);
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });

  const user = await prisma.user.findUnique({
    where: { id: req.user!.id },
    select: { password: true },
  });
  const passwordMatches = user
    ? await comparePassword(password, user.password)
    : false;
  if (!passwordMatches) {
    await audit(req, 'EMERGENCY_ACCESS_DENIED', event, {
      reason: 'PASSWORD_MISMATCH',
      ipAddress: req.ip,
    });
    return res.status(401).json({
      message: 'Erneute Anmeldung fehlgeschlagen.',
    });
  }

  const expiresAt = new Date(Date.now() + EMERGENCY_ACCESS_MS);
  const token = signEmergencyAccessToken({
    userId: req.user!.id,
    eventId: event.id,
  });
  await audit(req, 'EMERGENCY_ACCESS_GRANTED', event, {
    expiresAt: expiresAt.toISOString(),
    ipAddress: req.ip,
  });
  return res.json({ token, expiresAt: expiresAt.toISOString() });
}

export async function getEmergencyView(req: Request, res: Response) {
  const token = req.get('X-Emergency-Access-Token');
  if (!token) {
    return res.status(401).json({
      message: 'Für die Notfallansicht ist eine erneute Anmeldung erforderlich.',
    });
  }
  let claims;
  try {
    claims = verifyEmergencyAccessToken(token);
  } catch {
    return res.status(401).json({
      message: 'Der Notfallzugriff ist abgelaufen. Bitte erneut bestätigen.',
    });
  }
  if (claims.userId !== req.user!.id || claims.eventId !== req.params.id) {
    return res.status(403).json({
      message: 'Der Notfallzugriff gilt nicht für diesen Termin.',
    });
  }

  const teamIds = await accessibleTeamIds(req.user!);
  const event = await prisma.event.findFirst({
    where: { id: req.params.id, ...eventScope(teamIds) },
    select: {
      id: true,
      teamId: true,
      title: true,
      startAt: true,
      endAt: true,
      meetingAt: true,
      location: true,
      address: true,
      targetTeams: { select: { teamId: true } },
      attendance: {
        orderBy: { player: { lastName: 'asc' } },
        select: {
          status: true,
          actualAttendance: true,
          player: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              preferredName: true,
              photoUrl: true,
              photoAsset: { select: { id: true, deletedAt: true } },
              consents: {
                where: {
                  type: {
                    in: [ConsentType.PHOTO, ConsentType.MEDICAL_DATA] as ConsentType[],
                  },
                },
                select: {
                  type: true,
                  status: true,
                  expiresAt: true,
                  evidence: {
                    where: { action: ConsentStatus.GRANTED },
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                    select: { action: true, statement: true, createdAt: true },
                  },
                },
              },
              parentLinks: {
                orderBy: { createdAt: 'asc' },
                select: {
                  relationship: true,
                  isLegalGuardian: true,
                  canPickup: true,
                  parent: {
                    select: { id: true, name: true, phone: true },
                  },
                },
              },
              emergencyContacts: {
                orderBy: [{ priority: 'asc' }, { name: 'asc' }],
                select: {
                  id: true,
                  name: true,
                  relationship: true,
                  phone: true,
                  priority: true,
                  isAuthorizedPickup: true,
                },
              },
              medicalProfile: {
                select: {
                  allergies: true,
                  medications: true,
                  conditions: true,
                  physicianName: true,
                  physicianPhone: true,
                  emergencyNotes: true,
                },
              },
            },
          },
        },
      },
    },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  const targetIds = event.targetTeams.length
    ? event.targetTeams.map((target) => target.teamId)
    : [event.teamId];
  if (!targetIds.every((teamId) => teamIds.includes(teamId))) {
    return res.status(403).json({
      message: 'Keine Berechtigung für die vollständige Termingruppe.',
    });
  }

  const present = selectPresentAttendance(event.attendance);
  await audit(req, 'EMERGENCY_VIEW_OPENED', event, {
    playerCount: present.length,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? null,
  });
  return res.json({
    event: {
      id: event.id,
      title: event.title,
      startAt: event.startAt,
      endAt: event.endAt,
      meetingAt: event.meetingAt,
      location: event.location,
      address: event.address,
    },
    generatedAt: new Date(),
    presenceSource: event.attendance.some(
      (item) =>
        item.actualAttendance !== null &&
        item.actualAttendance !== AttendanceStatus.UNKNOWN,
    )
      ? 'ACTUAL_ATTENDANCE'
      : 'CONFIRMED_ATTENDANCE',
    players: present.map(({ player }) => ({
      id: player.id,
      firstName: player.firstName,
      lastName: player.lastName,
      preferredName: player.preferredName,
      photoUrl: hasActiveConsent(
        player.consents as ConsentSnapshot[],
        ConsentType.PHOTO,
        'APP_INTERNAL',
      )
        ? player.photoAsset && player.photoAsset.deletedAt === null
          ? mediaAssetUrl(player.photoAsset.id, '5m')
          : player.photoUrl
        : null,
      guardians: player.parentLinks.map((link) => ({
        id: link.parent.id,
        name: link.parent.name,
        phone: link.parent.phone,
        relationship: link.relationship,
        isLegalGuardian: link.isLegalGuardian,
        canPickup: link.canPickup,
      })),
      emergencyContacts: player.emergencyContacts,
      medical: medicalProfileForConsent(
        player.medicalProfile,
        player.consents as ConsentSnapshot[],
        true,
      ),
    })),
  });
}
