import { Request, Response } from 'express';
import { DominantFoot, PlayerStatus } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Role } from '../types/enums';
import { hasPermission, Permission } from '../security/permissions';
import { accessibleTeamIds } from '../services/team-access';
import { objectStorage } from '../services/object-storage';

const publicPlayerSelect = {
  id: true,
  teamId: true,
  firstName: true,
  lastName: true,
  preferredName: true,
  birthDate: true,
  nationality: true,
  position: true,
  secondaryPosition: true,
  dominantFoot: true,
  shirtNumber: true,
  status: true,
  joinedAt: true,
  createdAt: true,
  updatedAt: true,
} as const;

function isGuardianRole(role: Role) {
  return role === Role.PARENT;
}

function isPlayerRole(role: Role) {
  return role === Role.PLAYER;
}

async function guardianLink(userId: string, playerId: string) {
  return prisma.parentPlayerLink.findFirst({
    where: { parentId: userId, playerId },
  });
}

export async function canAccessPlayer(req: Request, playerId: string) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const player = await prisma.player.findFirst({
    where: { id: playerId, teamId: { in: teamIds } },
    select: { id: true, userId: true },
  });
  if (!player) return false;
  if (isPlayerRole(user.role)) return player.userId === user.id;
  if (!isGuardianRole(user.role)) return true;
  return Boolean(await guardianLink(user.id, playerId));
}

export async function listPlayers(req: Request, res: Response) {
  const { teamId, role, id: userId } = req.user!;

  if (isPlayerRole(role)) {
    const ownPlayer = await prisma.player.findMany({
      where: { userId, teamId },
      select: publicPlayerSelect,
    });
    return res.json(ownPlayer);
  }

  if (isGuardianRole(role)) {
    const links = await prisma.parentPlayerLink.findMany({
      where: { parentId: userId },
      include: { player: { select: publicPlayerSelect } },
      orderBy: { player: { lastName: 'asc' } },
    });
    return res.json(links.map((link) => link.player));
  }

  const status = parsePlayerStatus(req.query.status);
  const teamIds = await accessibleTeamIds(req.user!);
  const players = await prisma.player.findMany({
    where: { teamId: { in: teamIds }, ...(status ? { status } : {}) },
    orderBy: [{ status: 'asc' }, { lastName: 'asc' }, { firstName: 'asc' }],
    select: publicPlayerSelect,
  });
  return res.json(players);
}

export async function getPlayer(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }

  const guardian = isGuardianRole(user.role)
    ? await guardianLink(user.id, id)
    : null;
  const canViewSensitive =
    hasPermission(user.role, Permission.VIEW_SENSITIVE_PLAYER) ||
    guardian?.isLegalGuardian === true ||
    isPlayerRole(user.role);
  const canViewStaffNotes = hasPermission(user.role, Permission.MANAGE_DEVELOPMENT);

  const player = await prisma.player.findUnique({
    where: { id },
    select: {
      ...publicPlayerSelect,
      team: {
        select: {
          id: true,
          name: true,
          ageGroup: { select: { id: true, name: true, code: true } },
        },
      },
      photoAsset: {
        select: { pathname: true, deletedAt: true },
      },
      photoUrl: true,
      parentLinks: {
        select: {
          id: true,
          relationship: true,
          isLegalGuardian: true,
          canPickup: true,
          receivesCommunication: true,
          parent: {
            select: { id: true, name: true, email: true, phone: true },
          },
        },
      },
      medicalProfile: canViewSensitive,
      emergencyContacts: canViewSensitive
        ? { orderBy: [{ priority: 'asc' }, { name: 'asc' }] }
        : false,
      consents: canViewSensitive ? { orderBy: { type: 'asc' } } : false,
      developmentNotes: {
        where: canViewStaffNotes
          ? {}
          : guardian || isPlayerRole(user.role)
            ? { visibility: 'GUARDIANS_AND_STAFF' }
            : { id: '__no_visible_development_notes__' },
        orderBy: { observedAt: 'desc' },
        include: { author: { select: { id: true, name: true } } },
      },
    },
  });

  return res.json({
    ...player,
    photoAsset: undefined,
    photoUrl:
      player?.photoAsset && player.photoAsset.deletedAt === null
        ? await objectStorage.signedReadUrl(player.photoAsset.pathname)
        : player?.photoUrl ?? null,
    capabilities: {
      canEdit: hasPermission(user.role, Permission.MANAGE_PLAYERS),
      canViewSensitive,
      canEditSensitive:
        hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) ||
        guardian?.isLegalGuardian === true,
      canManageDocuments:
        hasPermission(user.role, Permission.MANAGE_DOCUMENTS) ||
        guardian?.isLegalGuardian === true,
      canManagePhoto:
        hasPermission(user.role, Permission.MANAGE_PLAYERS) ||
        guardian?.isLegalGuardian === true,
      canAddDevelopment: hasPermission(user.role, Permission.MANAGE_DEVELOPMENT),
    },
  });
}

