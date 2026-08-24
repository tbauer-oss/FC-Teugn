import { Request, Response } from 'express';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { prisma } from '../lib/prisma';
import { hashPassword, comparePassword } from '../lib/password';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../lib/jwt';
import { AccountStatus, Role } from '../types/enums';
import {
  ConsentRecordKind,
  ConsentDocumentType,
  GuardianRelationship,
} from '@prisma/client';
import { notifyPendingRegistrationAdministrators } from '../services/registration-notification.service';
import { isRecentRefreshRotation } from '../lib/session-refresh';
import { sendPasswordResetEmail } from '../services/password-reset-email.service';

const refreshLifetimeMs = 30 * 24 * 60 * 60 * 1000;
const biometricCredentialLifetimeMs = 180 * 24 * 60 * 60 * 1000;

async function familyLinks(userId: string) {
  return prisma.parentPlayerLink.findMany({
    where: { parentId: userId },
    orderBy: [{ player: { firstName: 'asc' } }, { player: { lastName: 'asc' } }],
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          teamId: true,
          team: {
            select: {
              id: true,
              name: true,
              ageGroup: { select: { code: true } },
            },
          },
        },
      },
    },
  });
}

function tokenHash(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

function accessTokenFor(user: {
  id: string;
  role: Role;
  status: AccountStatus;
  teamId: string;
}) {
  return signAccessToken({
    id: user.id,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  });
}

async function issueSession(
  user: { id: string; role: Role; status: AccountStatus; teamId: string },
  req: Request,
  familyId: string = randomUUID(),
) {
  const sessionId = randomUUID();
  const refreshToken = signRefreshToken({
    sessionId,
    userId: user.id,
    familyId,
  });
  await prisma.refreshToken.create({
    data: {
      id: sessionId,
      userId: user.id,
      familyId,
      tokenHash: tokenHash(refreshToken),
      expiresAt: new Date(Date.now() + refreshLifetimeMs),
      userAgent: req.get('user-agent')?.slice(0, 500) ?? null,
      ipAddress: req.ip?.slice(0, 64) ?? null,
    },
  });
  return { accessToken: accessTokenFor(user), refreshToken };
}

async function resolveTeamId(teamName?: string, teamId?: string) {
  if (teamId) {
    const selected = await prisma.team.findFirst({
      where: { id: teamId, isActive: true },
    });
    if (selected) return selected.id;
  }

  const name = teamName?.trim() || 'FC Teugn';
  const existing = await prisma.team.findFirst({
    where: { name: { equals: name, mode: 'insensitive' }, isActive: true },
  });
  if (existing) return existing.id;
  const fallback = await prisma.team.findFirst({
    where: { isActive: true, ageGroup: { season: { isActive: true } } },
    orderBy: { createdAt: 'asc' },
  });
  if (!fallback) {
    throw new Error('No active team configured');
  }
  return fallback.id;
}

export async function register(req: Request, res: Response) {
  const {
    email,
    password,
    name,
    firstName,
    lastName,
    phone,
    role,
    teamName,
    teamId,
    teamIds,
    childName,
    relationship,
    privacyAccepted,
    termsAccepted,
    pushOptIn = false,
    privacyTextVersionId,
    termsTextVersionId,
    pushTextVersionId,
  } = req.body as {
    email?: string;
    password?: string;
    name?: string;
    firstName?: string;
    lastName?: string;
    phone?: string;
    role?: string;
    teamName?: string;
    teamId?: string;
    teamIds?: string[];
    childName?: string;
    relationship?: GuardianRelationship;
    privacyAccepted?: boolean;
    termsAccepted?: boolean;
    pushOptIn?: boolean;
    privacyTextVersionId?: string;
    termsTextVersionId?: string;
    pushTextVersionId?: string;
  };
  const resolvedFirstName = firstName?.trim() || name?.trim().split(/\s+/)[0] || '';
  const resolvedLastName =
    lastName?.trim() || name?.trim().split(/\s+/).slice(1).join(' ') || '';
  const normalizedEmail = email?.trim().toLowerCase();
  if (!normalizedEmail || !password || !resolvedFirstName || !resolvedLastName) {
    return res.status(400).json({ message: 'Vorname, Nachname, E-Mail und Passwort sind erforderlich.' });
  }
  if (password.length < 10) {
    return res.status(400).json({ message: 'Das Passwort muss mindestens 10 Zeichen lang sein.' });
  }
  if (!privacyAccepted || !termsAccepted) {
    return res.status(400).json({
      message: 'Datenschutzinformation und Nutzungsbedingungen müssen bestätigt werden.',
    });
  }

  const existing = await prisma.user.findUnique({ where: { email: normalizedEmail } });
  if (existing) {
    return res.status(409).json({ message: 'E-Mail bereits vergeben' });
  }

  const normalizedRole =
    role === Role.COACH ||
    role === Role.TRAINER ||
    role === Role.TRAINER_ADMIN ||
    role === 'TRAINER'
      ? Role.COACH
      : role === Role.ASSISTANT_COACH
        ? Role.ASSISTANT_COACH
        : role === Role.TEAM_MANAGER
          ? Role.TEAM_MANAGER
          : role === Role.PLAYER
            ? Role.PLAYER
            : Role.PARENT;

  const requestedTeamIds =
    Array.isArray(teamIds) && teamIds.length > 0
      ? [...new Set(teamIds.filter((id): id is string => typeof id === 'string' && id.length > 0))]
      : [await resolveTeamId(teamName, teamId)];
  const selectedTeams = await prisma.team.findMany({
    where: {
      id: { in: requestedTeamIds },
      isActive: true,
      ageGroup: { season: { isActive: true } },
    },
    include: { ageGroup: { include: { season: true } } },
  });
  if (selectedTeams.length !== requestedTeamIds.length) {
    return res.status(400).json({ message: 'Mindestens eine gewählte Mannschaft ist nicht verfügbar.' });
  }
  const clubIds = new Set(selectedTeams.map((team) => team.ageGroup.season.clubId));
  if (clubIds.size !== 1) {
    return res.status(400).json({ message: 'Alle Mannschaften müssen zum selben Verein gehören.' });
  }
  if (
    (normalizedRole === Role.COACH || normalizedRole === Role.ASSISTANT_COACH) &&
    new Set(selectedTeams.map((team) => team.ageGroupId)).size !== 1
  ) {
    return res.status(400).json({
      message: 'Trainer und Co-Trainer dürfen nur Mannschaften einer Jugend auswählen.',
    });
  }
  const resolvedTeam = selectedTeams.find((team) => team.id === requestedTeamIds[0])!;
  const consentVersions = await prisma.consentTextVersion.findMany({
    where: {
      id: {
        in: [privacyTextVersionId, termsTextVersionId, pushTextVersionId].filter(
          (id): id is string => Boolean(id),
        ),
      },
      isActive: true,
    },
  });
  const privacyVersion = consentVersions.find(
    (version) =>
      version.id === privacyTextVersionId &&
      version.type === ConsentDocumentType.PRIVACY_POLICY,
  );
  const termsVersion = consentVersions.find(
    (version) =>
      version.id === termsTextVersionId &&
      version.type === ConsentDocumentType.TERMS_OF_USE,
  );
  const pushVersion = consentVersions.find(
    (version) =>
      version.id === pushTextVersionId &&
      version.type === ConsentDocumentType.PUSH_NOTIFICATIONS,
  );
  if (!privacyVersion || !termsVersion || (pushOptIn && !pushVersion)) {
    return res.status(400).json({
      message: 'Die verwendeten Einwilligungstexte sind nicht mehr aktuell. Bitte Seite neu laden.',
    });
  }
  if (normalizedRole === Role.PARENT && !childName?.trim()) {
    return res.status(400).json({ message: 'Bitte den Namen des Kindes angeben.' });
  }
  const isFirstClubUser =
    (await prisma.user.count({
      where: {
        team: {
          ageGroup: { season: { clubId: resolvedTeam.ageGroup.season.clubId } },
        },
      },
    })) === 0;
  const hashed = await hashPassword(password);
  const user = await prisma.$transaction(async (tx) => {
    const created = await tx.user.create({
      data: {
        email: normalizedEmail,
        password: hashed,
        name: `${resolvedFirstName} ${resolvedLastName}`.trim(),
        firstName: resolvedFirstName,
        lastName: resolvedLastName,
        phone: phone?.trim() || null,
        role: isFirstClubUser ? Role.CLUB_ADMIN : normalizedRole,
        status: isFirstClubUser ? AccountStatus.APPROVED : AccountStatus.PENDING,
        teamId: resolvedTeam.id,
      },
    });
    await tx.teamMembership.createMany({
      data: selectedTeams.map((team) => ({
        userId: created.id,
        teamId: team.id,
        role: created.role,
        status: created.status,
      })),
    });
    const now = new Date();
    const request = await tx.registrationRequest.create({
      data: {
        userId: created.id,
        requestedRole: normalizedRole,
        childName: childName?.trim() || null,
        relationship:
          normalizedRole === Role.PARENT &&
          relationship &&
          Object.values(GuardianRelationship).includes(relationship)
            ? relationship
            : normalizedRole === Role.PARENT
              ? GuardianRelationship.GUARDIAN
              : null,
        reviewStatus: isFirstClubUser ? 'COMPLETED' : 'NEW',
        reviewedById: isFirstClubUser ? created.id : null,
        reviewedAt: isFirstClubUser ? now : null,
        pushOptIn,
        privacyAcceptedAt: now,
        termsAcceptedAt: now,
        requestedTeams: {
          create: selectedTeams.map((team) => ({ teamId: team.id })),
        },
      },
    });
    await tx.userConsent.createMany({
      data: [
        {
          userId: created.id,
          consentTextVersionId: privacyVersion.id,
          granted: true,
          recordKind: ConsentRecordKind.ACKNOWLEDGEMENT,
          source: 'REGISTRATION_NOTICE_ACKNOWLEDGEMENT',
        },
        {
          userId: created.id,
          consentTextVersionId: termsVersion.id,
          granted: true,
          recordKind: ConsentRecordKind.AGREEMENT,
          source: 'REGISTRATION_TERMS_AGREEMENT',
        },
        ...(pushVersion
          ? [
              {
                userId: created.id,
                consentTextVersionId: pushVersion.id,
                granted: pushOptIn,
                recordKind: ConsentRecordKind.CONSENT,
                source: 'REGISTRATION_OPTIONAL_CONSENT',
              },
            ]
          : []),
      ],
    });
    await tx.registrationHistory.create({
      data: {
        registrationRequestId: request.id,
        actorId: isFirstClubUser ? created.id : null,
        toStatus: created.status,
        toReviewStatus: request.reviewStatus,
        note: isFirstClubUser
          ? 'Erster Vereinsaccount automatisch als Vereinsadministration freigegeben.'
          : 'Registrierung eingegangen.',
        metadata: {
          requestedRole: normalizedRole,
          requestedTeamIds,
          childName: childName?.trim() || null,
        },
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: created.id,
        teamId: resolvedTeam.id,
        action: 'USER_REGISTERED',
        entityType: 'User',
        entityId: created.id,
        metadata: {
          requestedRole: normalizedRole,
          requestedTeamIds,
          consentVersionIds: [
            privacyVersion.id,
            termsVersion.id,
            ...(pushVersion ? [pushVersion.id] : []),
          ],
        },
      },
    });
    return created;
  });

  const tokens = await issueSession(user, req);
  const parentLinks = await familyLinks(user.id);
  const registrationRequest = await prisma.registrationRequest.findUnique({
    where: { userId: user.id },
    select: {
      id: true,
      requestedRole: true,
      childName: true,
      relationship: true,
      reviewStatus: true,
      adminNote: true,
      applicantMessage: true,
      pushOptIn: true,
    },
  });

  if (user.status === AccountStatus.PENDING && registrationRequest) {
    await notifyPendingRegistrationAdministrators({
      registrationRequestId: registrationRequest.id,
      applicantName: user.name,
    }).catch((error) => {
      console.error(
        'Systemadministration konnte nicht über die Registrierung informiert werden.',
        error,
      );
    });
  }

  return res.status(201).json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      firstName: user.firstName,
      lastName: user.lastName,
      phone: user.phone,
      role: user.role,
      status: user.status,
      teamId: user.teamId,
      parentLinks,
      registrationRequest,
    },
    ...tokens,
  });
}

