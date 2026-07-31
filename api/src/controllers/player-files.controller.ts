import { createHash, randomUUID } from 'crypto';
import { Request, Response } from 'express';
import {
  ConsentStatus,
  PlayerDocumentType,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Permission, hasPermission } from '../security/permissions';
import { Role } from '../types/enums';
import { objectStorage } from '../services/object-storage';
import { mediaAssetUrl } from '../services/media-access';
import { canAccessPlayer } from './players.controller';

const imageTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

async function fileCapabilities(req: Request, playerId: string) {
  if (!(await canAccessPlayer(req, playerId))) return null;
  const user = req.user!;
  const guardian = await prisma.parentPlayerLink.findUnique({
    where: { parentId_playerId: { parentId: user.id, playerId } },
  });
  const canView =
    hasPermission(user.role, Permission.VIEW_SENSITIVE_PLAYER) ||
    guardian?.isLegalGuardian === true ||
    user.role === Role.PLAYER;
  const canManage =
    hasPermission(user.role, Permission.MANAGE_DOCUMENTS) ||
    guardian?.isLegalGuardian === true;
  const canManagePhoto =
    hasPermission(user.role, Permission.MANAGE_PLAYERS) ||
    guardian?.isLegalGuardian === true;
  return { canView, canManage, canManagePhoto };
}
function safeFileStem(value: string) {
  return value
    .normalize('NFKD')
    .replace(/[^\w.-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'datei';
}

function checksum(buffer: Buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

async function assetResponse(asset: {
  id: string;
  pathname: string;
  originalName: string;
  contentType: string;
  size: number;
  createdAt: Date;
}) {
  return {
    id: asset.id,
    originalName: asset.originalName,
    contentType: asset.contentType,
    size: asset.size,
    createdAt: asset.createdAt,
    downloadUrl: mediaAssetUrl(asset.id),
  };
}

export async function uploadPlayerPhoto(req: Request, res: Response) {
  const playerId = req.params.id;
  const capabilities = await fileCapabilities(req, playerId);
  if (!capabilities?.canManagePhoto) {
    return res.status(403).json({ message: 'Spielerfoto darf nicht geändert werden.' });
  }
  if (!req.file || !imageTypes.has(req.file.mimetype)) {
    return res.status(400).json({ message: 'Bitte ein JPEG-, PNG- oder WebP-Bild auswählen.' });
  }

  const extension = req.file.mimetype === 'image/png'
    ? 'png'
    : req.file.mimetype === 'image/webp'
      ? 'webp'
      : 'jpg';
  const stored = await objectStorage.uploadPrivate(
    `players/${playerId}/photos/${randomUUID()}.${extension}`,
    req.file.buffer,
    req.file.mimetype,
  );
  let previousPathname: string | null = null;
  const asset = await prisma.$transaction(async (tx) => {
    const player = await tx.player.findUnique({
      where: { id: playerId },
      include: { photoAsset: true },
    });
    if (!player) throw new Error('Spieler nicht gefunden.');
    previousPathname = player.photoAsset?.pathname ?? null;
    const created = await tx.fileAsset.create({
      data: {
        kind: 'PLAYER_PHOTO',
        pathname: stored.pathname,
        storageUrl: stored.url,
        originalName: req.file!.originalname,
        contentType: req.file!.mimetype,
        size: req.file!.size,
        checksum: checksum(req.file!.buffer),
        uploadedById: req.user!.id,
        ownerPlayerId: playerId,
      },
    });
    await tx.player.update({
      where: { id: playerId },
      data: { photoAssetId: created.id, photoUrl: null },
    });
    if (player.photoAsset) {
      await tx.fileAsset.update({
        where: { id: player.photoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: player.teamId,
        action: 'PLAYER_PHOTO_REPLACED',
        entityType: 'FileAsset',
        entityId: created.id,
        metadata: {
          playerId,
          contentType: created.contentType,
          size: created.size,
          previousAssetId: player.photoAssetId,
        },
      },
    });
    return created;
  });
  if (previousPathname) {
    objectStorage.delete(previousPathname).catch(() => undefined);
  }
  return res.status(201).json(await assetResponse(asset));
}

export async function removePlayerPhoto(req: Request, res: Response) {
  const playerId = req.params.id;
  const capabilities = await fileCapabilities(req, playerId);
  if (!capabilities?.canManagePhoto) {
    return res.status(403).json({ message: 'Spielerfoto darf nicht entfernt werden.' });
  }
  const result = await prisma.$transaction(async (tx) => {
    const player = await tx.player.findUnique({
      where: { id: playerId },
      include: { photoAsset: true },
    });
    if (!player) return null;
    await tx.player.update({
      where: { id: playerId },
      data: { photoAssetId: null, photoUrl: null },
    });
    if (player.photoAsset) {
      await tx.fileAsset.update({
        where: { id: player.photoAsset.id },
        data: { deletedAt: new Date() },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: player.teamId,
        action: 'PLAYER_PHOTO_REMOVED',
        entityType: 'Player',
        entityId: playerId,
      },
    });
    return player.photoAsset?.pathname ?? null;
  });
  if (result) objectStorage.delete(result).catch(() => undefined);
  return res.status(204).send();
}

export async function uploadPlayerDocument(req: Request, res: Response) {
  const playerId = req.params.id;
  const capabilities = await fileCapabilities(req, playerId);
  if (!capabilities?.canManage) {
    return res.status(403).json({ message: 'Dokumente dürfen nicht geändert werden.' });
  }
  if (!req.file) return res.status(400).json({ message: 'Bitte eine Datei auswählen.' });
  const type = req.body.type as PlayerDocumentType;
  const title = String(req.body.title ?? '').trim();
  if (!Object.values(PlayerDocumentType).includes(type) || !title) {
    return res.status(400).json({ message: 'Dokumenttyp und Titel sind erforderlich.' });
  }
  const status = Object.values(ConsentStatus).includes(req.body.status)
    ? req.body.status as ConsentStatus
    : ConsentStatus.PENDING;
  const validFrom = req.body.validFrom ? new Date(req.body.validFrom) : null;
  const validUntil = req.body.validUntil ? new Date(req.body.validUntil) : null;
  if (
    (validFrom && Number.isNaN(validFrom.getTime())) ||
    (validUntil && Number.isNaN(validUntil.getTime())) ||
    (validFrom && validUntil && validUntil < validFrom)
  ) {
    return res.status(400).json({ message: 'Der Gültigkeitszeitraum ist ungültig.' });
  }
  const latest = await prisma.playerDocument.findFirst({
    where: { playerId, type },
    orderBy: { version: 'desc' },
    select: { version: true },
  });
  const stored = await objectStorage.uploadPrivate(
    `players/${playerId}/documents/${type.toLowerCase()}/${randomUUID()}-${safeFileStem(req.file.originalname)}`,
    req.file.buffer,
    req.file.mimetype,
  );

  const document = await prisma.$transaction(async (tx) => {
    const player = await tx.player.findUnique({ where: { id: playerId } });
    if (!player) throw new Error('Spieler nicht gefunden.');
    const asset = await tx.fileAsset.create({
      data: {
        kind: 'PLAYER_DOCUMENT',
        pathname: stored.pathname,
        storageUrl: stored.url,
        originalName: req.file!.originalname,
        contentType: req.file!.mimetype,
        size: req.file!.size,
        checksum: checksum(req.file!.buffer),
        uploadedById: req.user!.id,
        ownerPlayerId: playerId,
      },
    });
    const created = await tx.playerDocument.create({
      data: {
        playerId,
        fileAssetId: asset.id,
        type,
        title,
        version: (latest?.version ?? 0) + 1,
        status,
        validFrom,
        validUntil,
        grantedBy: String(req.body.grantedBy ?? '').trim() || null,
        grantedAt:
          status === ConsentStatus.GRANTED
            ? req.body.grantedAt
              ? new Date(req.body.grantedAt)
              : new Date()
            : null,
        note: String(req.body.note ?? '').trim() || null,
      },
      include: { fileAsset: true },
    });
    await tx.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: player.teamId,
        action: 'PLAYER_DOCUMENT_UPLOADED',
        entityType: 'PlayerDocument',
        entityId: created.id,
        metadata: {
          playerId,
          type,
          version: created.version,
          status,
          fileAssetId: asset.id,
        },
      },
    });
    return created;
  });
  return res.status(201).json(await serializeDocument(document));
}

export async function listPlayerDocuments(req: Request, res: Response) {
  const playerId = req.params.id;
  const capabilities = await fileCapabilities(req, playerId);
  if (!capabilities?.canView) {
    return res.status(403).json({ message: 'Dokumente dürfen nicht angezeigt werden.' });
  }
  const documents = await prisma.playerDocument.findMany({
    where: { playerId, fileAsset: { deletedAt: null } },
    orderBy: [{ type: 'asc' }, { version: 'desc' }],
    include: { fileAsset: true },
  });
  return res.json(await Promise.all(documents.map(serializeDocument)));
}

export async function deletePlayerDocument(req: Request, res: Response) {
  const playerId = req.params.id;
  const capabilities = await fileCapabilities(req, playerId);
  if (!capabilities?.canManage) {
    return res.status(403).json({ message: 'Dokumente dürfen nicht entfernt werden.' });
  }
  const document = await prisma.playerDocument.findFirst({
    where: { id: req.params.documentId, playerId },
    include: { fileAsset: true, player: true },
  });
  if (!document) return res.status(404).json({ message: 'Dokument nicht gefunden.' });
  await prisma.$transaction([
    prisma.fileAsset.update({
      where: { id: document.fileAssetId },
      data: { deletedAt: new Date() },
    }),
    prisma.auditLog.create({
      data: {
        actorId: req.user!.id,
        teamId: document.player.teamId,
        action: 'PLAYER_DOCUMENT_REMOVED',
        entityType: 'PlayerDocument',
        entityId: document.id,
        metadata: { playerId, fileAssetId: document.fileAssetId },
      },
    }),
  ]);
  objectStorage.delete(document.fileAsset.pathname).catch(() => undefined);
  return res.status(204).send();
}

async function serializeDocument(document: {
  id: string;
  type: PlayerDocumentType;
  title: string;
  version: number;
  status: ConsentStatus;
  validFrom: Date | null;
  validUntil: Date | null;
  grantedBy: string | null;
  grantedAt: Date | null;
  note: string | null;
  createdAt: Date;
  fileAsset: {
    id: string;
    pathname: string;
    originalName: string;
    contentType: string;
    size: number;
    createdAt: Date;
  };
}) {
  return {
    id: document.id,
    type: document.type,
    title: document.title,
    version: document.version,
    status: document.status,
    validFrom: document.validFrom,
    validUntil: document.validUntil,
    grantedBy: document.grantedBy,
    grantedAt: document.grantedAt,
    note: document.note,
    createdAt: document.createdAt,
    file: await assetResponse(document.fileAsset),
  };
}
