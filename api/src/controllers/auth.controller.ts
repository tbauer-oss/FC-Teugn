import { Request, Response } from 'express';
import { createHash, randomUUID } from 'crypto';
import { prisma } from '../lib/prisma';
import { hashPassword, comparePassword } from '../lib/password';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../lib/jwt';
import { AccountStatus, Role } from '../types/enums';
import { ConsentDocumentType, GuardianRelationship } from '@prisma/client';

const refreshLifetimeMs = 30 * 24 * 60 * 60 * 1000;

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
        },
        {
          userId: created.id,
          consentTextVersionId: termsVersion.id,
          granted: true,
        },
        ...(pushVersion
          ? [
              {
                userId: created.id,
                consentTextVersionId: pushVersion.id,
                granted: pushOptIn,
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

  return res.status(201).json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      role: user.role,
      status: user.status,
      teamId: user.teamId,
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
    return res.status(400).json({ message: 'Ungültige Zugangsdaten' });
  }

  if (
    user.status === AccountStatus.BLOCKED ||
    user.status === AccountStatus.REJECTED ||
    user.status === AccountStatus.ARCHIVED
  ) {
    return res.status(403).json({ message: 'Dieser Account ist nicht aktiv.' });
  }

  const tokens = await issueSession(user, req);

  return res.json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      role: user.role,
      status: user.status,
      teamId: user.teamId,
      registrationRequest: user.registrationRequest,
    },
    ...tokens,
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
    await prisma.refreshToken.updateMany({
      where: { familyId: session.familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return res.status(401).json({ message: 'Sitzung wurde widerrufen.' });
  }

  const next = await issueSession(session.user, req, session.familyId);
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
    user: userResponse(session.user),
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

export async function logoutAll(req: Request, res: Response) {
  await prisma.refreshToken.updateMany({
    where: { userId: req.user!.id, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  return res.status(204).send();
}

export async function me(req: Request, res: Response) {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const user = await prisma.user.findUnique({
    where: { id: userId },
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
  if (!user) return res.status(404).json({ message: 'User not found' });

  return res.json({
    id: user.id,
    email: user.email,
    name: user.name,
    phone: user.phone,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
    registrationRequest: user.registrationRequest,
  });
}

function userResponse(user: {
  id: string;
  email: string;
  name: string;
  phone: string | null;
  role: Role;
  status: AccountStatus;
  teamId: string;
}) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    phone: user.phone,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  };
}
