import { Request, Response } from 'express';
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
  hasPermission,
  Permission,
  permissionsForRole,
} from '../security/permissions';
import { accessibleTeamIds } from '../services/team-access';
import { hashPassword } from '../lib/password';

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

function userScope(
  actor: { teamId: string; role: Role },
  clubId: string | undefined,
): Prisma.UserWhereInput {
  if (isSuperAdmin(actor.role)) return {};
  if (hasPermission(actor.role, Permission.MANAGE_ORGANIZATION) && clubId) {
    return { team: { ageGroup: { season: { clubId } } } };
  }
  return { teamId: actor.teamId };
}

export async function pendingUsers(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await actorClubId(user.teamId);
  const teamId = typeof req.query.teamId === 'string' ? req.query.teamId : undefined;
  const role = typeof req.query.role === 'string' ? req.query.role as Role : undefined;
  const query = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const users = await prisma.user.findMany({
    where: {
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
      ...userScope(user, clubId),
    },
    orderBy: { createdAt: 'asc' },
    select: memberSelect,
  });
  return res.json(users);
}

export async function listMembers(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await actorClubId(user.teamId);
  const users = await prisma.user.findMany({
    where: userScope(user, clubId),
    orderBy: [{ status: 'asc' }, { name: 'asc' }],
    select: memberSelect,
  });
  return res.json(users);
}

export async function createMember(req: Request, res: Response) {
  const actor = req.user!;
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
    adminNote?: string;
    applicantMessage?: string;
    reviewStatus?: RegistrationReviewStatus;
  };
  if (!userId) {
    return res.status(400).json({ message: 'Benutzer-ID fehlt.' });
  }

  const clubId = await actorClubId(actor.teamId);
  const canManageOrganization = hasPermission(actor.role, Permission.MANAGE_ORGANIZATION);
  const target = await prisma.user.findFirst({
    where: {
      id: userId,
      ...userScope(actor, clubId),
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
        : { id: actor.teamId }),
    },
    select: { id: true, ageGroupId: true },
  });
  if (allowedTeams.length !== requestedTeamIds.length) {
    return res.status(400).json({ message: 'Mindestens eine Mannschaft ist nicht zulässig.' });
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

  const primaryTeamId = allowedTeams[0].id;
  const membershipFunctions = teamFunctionMap(
    teamRoles,
    allowedTeams.map((team) => team.id),
    nextRole,
    actor.role,
  );
  const updated = await prisma.$transaction(async (tx) => {
    const member = await tx.user.update({
      where: { id: target.id },
      data: { status: nextStatus, role: nextRole, teamId: primaryTeamId },
      select: memberSelect,
    });
    await tx.teamMembership.deleteMany({
      where: {
        userId: target.id,
        ...(clubId ? { team: { ageGroup: { season: { clubId } } } } : {}),
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
    if (nextStatus === AccountStatus.APPROVED) {
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
      if (linkedPlayer && canHaveParentPlayerLinks(nextRole)) {
        await tx.parentPlayerLink.upsert({
          where: {
            parentId_playerId: { parentId: target.id, playerId: linkedPlayer.id },
          },
          create: {
            parentId: target.id,
            playerId: linkedPlayer.id,
            relationship:
              relationship &&
              Object.values(GuardianRelationship).includes(relationship)
                ? relationship
                : GuardianRelationship.GUARDIAN,
          },
          update: {
            relationship:
              relationship &&
              Object.values(GuardianRelationship).includes(relationship)
                ? relationship
                : GuardianRelationship.GUARDIAN,
          },
        });
      }
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
          reviewStatus: nextReviewStatus,
          adminNote: adminNote?.trim() || null,
          applicantMessage: applicantMessage?.trim() || null,
        },
      },
    });
    return member;
  });

  return res.json(updated);
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
  const teamIds = await accessibleTeamIds(actor);
  const [parent, player] = await Promise.all([
    prisma.user.findFirst({
      where: {
        id: parentId,
        ...(isSuperAdmin(actor.role)
          ? {}
          : { OR: [{ teamId: { in: teamIds } }, { memberships: { some: { teamId: { in: teamIds } } } }] }),
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
