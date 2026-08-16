import { Request, Response } from 'express';
import { createHash, randomBytes } from 'crypto';
import {
  AccountStatus,
  GuardianRelationship,
  PermissionOverrideState,
  Prisma,
  RegistrationReviewStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Role } from '../types/enums';
import {
  effectivePermissionsForUser,
  hasEffectivePermission,
  hasPermission,
  Permission,
  permissionsForRole,
} from '../security/permissions';
import {
  accessibleTeamIds,
  memberManagementTeamIds,
} from '../services/team-access';
import { hashPassword } from '../lib/password';

const adminPasswordResetLifetimeMs = 60 * 60 * 1000;

class RegistrationApprovalConflict extends Error {}

function passwordResetTokenHash(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

const memberSelect = {
  id: true,
  name: true,
  email: true,
  phone: true,
  role: true,
  status: true,
  teamId: true,
  createdAt: true,
  memberships: {
    orderBy: { team: { name: 'asc' as const } },
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
  parentLinks: {
    orderBy: { player: { lastName: 'asc' as const } },
    select: {
      id: true,
      relationship: true,
      isLegalGuardian: true,
      canPickup: true,
      receivesCommunication: true,
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
      reviewedAt: true,
      reviewedBy: { select: { id: true, name: true } },
      requestedTeams: {
        select: {
          team: {
            select: {
              id: true,
              name: true,
              ageGroup: { select: { name: true, code: true } },
            },
          },
        },
      },
      history: {
        orderBy: { createdAt: 'desc' as const },
        take: 20,
        select: {
          id: true,
          fromStatus: true,
          toStatus: true,
          fromReviewStatus: true,
          toReviewStatus: true,
          note: true,
          createdAt: true,
          actor: { select: { id: true, name: true } },
        },
      },
    },
  },
} as const;

async function actorClubId(teamId: string) {
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: { ageGroup: { select: { season: { select: { clubId: true } } } } },
  });
  return team?.ageGroup.season.clubId;
}

function isSuperAdmin(role: Role) {
  return role === Role.SUPER_ADMIN;
}

export function canHaveParentPlayerLinks(role: Role) {
  return role !== Role.PLAYER;
}

export function canLimitedManagerUpdateMember(
  targetStatus: AccountStatus,
  targetRole: Role,
  nextStatus: AccountStatus,
  nextRole: Role,
) {
  if (nextStatus !== AccountStatus.APPROVED) return false;
  if (targetStatus === AccountStatus.APPROVED) return nextRole === targetRole;
  return targetStatus === AccountStatus.PENDING && nextRole === targetRole;
}

export function limitedManagerTeamAssignmentAllowed(
  targetStatus: AccountStatus,
  requestedTeamIds: string[],
  currentScopedTeamIds: string[],
  managementTeamIds: string[],
) {
  if (!requestedTeamIds.every((id) => managementTeamIds.includes(id))) {
    return false;
  }
  if (targetStatus === AccountStatus.PENDING) return true;
  // An already approved parent can become visible to a second youth through
  // a still documented registration request or an existing child link. In
  // that case there is intentionally no account membership in this youth;
  // the trainer may add only the locally authorized child relation while the
  // account's primary team and memberships remain untouched.
  if (currentScopedTeamIds.length === 0) return true;
  return requestedTeamIds.length === currentScopedTeamIds.length &&
    requestedTeamIds.every((id) => currentScopedTeamIds.includes(id));
}

const singleYouthRoles = new Set<Role>([
  Role.COACH,
  Role.TRAINER,
  Role.ASSISTANT_COACH,
]);

async function violatesSingleYouthAssignment(role: Role, teamIds: string[]) {
  if (!singleYouthRoles.has(role) || teamIds.length < 2) return false;
  const ageGroups = await prisma.team.findMany({
    where: { id: { in: teamIds }, deletedAt: null },
    distinct: ['ageGroupId'],
    select: { ageGroupId: true },
  });
  return ageGroups.length !== 1;
}

const assignableTeamFunctions: Role[] = [
  Role.COACH,
  Role.ASSISTANT_COACH,
  Role.TEAM_MANAGER,
  Role.PARENT,
  Role.PLAYER,
  Role.READ_ONLY,
];

function teamFunctionMap(
  value: unknown,
  teamIds: string[],
  fallback: Role,
  actorRole: Role,
) {
  const canAssignStaff =
    isSuperAdmin(actorRole) ||
    hasPermission(actorRole, Permission.MANAGE_ORGANIZATION);
  const result = new Map<string, Role>();
  if (canAssignStaff && Array.isArray(value)) {
    for (const item of value) {
      if (!item || typeof item !== 'object') continue;
      const teamId = String((item as { teamId?: unknown }).teamId ?? '');
      const role = (item as { role?: Role }).role;
      if (
        role &&
        teamIds.includes(teamId) &&
        assignableTeamFunctions.includes(role)
      ) {
        result.set(teamId, role);
      }
    }
  }
  return new Map(
    teamIds.map((teamId) => [
      teamId,
      result.get(teamId) ??
        (assignableTeamFunctions.includes(fallback) ? fallback : Role.READ_ONLY),
    ]),
  );
}