export async function activeConsentTexts(_req: Request, res: Response) {
  const versions = await prisma.consentTextVersion.findMany({
    where: { isActive: true },
    orderBy: [{ type: 'asc' }, { version: 'desc' }],
    select: {
      id: true,
      type: true,
      version: true,
      title: true,
      content: true,
      publishedAt: true,
    },
  });
  const latestByType = new Map<string, (typeof versions)[number]>();
  for (const version of versions) {
    if (!latestByType.has(version.type)) latestByType.set(version.type, version);
  }
  return res.json([...latestByType.values()]);
}

export async function login(req: Request, res: Response) {
  const { email, password } = req.body;

  const user = await prisma.user.findUnique({
    where: { email: email?.trim().toLowerCase() },
    include: {
      registrationRequest: {
        select: {
          id: true,
          requestedRole: true,
          childName: true,
          relationship: true,
          reviewStatus: true,
          adminNote: true,
          applicantMessage: true,
          pushOptIn: true,
        },
      },
    },
  });
  if (!user) {
    return res.status(400).json({ message: 'Ungültige Zugangsdaten' });
  }

  const ok = await comparePassword(password, user.password);
  if (!ok) {
    await prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: 'LOGIN_REJECTED_INVALID_PASSWORD',
        entityType: 'User',
        entityId: user.id,
        metadata: {
          userAgent: req.get('user-agent')?.slice(0, 240) ?? null,
        },
      },
    }).catch(() => undefined);
    return res.status(400).json({ message: 'Ungültige Zugangsdaten' });
  }

  if (
    user.status === AccountStatus.BLOCKED ||
    user.status === AccountStatus.REJECTED ||
    user.status === AccountStatus.ARCHIVED
  ) {
    await prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: 'LOGIN_REJECTED_ACCOUNT_STATUS',
        entityType: 'User',
        entityId: user.id,
        metadata: { status: user.status },
      },
    }).catch(() => undefined);
    return res.status(403).json({
      code: 'ACCOUNT_INACTIVE',
      accountStatus: user.status,
      message: user.status === AccountStatus.BLOCKED
        ? 'Dieser Account ist gesperrt. Eine Passwortänderung hebt die Sperre nicht auf. Bitte wende dich an die Systemadministration.'
        : 'Dieser Account ist nicht aktiv. Eine Passwortänderung aktiviert ihn nicht. Bitte wende dich an die Systemadministration.',
    });
  }

  const tokens = await issueSession(user, req);
  const parentLinks = await familyLinks(user.id);

  return res.json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      role: user.role,
      status: user.status,
      teamId: user.teamId,
      parentLinks,
      registrationRequest: user.registrationRequest,
    },
    ...tokens,
  });
}