export async function createPlayer(req: Request, res: Response) {
  const { teamId, id: actorId } = req.user!;
  const data = playerData(req.body);
  if (!data.firstName || !data.lastName) {
    return res.status(400).json({ message: 'Vor- und Nachname sind erforderlich.' });
  }

  const player = await prisma.$transaction(async (tx) => {
    const created = await tx.player.create({
      data: { ...data, teamId },
      select: publicPlayerSelect,
    });
    await tx.auditLog.create({
      data: {
        actorId,
        teamId,
        action: 'PLAYER_CREATED',
        entityType: 'Player',
        entityId: created.id,
        metadata: { name: `${created.firstName} ${created.lastName}` },
      },
    });
    return created;
  });

  return res.status(201).json(player);
}

export async function updatePlayer(req: Request, res: Response) {
  const { teamId, id: actorId } = req.user!;
  const { id } = req.params;
  const player = await prisma.player.findFirst({ where: { id, teamId } });
  if (!player) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });

  const updated = await prisma.$transaction(async (tx) => {
    const result = await tx.player.update({
      where: { id },
      data: Object.fromEntries(
        Object.entries(playerData(req.body)).filter(
          ([key, value]) => req.body[key] !== undefined && value !== undefined,
        ),
      ),
      select: publicPlayerSelect,
    });
    await tx.auditLog.create({
      data: {
        actorId,
        teamId,
        action: 'PLAYER_UPDATED',
        entityType: 'Player',
        entityId: id,
      },
    });
    return result;
  });

  return res.json(updated);
}

export async function upsertMedicalProfile(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const guardian = isGuardianRole(user.role)
    ? await guardianLink(user.id, id)
    : null;
  if (
    !hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) &&
    guardian?.isLegalGuardian !== true
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für Gesundheitsdaten.' });
  }

  const fields = [
    'allergies',
    'medications',
    'conditions',
    'physicianName',
    'physicianPhone',
    'emergencyNotes',
  ] as const;
  const data = Object.fromEntries(
    fields.map((field) => [field, cleanOptionalString(req.body[field])]),
  );
  const medical = await prisma.$transaction(async (tx) => {
    const result = await tx.playerMedicalProfile.upsert({
      where: { playerId: id },
      update: { ...data, updatedById: user.id },
      create: { ...data, playerId: id, updatedById: user.id },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: 'PLAYER_MEDICAL_UPDATED',
        entityType: 'Player',
        entityId: id,
      },
    });
    return result;
  });
  return res.json(medical);
}

export async function createEmergencyContact(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const guardian = isGuardianRole(user.role)
    ? await guardianLink(user.id, id)
    : null;
  if (
    !hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) &&
    guardian?.isLegalGuardian !== true
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für Notfallkontakte.' });
  }
  const { name, phone, relationship, priority, isAuthorizedPickup } = req.body;
  if (!name?.trim() || !phone?.trim()) {
    return res.status(400).json({ message: 'Name und Telefonnummer sind erforderlich.' });
  }
  const contact = await prisma.playerEmergencyContact.create({
    data: {
      playerId: id,
      name: name.trim(),
      phone: phone.trim(),
      relationship: cleanOptionalString(relationship),
      priority: Number.isInteger(priority) ? Math.max(1, priority) : 1,
      isAuthorizedPickup: isAuthorizedPickup === true,
    },
  });
  return res.status(201).json(contact);
}

export async function addDevelopmentNote(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const { title, notes, category, visibility, rating, observedAt } = req.body;
  if (!title?.trim() || !notes?.trim()) {
    return res.status(400).json({ message: 'Titel und Beobachtung sind erforderlich.' });
  }
  const normalizedRating =
    Number.isInteger(rating) && rating >= 1 && rating <= 5 ? rating : null;
  const entry = await prisma.playerDevelopmentNote.create({
    data: {
      playerId: id,
      authorId: user.id,
      title: title.trim(),
      notes: notes.trim(),
      category: validDevelopmentCategory(category),
      visibility:
        visibility === 'GUARDIANS_AND_STAFF' ? 'GUARDIANS_AND_STAFF' : 'STAFF_ONLY',
      rating: normalizedRating,
      observedAt: validDate(observedAt) ?? new Date(),
    },
    include: { author: { select: { id: true, name: true } } },
  });
  return res.status(201).json(entry);
}