function teamMemberScope(teamIds: string[]): Prisma.UserWhereInput {
  return {
    OR: [
      { teamId: { in: teamIds } },
      { memberships: { some: { teamId: { in: teamIds } } } },
      {
        registrationRequest: {
          requestedTeams: { some: { teamId: { in: teamIds } } },
        },
      },
      { parentLinks: { some: { player: { teamId: { in: teamIds } } } } },
      { playerProfile: { teamId: { in: teamIds } } },
    ],
  };
}

async function userScope(
  actor: { id: string; teamId: string; role: Role; permissions?: string[] },
  clubId: string | undefined,
): Promise<Prisma.UserWhereInput> {
  if (isSuperAdmin(actor.role)) return {};
  if (
    hasEffectivePermission(
      actor.role,
      Permission.MANAGE_ORGANIZATION,
      actor.permissions,
    ) &&
    clubId
  ) {
    return {
      OR: [
        { team: { ageGroup: { season: { clubId } } } },
        {
          memberships: {
            some: { team: { ageGroup: { season: { clubId } } } },
          },
        },
        {
          registrationRequest: {
            requestedTeams: {
              some: { team: { ageGroup: { season: { clubId } } } },
            },
          },
        },
        {
          parentLinks: {
            some: { player: { team: { ageGroup: { season: { clubId } } } } },
          },
        },
      ],
    };
  }
  return teamMemberScope(await memberManagementTeamIds(actor));
}

function scopedMemberView<T extends {
  memberships: Array<{ team: { id: string } }>;
  parentLinks: Array<{ player: { teamId: string | null } }>;
  registrationRequest: null | {
    requestedTeams: Array<{ team: { id: string } }>;
  };
}>(member: T, teamIds: string[]) {
  const allowed = new Set(teamIds);
  return {
    ...member,
    memberships: member.memberships.filter((item) => allowed.has(item.team.id)),
    parentLinks: member.parentLinks.filter(
      (item) => item.player.teamId !== null && allowed.has(item.player.teamId),
    ),
    registrationRequest: member.registrationRequest
      ? {
          ...member.registrationRequest,
          requestedTeams: member.registrationRequest.requestedTeams.filter(
            (item) => allowed.has(item.team.id),
          ),
        }
      : null,
  };
}

export async function pendingUsers(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await actorClubId(user.teamId);
  const managementTeamIds = await memberManagementTeamIds(user);
  const limited = !isSuperAdmin(user.role) && !hasEffectivePermission(
    user.role,
    Permission.MANAGE_ORGANIZATION,
    user.permissions,
  );
  const teamId = typeof req.query.teamId === 'string' ? req.query.teamId : undefined;
  if (limited && teamId && !managementTeamIds.includes(teamId)) {
    return res.status(403).json({ message: 'Diese Jugend darf nicht verwaltet werden.' });
  }
  const role = typeof req.query.role === 'string' ? req.query.role as Role : undefined;
  const query = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const users = await prisma.user.findMany({
    where: {
      accountDeletedAt: null,
      status: AccountStatus.PENDING,
      ...(role && Object.values(Role).includes(role) ? { role } : {}),
      ...(query
        ? {
            OR: [
              { name: { contains: query, mode: 'insensitive' as const } },
              { email: { contains: query, mode: 'insensitive' as const } },
              {
                registrationRequest: {
                  childName: { contains: query, mode: 'insensitive' as const },
                },
              },
            ],
          }
        : {}),
      ...(teamId
        ? {
            registrationRequest: {
              requestedTeams: { some: { teamId } },
            },
          }
        : {}),
      ...(await userScope(user, clubId)),
    },
    orderBy: { createdAt: 'asc' },
    select: memberSelect,
  });
  return res.json(limited
    ? users.map((member) => scopedMemberView(member, managementTeamIds))
    : users);
}

export async function listMembers(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await actorClubId(user.teamId);
  const managementTeamIds = await memberManagementTeamIds(user);
  const limited = !isSuperAdmin(user.role) && !hasEffectivePermission(
    user.role,
    Permission.MANAGE_ORGANIZATION,
    user.permissions,
  );
  const users = await prisma.user.findMany({
    where: {
      accountDeletedAt: null,
      ...(await userScope(user, clubId)),
    },
    orderBy: [{ status: 'asc' }, { name: 'asc' }],
    select: memberSelect,
  });
  return res.json(limited
    ? users.map((member) => scopedMemberView(member, managementTeamIds))
    : users);
}

