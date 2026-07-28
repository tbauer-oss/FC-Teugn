import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hashPassword, comparePassword } from '../lib/password';
import { signAccessToken } from '../lib/jwt';
import { AccountStatus, Role } from '../types/enums';
import { ConsentDocumentType, GuardianRelationship } from '@prisma/client';

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

  const accessToken = signAccessToken({
    id: user.id,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  });
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
    accessToken,
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

  const accessToken = signAccessToken({
    id: user.id,
    role: user.role,
    status: user.status,
    teamId: user.teamId,
  });

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
    accessToken,
  });
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