export async function enrollBiometricLogin(req: Request, res: Response) {
  const actor = req.user!;
  const credential = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + biometricCredentialLifetimeMs);
  const created = await prisma.biometricCredential.create({
    data: {
      userId: actor.id,
      tokenHash: tokenHash(credential),
      expiresAt,
      userAgent: req.get('user-agent')?.slice(0, 500) ?? null,
    },
  });
  await prisma.auditLog.create({
    data: {
      actorId: actor.id,
      teamId: actor.teamId,
      action: 'BIOMETRIC_LOGIN_ENABLED',
      entityType: 'BiometricCredential',
      entityId: created.id,
    },
  });
  return res.status(201).json({ credential, expiresAt });
}

export async function biometricLogin(req: Request, res: Response) {
  const credential = typeof req.body?.credential === 'string'
    ? req.body.credential.trim()
    : '';
  if (credential.length < 32 || credential.length > 512) {
    return res.status(401).json({ message: 'Biometrische Anmeldung ist nicht gültig.' });
  }
  const stored = await prisma.biometricCredential.findUnique({
    where: { tokenHash: tokenHash(credential) },
    include: {
      user: {
        include: {
          registrationRequest: {
            select: {
              id: true,
              requestedRole: true,
              childName: true,
              relationship: true,
              reviewStatus: true,
              adminNote: true,
              applicantMessage: true,
              pushOptIn: true,
            },
          },
        },
      },
    },
  });
  const now = new Date();
  if (!stored || stored.revokedAt || stored.expiresAt <= now) {
    return res.status(401).json({ message: 'Biometrische Anmeldung ist abgelaufen.' });
  }
  const user = stored.user;
  if (
    user.status === AccountStatus.BLOCKED ||
    user.status === AccountStatus.REJECTED ||
    user.status === AccountStatus.ARCHIVED
  ) {
    return res.status(403).json({
      code: 'ACCOUNT_INACTIVE',
      accountStatus: user.status,
      message: 'Dieser Account ist nicht aktiv. Bitte wende dich an die Systemadministration.',
    });
  }
  await prisma.biometricCredential.update({
    where: { id: stored.id },
    data: {
      lastUsedAt: now,
      expiresAt: new Date(now.getTime() + biometricCredentialLifetimeMs),
    },
  });
  const tokens = await issueSession(user, req);
  const parentLinks = await familyLinks(user.id);
  return res.json({
    user: {
      ...userResponse(user),
      parentLinks,
      registrationRequest: user.registrationRequest,
    },
    ...tokens,
  });
}