export async function createMember(req: Request, res: Response) {
  const actor = req.user!;
  if (!isSuperAdmin(actor.role) && !hasEffectivePermission(
    actor.role,
    Permission.MANAGE_ORGANIZATION,
    actor.permissions,
  )) {
    return res.status(403).json({
      message: 'Trainer dürfen Konten freigeben und Eltern zuweisen, aber keine neuen Konten anlegen.',
    });
  }
  const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
  const email =
    typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
  const phone =
    typeof req.body?.phone === 'string' && req.body.phone.trim()
      ? req.body.phone.trim()
      : null;
  const password = typeof req.body?.password === 'string' ? req.body.password : '';
  const requestedRole = normalizeAssignableRole(req.body?.role as Role, actor.role);
  const requestedTeamIds: string[] = Array.isArray(req.body?.teamIds)
    ? [...new Set<string>(
        (req.body.teamIds as unknown[]).filter(
          (id: unknown): id is string => typeof id === 'string',
        ),
      )]
    : [];
  const teamFunctions = teamFunctionMap(
    req.body?.teamRoles,
    requestedTeamIds,
    requestedRole ?? Role.READ_ONLY,
    actor.role,
  );
  if (!name || !email || !email.includes('@')) {
    return res.status(400).json({ message: 'Name und gültige E-Mail-Adresse sind erforderlich.' });
  }
  if (password.length < 10) {
    return res.status(400).json({ message: 'Das Startpasswort muss mindestens 10 Zeichen haben.' });
  }
  if (!requestedRole) {
    return res.status(403).json({ message: 'Diese Rolle darf nicht vergeben werden.' });
  }
  if (requestedTeamIds.length === 0) {
    return res.status(400).json({ message: 'Mindestens eine Mannschaft ist erforderlich.' });
  }
  const allowedIds = await accessibleTeamIds(actor);
  if (!requestedTeamIds.every((id) => allowedIds.includes(id))) {
    return res.status(403).json({ message: 'Mindestens eine Mannschaft ist nicht zulässig.' });
  }
  if (await violatesSingleYouthAssignment(requestedRole, requestedTeamIds)) {
    return res.status(400).json({
      message: 'Trainer und Co-Trainer dürfen nur Mannschaften einer Jugend zugeordnet sein.',
    });
  }
  const playerId =
    typeof req.body?.playerId === 'string' ? req.body.playerId.trim() : null;
  const linkedPlayer =
    requestedRole === Role.PLAYER && playerId
      ? await prisma.player.findFirst({
          where: {
            id: playerId,
            teamId: { in: requestedTeamIds },
            userId: null,
          },
          select: { id: true },
        })
      : null;
  if (requestedRole === Role.PLAYER && !linkedPlayer) {
    return res.status(400).json({
      message: 'Für einen Spielerzugang muss ein freies Spielerprofil gewählt werden.',
    });
  }
  if (await prisma.user.findUnique({ where: { email }, select: { id: true } })) {
    return res.status(409).json({ message: 'Diese E-Mail-Adresse ist bereits registriert.' });
  }
  const passwordHash = await hashPassword(password);
  const member = await prisma.$transaction(async (tx) => {
    const created = await tx.user.create({
      data: {
        name,
        email,
        phone,
        password: passwordHash,
        role: requestedRole,
        status: AccountStatus.APPROVED,
        teamId: requestedTeamIds[0],
        memberships: {
          create: requestedTeamIds.map((teamId) => ({
            teamId,
            role: teamFunctions.get(teamId)!,
            status: AccountStatus.APPROVED,
          })),
        },
      },
      select: memberSelect,
    });
    if (linkedPlayer) {
      await tx.player.update({
        where: { id: linkedPlayer.id },
        data: { userId: created.id },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: requestedTeamIds[0],
        action: 'USER_CREATED_BY_ADMIN',
        entityType: 'User',
        entityId: created.id,
        metadata: { role: requestedRole, teamIds: requestedTeamIds },
      },
    });
    return created;
  });
  return res.status(201).json(member);
}

export async function createMemberPasswordResetLink(
  req: Request,
  res: Response,
) {
  const actor = req.user!;
  const member = await prisma.user.findUnique({
    where: { id: req.params.id },
    select: { id: true, name: true, teamId: true, status: true },
  });
  if (!member) {
    return res.status(404).json({ message: 'Mitglied nicht gefunden.' });
  }
  if (
    member.status === AccountStatus.BLOCKED ||
    member.status === AccountStatus.REJECTED ||
    member.status === AccountStatus.ARCHIVED
  ) {
    return res.status(400).json({
      message: 'Für diesen inaktiven Zugang kann kein Link erstellt werden.',
    });
  }

  const token = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + adminPasswordResetLifetimeMs);
  await prisma.$transaction(async (tx) => {
    await tx.passwordResetToken.deleteMany({
      where: { userId: member.id, consumedAt: null },
    });
    await tx.passwordResetToken.create({
      data: {
        userId: member.id,
        tokenHash: passwordResetTokenHash(token),
        expiresAt,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: member.teamId,
        action: 'PASSWORD_RESET_LINK_CREATED_BY_ADMIN',
        entityType: 'User',
        entityId: member.id,
        metadata: { expiresAt: expiresAt.toISOString() },
      },
    });
  });

  const appBaseUrl = (
    process.env.PUBLIC_APP_URL ?? 'https://fcteugnapp.vercel.app'
  ).replace(/\/$/, '');
  const actionUrl = `/reset-password?token=${encodeURIComponent(token)}`;
  return res.status(201).json({
    memberName: member.name,
    actionUrl,
    url: `${appBaseUrl}/#${actionUrl}`,
    expiresAt,
  });
}

