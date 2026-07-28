import { Request, Response } from 'express';
import { AccountStatus, GuardianRelationship } from '@prisma/client';
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
  const users = await prisma.user.findMany({
    where: {
      status: AccountStatus.PENDING,
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
  } = req.body as {
    userId?: string;
    status?: AccountStatus;
    role?: Role;
    teamIds?: string[];
    playerId?: string;
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

  const nextStatus =
    status === AccountStatus.BLOCKED || status === AccountStatus.APPROVED
      ? status
      : AccountStatus.APPROVED;
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
    nextRole === Role.PLAYER && playerId
      ? await prisma.player.findFirst({
          where: {
            id: playerId,
            teamId: { in: allowedTeams.map((team) => team.id) },
            OR: [{ userId: null }, { userId: target.id }],
          },
          select: { id: true },
        })
      : null;
  if (nextRole === Role.PLAYER && !linkedPlayer) {
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
    await tx.player.updateMany({
      where: { userId: target.id },
      data: { userId: null },
    });
    if (linkedPlayer) {
      await tx.player.update({
        where: { id: linkedPlayer.id },
        data: { userId: target.id },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: actor.id,
        teamId: primaryTeamId,
        action: nextStatus === AccountStatus.APPROVED ? 'USER_APPROVED' : 'USER_BLOCKED',
        entityType: 'User',
        entityId: target.id,
        metadata: {
          role: nextRole,
          teamIds: allowedTeams.map((team) => team.id),
          playerId: linkedPlayer?.id,
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