export async function disableBiometricLogin(req: Request, res: Response) {
  const credential = typeof req.body?.credential === 'string'
    ? req.body.credential.trim()
    : '';
  if (!credential) return res.status(204).send();
  const stored = await prisma.biometricCredential.findFirst({
    where: {
      userId: req.user!.id,
      tokenHash: tokenHash(credential),
      revokedAt: null,
    },
    select: { id: true },
  });
  if (stored) {
    await prisma.$transaction([
      prisma.biometricCredential.update({
        where: { id: stored.id },
        data: { revokedAt: new Date() },
      }),
      prisma.auditLog.create({
        data: {
          actorId: req.user!.id,
          teamId: req.user!.teamId,
          action: 'BIOMETRIC_LOGIN_DISABLED',
          entityType: 'BiometricCredential',
          entityId: stored.id,
        },
      }),
    ]);
  }
  return res.status(204).send();
}

const passwordResetLifetimeMs = 15 * 60 * 1000;
const passwordResetResponse = {
  message:
    'Wenn unter dieser E-Mail-Adresse ein freigegebener Zugang besteht, erhältst du einen 15 Minuten gültigen Einmallink. Bitte prüfe auch den Spam- oder Junk-Ordner.',
};

export async function requestPasswordReset(req: Request, res: Response) {
  const normalizedEmail =
    typeof req.body.email === 'string'
      ? req.body.email.trim().toLowerCase()
      : '';
  if (!normalizedEmail || !normalizedEmail.includes('@')) {
    return res.status(202).json(passwordResetResponse);
  }

  const user = await prisma.user.findUnique({
    where: { email: normalizedEmail },
    select: {
      id: true,
      name: true,
      email: true,
      status: true,
    },
  });
  if (
    !user ||
    user.status === AccountStatus.BLOCKED ||
    user.status === AccountStatus.REJECTED ||
    user.status === AccountStatus.ARCHIVED
  ) {
    return res.status(202).json(passwordResetResponse);
  }

  await prisma.passwordResetToken.deleteMany({
    where: {
      OR: [
        { expiresAt: { lte: new Date() } },
        { userId: user.id, consumedAt: null },
      ],
    },
  });

  const token = randomBytes(32).toString('base64url');
  const reset = await prisma.passwordResetToken.create({
    data: {
      userId: user.id,
      tokenHash: tokenHash(token),
      expiresAt: new Date(Date.now() + passwordResetLifetimeMs),
    },
  });
  let resetDelivered = false;
  try {
    resetDelivered = await sendPasswordResetEmail({
      recipient: user.email,
      recipientName: user.name,
      token,
      resetId: reset.id,
      expiresAt: reset.expiresAt,
    });
  } catch (error) {
    console.error('[password-reset] email delivery failed', error);
  }
  if (!resetDelivered) {
    console.warn('[password-reset] email delivery was not accepted');
    await prisma.passwordResetToken.delete({ where: { id: reset.id } });
  }
  return res.status(202).json(passwordResetResponse);
}