export async function deleteMemberAccount(req: Request, res: Response) {
  const actor = req.user!;
  const target = await prisma.user.findUnique({
    where: { id: req.params.id },
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      status: true,
      teamId: true,
      accountDeletedAt: true,
      memberships: { select: { teamId: true } },
    },
  });
  if (!target || target.accountDeletedAt) {
    return res.status(404).json({ message: 'Mitglied nicht gefunden.' });
  }
  if (target.id === actor.id) {
    return res.status(400).json({
      message: 'Das aktuell verwendete Systemadministrationskonto kann nicht selbst gelöscht werden.',
    });
  }
  if (target.role === Role.SUPER_ADMIN) {
    const remainingSuperAdmins = await prisma.user.count({
      where: {
        id: { not: target.id },
        role: Role.SUPER_ADMIN,
        status: AccountStatus.APPROVED,
        accountDeletedAt: null,
      },
    });
    if (remainingSuperAdmins === 0) {
      return res.status(400).json({
        message: 'Das letzte aktive Systemadministrationskonto kann nicht gelöscht werden.',
      });
    }
  }

  const deletedAt = new Date();
  const replacementPassword = await hashPassword(randomBytes(32).toString('base64url'));
  const deletedEmail = `deleted-${target.id}@accounts.invalid`;
  await prisma.$transaction(async (tx) => {
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: target.teamId,
        action: 'USER_ACCOUNT_DELETED',
        entityType: 'User',
        entityId: target.id,
        metadata: {
          previousRole: target.role,
          previousStatus: target.status,
          previousTeamIds: target.memberships.map((item) => item.teamId),
          deletionMode: 'ANONYMIZED_TOMBSTONE',
        },
      },
    });
    await tx.notificationDelivery.deleteMany({ where: { userId: target.id } });
    await tx.notification.deleteMany({ where: { userId: target.id } });
    await tx.pushSubscription.deleteMany({ where: { userId: target.id } });
    await tx.notificationPreference.deleteMany({ where: { userId: target.id } });
    await tx.refreshToken.deleteMany({ where: { userId: target.id } });
    await tx.passwordResetToken.deleteMany({ where: { userId: target.id } });
    await tx.idempotencyRecord.deleteMany({ where: { userId: target.id } });
    await tx.userPermissionOverride.deleteMany({ where: { userId: target.id } });
    await tx.userContextPreference.deleteMany({ where: { userId: target.id } });
    await tx.registrationRequest.deleteMany({ where: { userId: target.id } });
    await tx.userConsent.deleteMany({ where: { userId: target.id } });
    await tx.eventParticipant.deleteMany({ where: { userId: target.id } });
    await tx.eventReminder.deleteMany({ where: { recipientId: target.id } });
    await tx.scheduledReminder.deleteMany({ where: { recipientId: target.id } });
    await tx.announcementRecipient.deleteMany({ where: { userId: target.id } });
    await tx.announcementRead.deleteMany({ where: { userId: target.id } });
    await tx.carpoolPassenger.deleteMany({ where: { requestedById: target.id } });
    await tx.carpoolNeed.deleteMany({ where: { requestedById: target.id } });
    await tx.carpoolOffer.deleteMany({ where: { driverId: target.id } });
    await tx.parentPlayerLink.deleteMany({ where: { parentId: target.id } });
    await tx.teamMembership.deleteMany({ where: { userId: target.id } });
    await tx.player.updateMany({
      where: { userId: target.id },
      data: { userId: null },
    });
    await tx.user.update({
      where: { id: target.id },
      data: {
        name: 'Gelöschtes Konto',
        firstName: null,
        lastName: null,
        phone: null,
        email: deletedEmail,
        password: replacementPassword,
        role: Role.READ_ONLY,
        status: AccountStatus.ARCHIVED,
        calendarToken: null,
        accountDeletedAt: deletedAt,
      },
    });
  });
  return res.status(204).send();
}

