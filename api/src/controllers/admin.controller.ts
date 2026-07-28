import { Request, Response } from 'express';
import {
  AccountStatus,
  GuardianRelationship,
  RegistrationReviewStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Role } from '../types/enums';
import { hasPermission, Permission } from '../security/permissions';

const memberSelect = {
  id: true,
  name: true,
  email: true,
  phone: true,
  role: true,
  status: true,
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

export async function pendingUsers(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await actorClubId(user.teamId);
  const canManageOrganization = hasPermission(user.role, Permission.MANAGE_ORGANIZATION);
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
      ...(canManageOrganization && clubId
        ? { team: { ageGroup: { season: { clubId } } } }
        : { teamId: user.teamId }),
    },
    orderBy: { createdAt: 'asc' },
    select: memberSelect,
  });
  return res.json(users);
}

export async function listMembers(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await actorClubId(user.teamId);
  const canManageOrganization = hasPermission(user.role, Permission.MANAGE_ORGANIZATION);
  const users = await prisma.user.findMany({
    where: canManageOrganization && clubId
      ? { team: { ageGroup: { season: { clubId } } } }
      : { teamId: user.teamId },
    orderBy: [{ status: 'asc' }, { name: 'asc' }],
    select: memberSelect,
  });
  return res.json(users);
}

export async function approveUser(req: Request, res: Response) {
  const actor = req.user!;
  const {
    userId,
    status,
    role,
    teamIds,
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
      ...(canManageOrganization && clubId
        ? { team: { ageGroup: { season: { clubId } } } }
        : { teamId: actor.teamId }),
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
  const nextRole = normalizeAssignableRole(role ?? (target.role as Role), canManageOrganization);
  if (!nextRole) {
    return res.status(403).json({ message: 'Diese Rolle darf nicht vergeben werden.' });
  }

  const requestedTeamIds =
    Array.isArray(teamIds) && teamIds.length > 0 ? [...new Set(teamIds)] : [target.teamId];
  const allowedTeams = await prisma.team.findMany({
    where: {
      id: { in: requestedTeamIds },
      ...(canManageOrganization && clubId
        ? { ageGroup: { season: { clubId, isActive: true } } }
        : { id: actor.teamId }),
    },
    select: { id: true },
  });
  if (allowedTeams.length !== requestedTeamIds.length) {
    return res.status(400).json({ message: 'Mindestens eine Mannschaft ist nicht zulässig.' });
  }
  const linkedPlayer =
    (nextRole === Role.PLAYER || nextRole === Role.PARENT) && playerId
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
        role: nextRole,
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
      if (linkedPlayer && nextRole === Role.PARENT) {
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
  const [parent, player] = await Promise.all([
    prisma.user.findFirst({ where: { id: parentId, teamId: actor.teamId } }),
    prisma.player.findFirst({ where: { id: playerId, teamId: actor.teamId } }),
  ]);
  if (!parent || parent.role !== Role.PARENT) {
    return res.status(404).json({ message: 'Elternteil nicht gefunden.' });
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

function normalizeAssignableRole(role: Role, canManageOrganization: boolean) {
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
  const allowed = canManageOrganization ? organizationRoles : teamRoles;
  return allowed.includes(role) ? role : null;
}