export async function exchangePasswordReset(req: Request, res: Response) {
  const requestId =
    typeof req.body.requestId === 'string' ? req.body.requestId.trim() : '';
  const deviceEndpoint =
    typeof req.body.deviceEndpoint === 'string'
      ? req.body.deviceEndpoint.trim()
      : '';
  if (!requestId || !deviceEndpoint || deviceEndpoint.length > 4096) {
    return res.status(400).json({
      message:
        'Die Sicherheitsanfrage ist unvollständig. Bitte öffne die Pushnachricht auf dem registrierten Gerät erneut.',
    });
  }

  const now = new Date();
  const reset = await prisma.passwordResetToken.findUnique({
    where: { id: requestId },
    include: { user: { select: { status: true } } },
  });
  if (
    !reset ||
    reset.consumedAt ||
    reset.expiresAt <= now ||
    reset.user.status === AccountStatus.BLOCKED ||
    reset.user.status === AccountStatus.REJECTED ||
    reset.user.status === AccountStatus.ARCHIVED
  ) {
    return res.status(400).json({
      message: 'Die Sicherheitsanfrage ist ungültig oder abgelaufen.',
    });
  }
  const subscription = await prisma.pushSubscription.findFirst({
    where: {
      userId: reset.userId,
      endpoint: deviceEndpoint,
      isActive: true,
      administrativelyDisabledAt: null,
    },
    select: { id: true },
  });
  if (
    !subscription ||
    (reset.claimedBySubscriptionId &&
      reset.claimedBySubscriptionId !== subscription.id)
  ) {
    return res.status(403).json({
      message:
        'Der Passwortwechsel darf nur auf dem registrierten Gerät fortgesetzt werden, das die Anfrage zuerst geöffnet hat.',
    });
  }

  const token = randomBytes(32).toString('base64url');
  const claimed = await prisma.passwordResetToken.updateMany({
    where: {
      id: reset.id,
      consumedAt: null,
      expiresAt: { gt: now },
      OR: [
        { claimedBySubscriptionId: null },
        { claimedBySubscriptionId: subscription.id },
      ],
    },
    data: {
      tokenHash: tokenHash(token),
      exchangedAt: now,
      claimedBySubscriptionId: subscription.id,
    },
  });
  if (claimed.count !== 1) {
    return res.status(409).json({
      message:
        'Die Sicherheitsanfrage wurde bereits auf einem anderen Gerät geöffnet.',
    });
  }
  return res.json({ token, expiresAt: reset.expiresAt });
}