export async function approveUser(req: Request, res: Response) {
  const actor = req.user!;
  const {
    userId,
    status,
    role,
    teamIds,
    teamRoles,
    playerId,
    relationship,
    guardianLinks,
    adminNote,
    applicantMessage,
    reviewStatus,
  } = req.body as {
    userId?: string;
    status?: AccountStatus;
    role?: Role;
    teamIds?: string[];
    teamRoles?: Array<{ teamId?: string; role?: Role }>;
    playerId?: string;
    relationship?: GuardianRelationship;
    guardianLinks?: Array<{
      playerId?: string;
      relationship?: GuardianRelationship;
    }>;
    adminNote?: string;
    applicantMessage?: string;
    reviewStatus?: RegistrationReviewStatus;
  };
  if (!userId) {
    return res.status(400).json({ message: 'Benutzer-ID fehlt.' });
  }

  const clubId = await actorClubId(actor.teamId);
  const canManageOrganization = hasEffectivePermission(
    actor.role,
    Permission.MANAGE_ORGANIZATION,
    actor.permissions,
  );
  const managementTeamIds = await memberManagementTeamIds(actor);
  const limitedManager = !isSuperAdmin(actor.role) && !canManageOrganization;
  const target = await prisma.user.findFirst({
    where: {
      id: userId,
      ...(await userScope(actor, clubId)),
    },
    include: {
      memberships: { select: { teamId: true, role: true } },
      registrationRequest: {
        select: { requestedTeams: { select: { teamId: true } } },
      },
    },
  });
  if (!target) {
    return res.status(404).json({ message: 'Mitglied nicht gefunden.' });
  }

  const allowedStatuses: AccountStatus[] = [
    AccountStatus.PENDING,
    AccountStatus.APPROVED,
    AccountStatus.REJECTED,
    AccountStatus.BLOCKED,
    AccountStatus.ARCHIVED,
  ];
  const nextStatus =
    status && allowedStatuses.includes(status) ? status : AccountStatus.APPROVED;
  const allowedReviewStatuses = Object.values(RegistrationReviewStatus);
  const nextReviewStatus =
    reviewStatus && allowedReviewStatuses.includes(reviewStatus)
      ? reviewStatus
      : nextStatus === AccountStatus.PENDING
        ? RegistrationReviewStatus.IN_REVIEW
        : RegistrationReviewStatus.COMPLETED;
  if (target.role === Role.SUPER_ADMIN && !isSuperAdmin(actor.role)) {
    return res.status(403).json({
      message: 'Systemadministratoren dürfen nur von Systemadministratoren bearbeitet werden.',
    });
  }
  const nextRole = normalizeAssignableRole(
    role ?? (target.role as Role),
    actor.role,
  );
  if (!nextRole) {
    return res.status(403).json({ message: 'Diese Rolle darf nicht vergeben werden.' });
  }
  if (limitedManager) {
    if (!canLimitedManagerUpdateMember(
      target.status,
      target.role as Role,
      nextStatus,
      nextRole,
    )) {
      return res.status(403).json({
        message: 'Trainer dürfen beantragte Konten freigeben sowie Eltern zuweisen, aber Konten weder sperren, deaktivieren noch in Rolle oder Mannschaft verändern.',
      });
    }
  }
  if (
    target.role === Role.SUPER_ADMIN &&
    (nextRole !== Role.SUPER_ADMIN || nextStatus !== AccountStatus.APPROVED)
  ) {
    const remainingSuperAdmins = await prisma.user.count({
      where: {
        id: { not: target.id },
        role: Role.SUPER_ADMIN,
        status: AccountStatus.APPROVED,
      },
    });
    if (remainingSuperAdmins === 0) {
      return res.status(400).json({
        message: 'Der letzte aktive Systemadministrator kann nicht herabgestuft oder gesperrt werden.',
      });
    }
  }

  const requestedTeamIds =
    Array.isArray(teamIds) && teamIds.length > 0 ? [...new Set(teamIds)] : [target.teamId];
  const allowedTeams = await prisma.team.findMany({
    where: {
      id: { in: requestedTeamIds },
      ...(isSuperAdmin(actor.role)
        ? { isActive: true }
        : canManageOrganization && clubId
        ? { ageGroup: { season: { clubId, isActive: true } } }
        : { id: { in: managementTeamIds }, isActive: true }),
    },
    select: { id: true, ageGroupId: true },
  });
  if (allowedTeams.length !== requestedTeamIds.length) {
    return res.status(400).json({ message: 'Mindestens eine Mannschaft ist nicht zulässig.' });
  }
  if (limitedManager) {
    const currentScopedTeamIds = target.status === AccountStatus.PENDING
      ? target.registrationRequest?.requestedTeams
          .map((item) => item.teamId)
          .filter((id) => managementTeamIds.includes(id)) ?? []
      : [...new Set([
          ...(managementTeamIds.includes(target.teamId) ? [target.teamId] : []),
          ...target.memberships
            .map((membership) => membership.teamId)
            .filter((id) => managementTeamIds.includes(id)),
        ])];
    const assignmentAllowed = limitedManagerTeamAssignmentAllowed(
      target.status,
      requestedTeamIds,
      currentScopedTeamIds,
      managementTeamIds,
    );
    if (!assignmentAllowed) {
      return res.status(403).json({
        message: target.status === AccountStatus.PENDING
          ? 'Trainer dürfen eine Registrierung nur Mannschaften ihrer gewählten Jugend zuordnen.'
          : 'Trainer dürfen bestehende Mannschaftszuordnungen nicht ändern.',
      });
    }
  }
  if (await violatesSingleYouthAssignment(
    nextRole,
    allowedTeams.map((team) => team.id),
  )) {
    return res.status(400).json({
      message: 'Trainer und Co-Trainer dürfen nur Mannschaften einer Jugend zugeordnet sein.',
    });
  }
  let linkedPlayer =
    playerId
      ? await prisma.player.findFirst({
          where: {
            id: playerId,
            teamId: { in: allowedTeams.map((team) => team.id) },
            ...(nextRole === Role.PLAYER
              ? { OR: [{ userId: null }, { userId: target.id }] }
              : {}),
          },
          select: { id: true },
        })
      : null;

  const requestedGuardianLinks = nextRole === Role.PLAYER
    ? []
    : [
        ...(Array.isArray(guardianLinks) ? guardianLinks : []),
        ...(!Array.isArray(guardianLinks) && playerId
          ? [{ playerId, relationship }]
          : []),
      ];
  const guardianAssignments = new Map<string, GuardianRelationship>();
  for (const assignment of requestedGuardianLinks) {
    const assignedPlayerId = typeof assignment?.playerId === 'string'
      ? assignment.playerId.trim()
      : '';
    if (!assignedPlayerId) {
      return res.status(400).json({
        message: 'Mindestens eine Kinderzuordnung ist unvollständig.',
      });
    }
    const assignedRelationship = assignment.relationship &&
      Object.values(GuardianRelationship).includes(assignment.relationship)
      ? assignment.relationship
      : GuardianRelationship.GUARDIAN;
    guardianAssignments.set(assignedPlayerId, assignedRelationship);
  }
  const guardianPlayers = guardianAssignments.size === 0
    ? []
    : await prisma.player.findMany({
        where: {
          id: { in: [...guardianAssignments.keys()] },
          teamId: {
            in: limitedManager
              ? managementTeamIds
              : allowedTeams.map((team) => team.id),
          },
        },
        select: { id: true, teamId: true },
      });
  if (guardianPlayers.length !== guardianAssignments.size) {
    return res.status(403).json({
      message: 'Mindestens ein Kind gehört nicht zu deinem erlaubten Mannschafts- oder Jugendbereich.',
    });
  }
  if (
    nextStatus === AccountStatus.APPROVED &&
    target.status === AccountStatus.PENDING &&
    nextRole === Role.PARENT &&
    guardianAssignments.size === 0
  ) {
    return res.status(400).json({
      message: 'Für einen Elternzugang muss mindestens ein Kind zugeordnet werden.',
    });
  }
  if (nextRole === Role.PLAYER && !linkedPlayer && !playerId) {
    linkedPlayer = await prisma.player.findFirst({
      where: {
        userId: target.id,
        teamId: { in: allowedTeams.map((team) => team.id) },
      },
      select: { id: true },
    });
  }
  if (
    nextStatus === AccountStatus.APPROVED &&
    nextRole === Role.PLAYER &&
    !linkedPlayer
  ) {
    return res.status(400).json({
      message: 'Für einen Spielerzugang muss ein passendes Spielerprofil gewählt werden.',
    });
  }

  const preserveAccountAssignment =
    limitedManager && target.status === AccountStatus.APPROVED;
  const primaryTeamId = preserveAccountAssignment
    ? target.teamId
    : allowedTeams[0].id;
  const membershipFunctions = teamFunctionMap(
    teamRoles,
    allowedTeams.map((team) => team.id),
    nextRole,
    actor.role,
  );
  let updated: Prisma.UserGetPayload<{ select: typeof memberSelect }>;
  try {
    updated = await prisma.$transaction(async (tx) => {
    if (
      target.status === AccountStatus.PENDING &&
      nextStatus !== AccountStatus.PENDING
    ) {
      const claimed = await tx.user.updateMany({
        where: { id: target.id, status: AccountStatus.PENDING },
        data: { status: nextStatus, role: nextRole, teamId: primaryTeamId },
      });
      if (claimed.count !== 1) {
        throw new RegistrationApprovalConflict();
      }
    }
    const member = preserveAccountAssignment
      ? await tx.user.findUniqueOrThrow({
          where: { id: target.id },
          select: memberSelect,
        })
      : await tx.user.update({
          where: { id: target.id },
          data: { status: nextStatus, role: nextRole, teamId: primaryTeamId },
          select: memberSelect,
        });
    if (!preserveAccountAssignment) {
      await tx.teamMembership.deleteMany({
        where: {
          userId: target.id,
          ...(limitedManager
            ? { teamId: { in: managementTeamIds } }
            : clubId
              ? { team: { ageGroup: { season: { clubId } } } }
              : {}),
        },
      });
      await tx.teamMembership.createMany({
        data: allowedTeams.map((team) => ({
          userId: target.id,
          teamId: team.id,
          role: membershipFunctions.get(team.id)!,
          status: nextStatus,
        })),
        skipDuplicates: true,
      });
    }
    if (nextStatus === AccountStatus.APPROVED) {
      if (!preserveAccountAssignment) {
        await tx.player.updateMany({
          where: { userId: target.id },
          data: { userId: null },
        });
        if (linkedPlayer && nextRole === Role.PLAYER) {
          await tx.player.update({
            where: { id: linkedPlayer.id },
            data: { userId: target.id },
          });
        }
      }
      if (canHaveParentPlayerLinks(nextRole)) {
        for (const [assignedPlayerId, assignedRelationship] of guardianAssignments) {
          await tx.parentPlayerLink.upsert({
            where: {
              parentId_playerId: {
                parentId: target.id,
                playerId: assignedPlayerId,
              },
            },
            create: {
              parentId: target.id,
              playerId: assignedPlayerId,
              relationship: assignedRelationship,
            },
            update: { relationship: assignedRelationship },
          });
        }
      }
    } else if (target.status === AccountStatus.PENDING) {
      await tx.parentPlayerLink.deleteMany({ where: { parentId: target.id } });
    }
    const registration = await tx.registrationRequest.findUnique({
      where: { userId: target.id },
    });
    if (registration) {
      await tx.registrationRequest.update({
        where: { id: registration.id },
        data: {
          reviewStatus: nextReviewStatus,
          adminNote: adminNote?.trim() || registration.adminNote,
          applicantMessage:
            applicantMessage?.trim() || registration.applicantMessage,
          reviewedById: actor.id,
          reviewedAt: new Date(),
        },
      });
      await tx.registrationHistory.create({
        data: {
          registrationRequestId: registration.id,
          actorId: actor.id,
          fromStatus: target.status,
          toStatus: nextStatus,
          fromReviewStatus: registration.reviewStatus,
          toReviewStatus: nextReviewStatus,
          note: adminNote?.trim() || applicantMessage?.trim() || null,
          metadata: {
            role: nextRole,
            teamRoles: Object.fromEntries(membershipFunctions),
            teamIds: allowedTeams.map((team) => team.id),
            playerId: linkedPlayer?.id,
            guardianLinks: [...guardianAssignments].map(
              ([assignedPlayerId, assignedRelationship]) => ({
                playerId: assignedPlayerId,
                relationship: assignedRelationship,
              }),
            ),
          },
        },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: primaryTeamId,
        action: `USER_${nextStatus}`,
        entityType: 'User',
        entityId: target.id,
        metadata: {
          role: nextRole,
          teamRoles: Object.fromEntries(membershipFunctions),
          teamIds: allowedTeams.map((team) => team.id),
          playerId: linkedPlayer?.id,
          guardianLinks: [...guardianAssignments].map(
            ([assignedPlayerId, assignedRelationship]) => ({
              playerId: assignedPlayerId,
              relationship: assignedRelationship,
            }),
          ),
          reviewStatus: nextReviewStatus,
          adminNote: adminNote?.trim() || null,
          applicantMessage: applicantMessage?.trim() || null,
        },
      },
    });
    return tx.user.findUniqueOrThrow({
      where: { id: member.id },
      select: memberSelect,
    });
    }, {
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
    });
  } catch (error) {
    if (
      error instanceof RegistrationApprovalConflict ||
      (error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2034')
    ) {
      return res.status(409).json({
        message: 'Die Registrierung wurde bereits von einer anderen Person bearbeitet.',
      });
    }
    throw error;
  }

  return res.json(limitedManager
    ? scopedMemberView(updated, managementTeamIds)
    : updated);
}

export async function assignParentPlayer(req: Request, res: Response) {
  const {
    parentId,
    playerId,
    relationship,
    isLegalGuardian,
    canPickup,
    receivesCommunication,
  } = req.body as {
    parentId?: string;
    playerId?: string;
    relationship?: GuardianRelationship;
    isLegalGuardian?: boolean;
    canPickup?: boolean;
    receivesCommunication?: boolean;
  };
  if (!parentId || !playerId) {
    return res.status(400).json({ message: 'Elternteil und Spieler sind erforderlich.' });
  }

  const actor = req.user!;
  const teamIds = await memberManagementTeamIds(actor);
  const [parent, player] = await Promise.all([
    prisma.user.findFirst({
      where: {
        id: parentId,
        ...(isSuperAdmin(actor.role)
          ? {}
          : {
              OR: [
                { teamId: { in: teamIds } },
                { memberships: { some: { teamId: { in: teamIds } } } },
                {
                  parentLinks: {
                    some: { player: { teamId: { in: teamIds } } },
                  },
                },
              ],
            }),
      },
    }),
    prisma.player.findFirst({ where: { id: playerId, teamId: { in: teamIds } } }),
  ]);
  if (
    !parent ||
    parent.status !== AccountStatus.APPROVED ||
    !canHaveParentPlayerLinks(parent.role as Role)
  ) {
    return res.status(404).json({ message: 'Freigegebenes Mitglied nicht gefunden.' });
  }
  if (!player) {
    return res.status(404).json({ message: 'Spieler nicht gefunden.' });
  }

  const relation = Object.values(GuardianRelationship).includes(
    relationship as GuardianRelationship,
  )
    ? relationship!
    : GuardianRelationship.GUARDIAN;
  const link = await prisma.$transaction(async (tx) => {
    const result = await tx.parentPlayerLink.upsert({
      where: { parentId_playerId: { parentId, playerId } },
      update: {
        relationship: relation,
        isLegalGuardian: isLegalGuardian ?? true,
        canPickup: canPickup ?? true,
        receivesCommunication: receivesCommunication ?? true,
      },
      create: {
        parentId,
        playerId,
        relationship: relation,
        isLegalGuardian: isLegalGuardian ?? true,
        canPickup: canPickup ?? true,
        receivesCommunication: receivesCommunication ?? true,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: actor.teamId,
        action: 'GUARDIAN_ASSIGNED',
        entityType: 'ParentPlayerLink',
        entityId: result.id,
        metadata: { parentId, playerId, relationship: relation },
      },
    });
    return result;
  });
  return res.status(201).json(link);
}

export async function removeParentPlayer(req: Request, res: Response) {
  const actor = req.user!;
  const { parentId, playerId } = req.params;
  const link = await prisma.parentPlayerLink.findUnique({
    where: { parentId_playerId: { parentId, playerId } },
    select: {
      id: true,
      relationship: true,
      isLegalGuardian: true,
      canPickup: true,
      receivesCommunication: true,
      parent: { select: { id: true, name: true } },
      player: {
        select: { id: true, firstName: true, lastName: true, teamId: true },
      },
    },
  });
  if (!link) {
    return res.status(404).json({
      message: 'Diese Sorgeberechtigten-Zuordnung besteht nicht mehr.',
    });
  }

  await prisma.$transaction(async (tx) => {
    await tx.parentPlayerLink.delete({ where: { id: link.id } });
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: link.player.teamId ?? actor.teamId,
        action: 'GUARDIAN_ASSIGNMENT_REMOVED',
        entityType: 'ParentPlayerLink',
        entityId: link.id,
        metadata: {
          parentId: link.parent.id,
          parentName: link.parent.name,
          playerId: link.player.id,
          playerName: `${link.player.firstName} ${link.player.lastName}`.trim(),
          relationship: link.relationship,
          isLegalGuardian: link.isLegalGuardian,
          canPickup: link.canPickup,
          receivesCommunication: link.receivesCommunication,
        },
      },
    });
  });

  return res.status(204).send();
}