export async function upsertConsent(req: Request, res: Response) {
  const user = req.user!;
  const { id, type } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const guardian = isGuardianRole(user.role)
    ? await guardianLink(user.id, id)
    : null;
  if (
    !hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) &&
    guardian?.isLegalGuardian !== true
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für Einwilligungen.' });
  }
  const consentType = validConsentType(type);
  if (!consentType) {
    return res.status(400).json({ message: 'Unbekannte Einwilligungsart.' });
  }
  const status = validConsentStatus(req.body.status);
  const now = new Date();
  const consent = await prisma.$transaction(async (tx) => {
    const result = await tx.playerConsent.upsert({
      where: { playerId_type: { playerId: id, type: consentType } },
      update: {
        status,
        grantedBy: status === 'GRANTED' ? user.id : undefined,
        grantedAt: status === 'GRANTED' ? now : undefined,
        revokedAt: status === 'REVOKED' ? now : null,
        expiresAt: validDate(req.body.expiresAt),
        note: cleanOptionalString(req.body.note),
      },
      create: {
        playerId: id,
        type: consentType,
        status,
        grantedBy: status === 'GRANTED' ? user.id : null,
        grantedAt: status === 'GRANTED' ? now : null,
        revokedAt: status === 'REVOKED' ? now : null,
        expiresAt: validDate(req.body.expiresAt),
        note: cleanOptionalString(req.body.note),
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: `PLAYER_CONSENT_${status}`,
        entityType: 'PlayerConsent',
        entityId: result.id,
        metadata: { playerId: id, type: consentType },
      },
    });
    return result;
  });
  return res.json(consent);
}

export async function deletePlayer(req: Request, res: Response) {
  const { teamId, id: actorId } = req.user!;
  const { id } = req.params;
  const player = await prisma.player.findFirst({ where: { id, teamId } });
  if (!player) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });

  await prisma.$transaction(async (tx) => {
    await tx.auditLog.create({
      data: {
        actorId,
        teamId,
        action: 'PLAYER_DELETED',
        entityType: 'Player',
        entityId: id,
        metadata: { name: `${player.firstName} ${player.lastName}` },
      },
    });
    await tx.player.delete({ where: { id } });
  });
  return res.status(204).send();
}

function playerData(body: Record<string, unknown>) {
  return {
    firstName: cleanRequiredString(body.firstName),
    lastName: cleanRequiredString(body.lastName),
    preferredName: cleanOptionalString(body.preferredName),
    birthDate: validDate(body.birthDate),
    nationality: cleanOptionalString(body.nationality),
    position: cleanOptionalString(body.position),
    secondaryPosition: cleanOptionalString(body.secondaryPosition),
    dominantFoot: parseDominantFoot(body.dominantFoot) ?? DominantFoot.UNKNOWN,
    shirtNumber:
      Number.isInteger(body.shirtNumber) && Number(body.shirtNumber) > 0
        ? Number(body.shirtNumber)
        : null,
    status: parsePlayerStatus(body.status) ?? PlayerStatus.ACTIVE,
    joinedAt: validDate(body.joinedAt),
  };
}

function cleanRequiredString(value: unknown) {
  return typeof value === 'string' ? value.trim() : '';
}

function cleanOptionalString(value: unknown) {
  if (value === null) return null;
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function validDate(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const date = new Date(String(value));
  return Number.isNaN(date.valueOf()) ? null : date;
}

function parsePlayerStatus(value: unknown) {
  return typeof value === 'string' &&
    Object.values(PlayerStatus).includes(value as PlayerStatus)
    ? (value as PlayerStatus)
    : null;
}

function parseDominantFoot(value: unknown) {
  return typeof value === 'string' &&
    Object.values(DominantFoot).includes(value as DominantFoot)
    ? (value as DominantFoot)
    : null;
}

function validDevelopmentCategory(value: unknown) {
  return [
    'TECHNIQUE',
    'TACTICS',
    'ATHLETIC',
    'SOCIAL',
    'GOALKEEPING',
    'GENERAL',
  ].includes(String(value))
    ? (value as
        | 'TECHNIQUE'
        | 'TACTICS'
        | 'ATHLETIC'
        | 'SOCIAL'
        | 'GOALKEEPING'
        | 'GENERAL')
    : 'GENERAL';
}

function validConsentType(value: unknown) {
  return ['PHOTO', 'TEAM_PHOTO', 'TRANSPORT', 'MEDICAL_DATA', 'COMMUNICATION'].includes(
    String(value),
  )
    ? (value as 'PHOTO' | 'TEAM_PHOTO' | 'TRANSPORT' | 'MEDICAL_DATA' | 'COMMUNICATION')
    : null;
}

function validConsentStatus(value: unknown) {
  return ['GRANTED', 'REVOKED', 'EXPIRED'].includes(String(value))
    ? (value as 'GRANTED' | 'REVOKED' | 'EXPIRED')
    : 'PENDING';
}