export async function confirmPasswordReset(req: Request, res: Response) {
  const token = typeof req.body.token === 'string' ? req.body.token.trim() : '';
  const password =
    typeof req.body.password === 'string' ? req.body.password : '';
  if (!token || password.length < 10) {
    return res.status(400).json({
      message: token
        ? 'Das neue Passwort muss mindestens 10 Zeichen lang sein.'
        : 'Der Reset-Link ist ungültig oder abgelaufen.',
    });
  }

  const now = new Date();
  const reset = await prisma.passwordResetToken.findUnique({
    where: { tokenHash: tokenHash(token) },
    include: { user: { select: { id: true, teamId: true, status: true } } },
  });
  if (
    !reset ||
    reset.consumedAt ||
    reset.expiresAt <= now ||
    reset.user.status === AccountStatus.BLOCKED ||
    reset.user.status === AccountStatus.REJECTED ||
    reset.user.status === AccountStatus.ARCHIVED
  ) {
    return res.status(400).json({
      message: 'Der Reset-Link ist ungültig oder abgelaufen.',
    });
  }

  const passwordHash = await hashPassword(password);
  try {
    await prisma.$transaction(async (tx) => {
      const consumed = await tx.passwordResetToken.updateMany({
        where: { id: reset.id, consumedAt: null, expiresAt: { gt: now } },
        data: { consumedAt: now },
      });
      if (consumed.count !== 1) throw new Error('RESET_ALREADY_CONSUMED');
      await tx.user.update({
        where: { id: reset.user.id },
        data: { password: passwordHash },
      });
      await tx.refreshToken.updateMany({
        where: { userId: reset.user.id, revokedAt: null },
        data: { revokedAt: now },
      });
      await tx.biometricCredential.updateMany({
        where: { userId: reset.user.id, revokedAt: null },
        data: { revokedAt: now },
      });
      await tx.notification.updateMany({
        where: { entityType: 'PasswordReset', entityId: reset.id },
        data: { readAt: now },
      });
      await tx.auditLog.create({
        data: {
          actorId: reset.user.id,
          teamId: reset.user.teamId,
          action: 'PASSWORD_RESET_COMPLETED',
          entityType: 'User',
          entityId: reset.user.id,
        },
      });
    });
  } catch {
    return res.status(400).json({
      message: 'Der Reset-Link ist ungültig oder wurde bereits verwendet.',
    });
  }
  return res.json({
    message: 'Dein Passwort wurde geändert. Du kannst dich jetzt anmelden.',
  });
}