export async function getMemberPermissions(req: Request, res: Response) {
  const target = await prisma.user.findUnique({
    where: { id: req.params.id },
    select: {
      id: true,
      name: true,
      role: true,
      permissionOverrides: {
        orderBy: { permission: 'asc' },
        select: { permission: true, state: true, updatedAt: true },
      },
    },
  });
  if (!target) return res.status(404).json({ message: 'Mitglied nicht gefunden.' });
  return res.json({
    ...target,
    rolePermissions: permissionsForRole(target.role as Role),
    effectivePermissions: await effectivePermissionsForUser(
      target.id,
      target.role as Role,
    ),
    availablePermissions: Object.values(Permission),
  });
}

export async function updateMemberPermission(req: Request, res: Response) {
  const actor = req.user!;
  const target = await prisma.user.findUnique({
    where: { id: req.params.id },
    select: { id: true, role: true, teamId: true },
  });
  if (!target) return res.status(404).json({ message: 'Mitglied nicht gefunden.' });
  const permission = String(req.body?.permission ?? '') as Permission;
  if (!Object.values(Permission).includes(permission)) {
    return res.status(400).json({ message: 'Unbekannte Berechtigung.' });
  }
  if (target.role === Role.SUPER_ADMIN) {
    return res.status(400).json({
      message: 'Systemadministrator-Rechte sind aus Sicherheitsgründen unveränderlich.',
    });
  }
  const requestedState = String(req.body?.state ?? '').toUpperCase();
  const previous = await prisma.userPermissionOverride.findUnique({
    where: { userId_permission: { userId: target.id, permission } },
    select: { state: true },
  });
  await prisma.$transaction(async (tx) => {
    if (requestedState === 'DEFAULT') {
      await tx.userPermissionOverride.deleteMany({
        where: { userId: target.id, permission },
      });
    } else {
      const state = requestedState === PermissionOverrideState.ALLOW
        ? PermissionOverrideState.ALLOW
        : requestedState === PermissionOverrideState.DENY
          ? PermissionOverrideState.DENY
          : null;
      if (!state) throw new Error('INVALID_PERMISSION_STATE');
      await tx.userPermissionOverride.upsert({
        where: { userId_permission: { userId: target.id, permission } },
        update: { state, changedById: actor.id },
        create: { userId: target.id, permission, state, changedById: actor.id },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: target.teamId,
        action: 'USER_PERMISSION_CHANGED',
        entityType: 'User',
        entityId: target.id,
        metadata: {
          permission,
          before: previous?.state ?? 'DEFAULT',
          after: requestedState,
        },
      },
    });
  }).catch((error) => {
    if (error instanceof Error && error.message === 'INVALID_PERMISSION_STATE') return null;
    throw error;
  });
  if (!['DEFAULT', 'ALLOW', 'DENY'].includes(requestedState)) {
    return res.status(400).json({ message: 'Status muss DEFAULT, ALLOW oder DENY sein.' });
  }
  return getMemberPermissions(req, res);
}

export async function resetMemberPermissions(req: Request, res: Response) {
  const actor = req.user!;
  const target = await prisma.user.findUnique({
    where: { id: req.params.id },
    select: { id: true, role: true, teamId: true },
  });
  if (!target) return res.status(404).json({ message: 'Mitglied nicht gefunden.' });
  if (target.role === Role.SUPER_ADMIN) {
    return res.status(400).json({ message: 'Systemadministrator-Rechte sind unveränderlich.' });
  }
  await prisma.$transaction([
    prisma.userPermissionOverride.deleteMany({ where: { userId: target.id } }),
    prisma.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: target.teamId,
        action: 'USER_PERMISSIONS_RESET',
        entityType: 'User',
        entityId: target.id,
      },
    }),
  ]);
  return getMemberPermissions(req, res);
}

function normalizeAssignableRole(role: Role, actorRole: Role) {
  const organizationRoles: Role[] = [
    Role.CLUB_ADMIN,
    Role.YOUTH_DIRECTOR,
    Role.COACH,
    Role.ASSISTANT_COACH,
    Role.TEAM_MANAGER,
    Role.PARENT,
    Role.PLAYER,
    Role.READ_ONLY,
  ];
  const teamRoles: Role[] = [Role.PARENT, Role.PLAYER, Role.READ_ONLY];
  const allowed = isSuperAdmin(actorRole)
    ? [Role.SUPER_ADMIN, ...organizationRoles]
    : hasPermission(actorRole, Permission.MANAGE_ORGANIZATION)
      ? organizationRoles
      : teamRoles;
  return allowed.includes(role) ? role : null;
}