export async function refresh(req: Request, res: Response) {
  const refreshToken =
    typeof req.body.refreshToken === 'string' ? req.body.refreshToken : '';
  if (!refreshToken) {
    return res.status(400).json({ message: 'Refresh-Token fehlt.' });
  }

  let payload: { sessionId?: string; userId?: string; familyId?: string };
  try {
    payload = verifyRefreshToken(refreshToken) as typeof payload;
  } catch {
    return res.status(401).json({ message: 'Sitzung ist abgelaufen.' });
  }
  if (!payload.sessionId || !payload.userId || !payload.familyId) {
    return res.status(401).json({ message: 'Ungültige Sitzung.' });
  }

  const session = await prisma.refreshToken.findUnique({
    where: { id: payload.sessionId },
    include: { user: true },
  });
  const reused =
    session?.revokedAt != null &&
    session.tokenHash === tokenHash(refreshToken);
  if (reused) {
    if (isRecentRefreshRotation(session.revokedAt)) {
      return res.status(409).json({
        code: 'REFRESH_TOKEN_ROTATED',
        message: 'Sitzung wurde bereits in einem anderen App-Fenster erneuert.',
      });
    }
    await prisma.refreshToken.updateMany({
      where: { familyId: session.familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return res.status(401).json({ message: 'Sitzung wurde widerrufen.' });
  }
  if (
    !session ||
    session.userId !== payload.userId ||
    session.familyId !== payload.familyId ||
    session.tokenHash !== tokenHash(refreshToken) ||
    session.expiresAt <= new Date()
  ) {
    return res.status(401).json({ message: 'Sitzung ist abgelaufen.' });
  }
  if (
    session.user.status === AccountStatus.BLOCKED ||
    session.user.status === AccountStatus.REJECTED ||
    session.user.status === AccountStatus.ARCHIVED
  ) {
    return res.status(403).json({ message: 'Account ist nicht aktiv.' });
  }

  const consumed = await prisma.refreshToken.updateMany({
    where: {
      id: session.id,
      tokenHash: tokenHash(refreshToken),
      revokedAt: null,
      expiresAt: { gt: new Date() },
    },
    data: { revokedAt: new Date(), lastUsedAt: new Date() },
  });
  if (consumed.count !== 1) {
    const concurrentRotation = await prisma.refreshToken.findUnique({
      where: { id: session.id },
      select: { revokedAt: true, tokenHash: true },
    });
    if (
      concurrentRotation?.tokenHash === tokenHash(refreshToken) &&
      isRecentRefreshRotation(concurrentRotation.revokedAt)
    ) {
      return res.status(409).json({
        code: 'REFRESH_TOKEN_ROTATED',
        message: 'Sitzung wurde bereits in einem anderen App-Fenster erneuert.',
      });
    }
    await prisma.refreshToken.updateMany({
      where: { familyId: session.familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return res.status(401).json({ message: 'Sitzung wurde widerrufen.' });
  }

  const next = await issueSession(session.user, req, session.familyId);
  const parentLinks = await familyLinks(session.user.id);
  const nextPayload = verifyRefreshToken(next.refreshToken) as {
    sessionId: string;
  };
  await prisma.refreshToken.update({
    where: { id: session.id },
    data: {
      replacedById: nextPayload.sessionId,
    },
  });
  return res.json({
    user: { ...userResponse(session.user), parentLinks },
    ...next,
  });
}

export async function logout(req: Request, res: Response) {
  const refreshToken =
    typeof req.body.refreshToken === 'string' ? req.body.refreshToken : '';
  if (refreshToken) {
    await prisma.refreshToken.updateMany({
      where: { tokenHash: tokenHash(refreshToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
  return res.status(204).send();
}

export async function updateOwnProfile(req: Request, res: Response) {
  const actor = req.user!;
  const firstName = typeof req.body?.firstName === 'string'
    ? req.body.firstName.trim()
    : '';
  const lastName = typeof req.body?.lastName === 'string'
    ? req.body.lastName.trim()
    : '';
  const email = typeof req.body?.email === 'string'
    ? req.body.email.trim().toLowerCase()
    : '';
  const phone = typeof req.body?.phone === 'string' && req.body.phone.trim()
    ? req.body.phone.trim()
    : null;
  if (!firstName || !lastName || !/^\S+@\S+\.\S+$/.test(email)) {
    return res.status(400).json({
      message: 'Vorname, Nachname und eine gültige E-Mail-Adresse sind erforderlich.',
    });
  }
  if (firstName.length > 80 || lastName.length > 80 || email.length > 254 || (phone?.length ?? 0) > 60) {
    return res.status(400).json({ message: 'Mindestens eine Eingabe ist zu lang.' });
  }
  const current = await prisma.user.findUnique({
    where: { id: actor.id },
    select: {
      id: true,
      email: true,
      firstName: true,
      lastName: true,
      phone: true,
      teamId: true,
    },
  });
  if (!current) return res.status(404).json({ message: 'Konto nicht gefunden.' });
  const duplicate = await prisma.user.findFirst({
    where: { email, id: { not: actor.id }, accountDeletedAt: null },
    select: { id: true },
  });
  if (duplicate) {
    return res.status(409).json({ message: 'Diese E-Mail-Adresse wird bereits verwendet.' });
  }
  const changedFields = [
    current.firstName !== firstName || current.lastName !== lastName ? 'name' : null,
    current.email !== email ? 'email' : null,
    current.phone !== phone ? 'phone' : null,
  ].filter((value): value is string => value !== null);
  const updated = await prisma.$transaction(async (tx) => {
    const user = await tx.user.update({
      where: { id: actor.id },
      data: {
        firstName,
        lastName,
        name: `${firstName} ${lastName}`,
        email,
        phone,
      },
      select: {
        id: true,
        email: true,
        name: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        status: true,
        teamId: true,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: current.teamId,
        action: 'USER_PROFILE_UPDATED',
        entityType: 'User',
        entityId: actor.id,
        metadata: { changedFields },
      },
    });
    return user;
  });
  return res.json(updated);
}

export async function changeOwnPassword(req: Request, res: Response) {
  const actor = req.user!;
  const currentPassword = typeof req.body?.currentPassword === 'string'
    ? req.body.currentPassword
    : '';
  const newPassword = typeof req.body?.newPassword === 'string'
    ? req.body.newPassword
    : '';
  if (!currentPassword || newPassword.length < 10) {
    return res.status(400).json({
      message: 'Das aktuelle Passwort und ein neues Passwort mit mindestens 10 Zeichen sind erforderlich.',
    });
  }
  if (currentPassword === newPassword) {
    return res.status(400).json({ message: 'Das neue Passwort muss sich vom aktuellen unterscheiden.' });
  }
  const user = await prisma.user.findUnique({
    where: { id: actor.id },
    select: { id: true, password: true, teamId: true },
  });
  if (!user || !await comparePassword(currentPassword, user.password)) {
    return res.status(400).json({ message: 'Das aktuelle Passwort ist nicht korrekt.' });
  }
  const passwordHash = await hashPassword(newPassword);
  const changedAt = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.user.update({
      where: { id: actor.id },
      data: { password: passwordHash },
    });
    await tx.refreshToken.updateMany({
      where: { userId: actor.id, revokedAt: null },
      data: { revokedAt: changedAt },
    });
    await tx.biometricCredential.updateMany({
      where: { userId: actor.id, revokedAt: null },
      data: { revokedAt: changedAt },
    });
    await tx.passwordResetToken.updateMany({
      where: { userId: actor.id, consumedAt: null },
      data: { consumedAt: changedAt },
    });
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: user.teamId,
        action: 'PASSWORD_CHANGED_BY_USER',
        entityType: 'User',
        entityId: actor.id,
      },
    });
  });
  return res.json({
    message: 'Dein Passwort wurde geändert. Bitte melde dich erneut an.',
    reauthenticate: true,
  });
}

export async function logoutAll(req: Request, res: Response) {
  const revokedAt = new Date();
  await prisma.$transaction([
    prisma.refreshToken.updateMany({
      where: { userId: req.user!.id, revokedAt: null },
      data: { revokedAt },
    }),
    prisma.biometricCredential.updateMany({
      where: { userId: req.user!.id, revokedAt: null },
      data: { revokedAt },
    }),
  ]);
  return res.status(204).send();
}

export async function me(req: Request, res: Response) {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      memberships: {
        where: { status: AccountStatus.APPROVED },
        orderBy: { team: { name: 'asc' } },
        select: {
          id: true,
          role: true,
          status: true,
          team: {
            select: {
              id: true,
              name: true,
              ageGroup: { select: { name: true, code: true } },
            },
          },
        },
      },
      registrationRequest: {
        select: {
          id: true,
          requestedRole: true,
          childName: true,
          relationship: true,
          reviewStatus: true,
          adminNote: true,
          applicantMessage: true,
          pushOptIn: true,
        },
      },
    },
  });
  if (!user) return res.status(404).json({ message: 'User not found' });
  const parentLinks = await familyLinks(user.id);

  return res.json({
    id: user.id,
    email: user.email,
    name: user.name,
    firstName: user.firstName,
    lastName: user.lastName,
    phone: user.phone,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
    memberships: user.memberships,
    parentLinks,
    registrationRequest: user.registrationRequest,
    preview: req.user?.previewActorId
      ? {
          readOnly: true,
          actorId: req.user.previewActorId,
          actorName: req.user.previewActorName,
          targetId: user.id,
          targetName: user.name,
        }
      : null,
  });
}

function userResponse(user: {
  id: string;
  email: string;
  name: string;
  firstName: string | null;
  lastName: string | null;
  phone: string | null;
  role: Role;
  status: AccountStatus;
  teamId: string;
}) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    firstName: user.firstName,
    lastName: user.lastName,
    phone: user.phone,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  };
}
