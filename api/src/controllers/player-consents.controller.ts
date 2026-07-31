import { createHash } from 'crypto';
import { ConsentStatus, ConsentType } from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { accessibleTeamIds } from '../services/team-access';
import { buildConsentPdf } from '../services/consent-pdf';
import {
  consentTemplate,
  publicConsentTemplates,
} from '../services/consent-templates';
import { Role } from '../types/enums';

type SignatureData = {
  width: number;
  height: number;
  strokes: Array<Array<{ x: number; y: number }>>;
};

function parsedType(value: unknown) {
  return Object.values(ConsentType).includes(value as ConsentType)
    ? (value as ConsentType)
    : null;
}

function signature(value: unknown): SignatureData | null {
  if (!value || typeof value !== 'object') return null;
  const data = value as Partial<SignatureData>;
  if (
    typeof data.width !== 'number' ||
    typeof data.height !== 'number' ||
    data.width <= 0 ||
    data.height <= 0 ||
    !Array.isArray(data.strokes)
  ) {
    return null;
  }
  const strokes = data.strokes
    .filter(Array.isArray)
    .map((stroke) =>
      stroke
        .filter(
          (point) =>
            point &&
            typeof point === 'object' &&
            Number.isFinite((point as { x?: number }).x) &&
            Number.isFinite((point as { y?: number }).y),
        )
        .slice(0, 500)
        .map((point) => ({
          x: Math.max(0, Math.min(data.width!, Number((point as { x: number }).x))),
          y: Math.max(0, Math.min(data.height!, Number((point as { y: number }).y))),
        })),
    )
    .filter((stroke) => stroke.length >= 2)
    .slice(0, 20);
  const pointCount = strokes.reduce((sum, stroke) => sum + stroke.length, 0);
  return pointCount >= 8
    ? { width: data.width, height: data.height, strokes }
    : null;
}

async function access(req: Request, playerId: string) {
  const user = req.user!;
  const [player, guardian, currentUser] = await Promise.all([
    prisma.player.findUnique({
      where: { id: playerId },
      select: {
        id: true,
        teamId: true,
        userId: true,
        firstName: true,
        lastName: true,
        birthDate: true,
      },
    }),
    prisma.parentPlayerLink.findUnique({
      where: { parentId_playerId: { parentId: user.id, playerId } },
      select: { isLegalGuardian: true, relationship: true },
    }),
    prisma.user.findUnique({
      where: { id: user.id },
      select: { id: true, name: true, role: true },
    }),
  ]);
  if (!player || !currentUser) return null;
  const teamIds = await accessibleTeamIds(user);
  const staffAccess =
    hasPermission(user.role, Permission.VIEW_SENSITIVE_PLAYER) &&
    (user.role === Role.SUPER_ADMIN ||
      (player.teamId !== null && teamIds.includes(player.teamId)));
  const ownPlayer = player.userId === user.id;
  const canView = staffAccess || guardian?.isLegalGuardian === true || ownPlayer;
  if (!canView) return null;
  return {
    player,
    currentUser,
    canSign: guardian?.isLegalGuardian === true,
    guardianRelationship: guardian?.relationship ?? null,
    canManage: hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER),
  };
}

function safeFilename(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9_-]+/g, '-')
    .replace(/^-|-$/g, '');
}

function pdfResponse(res: Response, bytes: Uint8Array, filename: string) {
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader(
    'Content-Disposition',
    `attachment; filename="${safeFilename(filename)}.pdf"`,
  );
  res.setHeader('Cache-Control', 'private, no-store');
  return res.send(Buffer.from(bytes));
}

export async function listConsentTemplates(req: Request, res: Response) {
  return res.json(publicConsentTemplates());
}

export async function downloadConsentTemplate(req: Request, res: Response) {
  const type = parsedType(req.params.type);
  if (!type) return res.status(404).json({ message: 'Einwilligungsvorlage nicht gefunden.' });
  const template = consentTemplate(type);
  const bytes = await buildConsentPdf({ template });
  return pdfResponse(res, bytes, `FC-Teugn-${template.shortTitle}-Vorlage`);
}

export async function signPlayerConsent(req: Request, res: Response) {
  const type = parsedType(req.params.type);
  if (!type) return res.status(400).json({ message: 'Unbekannte Einwilligungsart.' });
  const permission = await access(req, req.params.id);
  if (!permission) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  if (!permission.canSign) {
    return res.status(403).json({
      message:
        'Digital unterschreiben darf nur eine zugeordnete sorgeberechtigte Person. Vereinsverantwortliche können den Status einsehen, aber nicht stellvertretend einwilligen.',
    });
  }

  const template = consentTemplate(type);
  if (req.body?.templateVersion !== template.version) {
    return res.status(409).json({
      message: 'Die Vorlage wurde aktualisiert. Bitte Einwilligung erneut öffnen.',
    });
  }
  const selected: string[] = Array.isArray(req.body?.selections)
    ? Array.from(
        new Set<string>(
          req.body.selections.map((item: unknown) => String(item)),
        ),
      )
    : [];
  const allowed = new Set(template.options.map((option) => option.id));
  if (selected.length === 0 || selected.some((item) => !allowed.has(item))) {
    return res.status(400).json({ message: 'Bitte mindestens einen gültigen Umfang auswählen.' });
  }
  if (req.body?.guardianAuthorityConfirmed !== true) {
    return res.status(400).json({ message: 'Bitte Sorgeberechtigung bestätigen.' });
  }
  if (template.explicit && req.body?.explicitConsent !== true) {
    return res.status(400).json({
      message: 'Für Gesundheitsdaten ist eine ausdrückliche Einwilligung erforderlich.',
    });
  }
  const signatureData = signature(req.body?.signatureData);
  if (!signatureData) {
    return res.status(400).json({ message: 'Bitte vollständig im Unterschriftsfeld unterschreiben.' });
  }
  const now = new Date();
  const clientSignedAt =
    typeof req.body?.clientSignedAt === 'string' &&
    !Number.isNaN(new Date(req.body.clientSignedAt).valueOf())
      ? new Date(req.body.clientSignedAt)
      : null;
  const note: string | null =
    typeof req.body?.note === 'string' && req.body.note.trim()
      ? req.body.note.trim().slice(0, 1000)
      : null;
  const childAssentName: string | null =
    typeof req.body?.childAssentName === 'string' && req.body.childAssentName.trim()
      ? req.body.childAssentName.trim().slice(0, 160)
      : null;

  const statement = {
    type,
    templateVersion: template.version,
    selections: selected.sort(),
    note,
    explicitConsent: template.explicit ? true : req.body?.explicitConsent === true,
    guardianAuthorityConfirmed: true,
    playerId: permission.player.id,
    playerName: `${permission.player.firstName} ${permission.player.lastName}`,
    signerId: permission.currentUser.id,
    signerName: permission.currentUser.name,
    signerRelationship: permission.guardianRelationship,
    serverSignedAt: now.toISOString(),
  };
  const documentHash = createHash('sha256')
    .update(JSON.stringify(statement))
    .update(JSON.stringify(signatureData))
    .digest('hex');

  const consent = await prisma.$transaction(async (tx) => {
    const current = await tx.playerConsent.upsert({
      where: { playerId_type: { playerId: permission.player.id, type } },
      update: {
        status: ConsentStatus.GRANTED,
        grantedBy: permission.currentUser.id,
        grantedAt: now,
        revokedAt: null,
        expiresAt: null,
        note,
        templateVersion: template.version,
        currentHash: documentHash,
      },
      create: {
        playerId: permission.player.id,
        type,
        status: ConsentStatus.GRANTED,
        grantedBy: permission.currentUser.id,
        grantedAt: now,
        note,
        templateVersion: template.version,
        currentHash: documentHash,
      },
    });
    const evidence = await tx.playerConsentEvidence.create({
      data: {
        consentId: current.id,
        signerId: permission.currentUser.id,
        action: ConsentStatus.GRANTED,
        templateVersion: template.version,
        statement,
        signatureData,
        signerName: permission.currentUser.name,
        signerRole: permission.currentUser.role,
        guardianAuthorityConfirmed: true,
        childAssentName,
        documentHash,
        clientSignedAt,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: permission.currentUser.id,
        teamId: req.user!.teamId,
        action: 'PLAYER_CONSENT_DIGITALLY_SIGNED',
        entityType: 'PlayerConsent',
        entityId: current.id,
        metadata: {
          playerId: permission.player.id,
          type,
          templateVersion: template.version,
          documentHash,
          evidenceId: evidence.id,
        },
      },
    });
    return { ...current, evidence: [evidence] };
  });
  return res.status(201).json(consent);
}

export async function revokePlayerConsent(req: Request, res: Response) {
  const type = parsedType(req.params.type);
  if (!type) return res.status(400).json({ message: 'Unbekannte Einwilligungsart.' });
  const permission = await access(req, req.params.id);
  if (!permission) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  if (!permission.canSign && !permission.canManage) {
    return res.status(403).json({ message: 'Keine Berechtigung zum Widerruf.' });
  }
  const current = await prisma.playerConsent.findUnique({
    where: { playerId_type: { playerId: permission.player.id, type } },
  });
  if (!current) return res.status(404).json({ message: 'Keine Einwilligung vorhanden.' });
  const now = new Date();
  const reason =
    typeof req.body?.reason === 'string' && req.body.reason.trim()
      ? req.body.reason.trim().slice(0, 1000)
      : null;
  const statement = {
    type,
    previousHash: current.currentHash,
    reason,
    playerId: permission.player.id,
    signerId: permission.currentUser.id,
    revokedAt: now.toISOString(),
  };
  const documentHash = createHash('sha256')
    .update(JSON.stringify(statement))
    .digest('hex');
  const consent = await prisma.$transaction(async (tx) => {
    const updated = await tx.playerConsent.update({
      where: { id: current.id },
      data: {
        status: ConsentStatus.REVOKED,
        revokedAt: now,
        note: reason ?? current.note,
        currentHash: documentHash,
      },
    });
    await tx.playerConsentEvidence.create({
      data: {
        consentId: current.id,
        signerId: permission.currentUser.id,
        action: ConsentStatus.REVOKED,
        templateVersion: current.templateVersion ?? consentTemplate(type).version,
        statement,
        signerName: permission.currentUser.name,
        signerRole: permission.currentUser.role,
        guardianAuthorityConfirmed: permission.canSign,
        documentHash,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: permission.currentUser.id,
        teamId: req.user!.teamId,
        action: 'PLAYER_CONSENT_REVOKED',
        entityType: 'PlayerConsent',
        entityId: current.id,
        metadata: { playerId: permission.player.id, type, documentHash },
      },
    });
    return updated;
  });
  return res.json(consent);
}

export async function downloadConsentEvidence(req: Request, res: Response) {
  const type = parsedType(req.params.type);
  if (!type) return res.status(404).json({ message: 'Einwilligung nicht gefunden.' });
  const permission = await access(req, req.params.id);
  if (!permission) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  const evidence = await prisma.playerConsentEvidence.findFirst({
    where: {
      id: req.params.evidenceId,
      consent: { playerId: permission.player.id, type },
    },
    include: { consent: true },
  });
  if (!evidence) return res.status(404).json({ message: 'Nachweis nicht gefunden.' });
  const statement = evidence.statement as {
    selections?: string[];
    note?: string | null;
    signerRelationship?: string | null;
  };
  const signatureData = evidence.signatureData as SignatureData | null;
  const signerLink = evidence.signerId
    ? await prisma.parentPlayerLink.findUnique({
        where: {
          parentId_playerId: {
            parentId: evidence.signerId,
            playerId: permission.player.id,
          },
        },
        select: { relationship: true },
      })
    : null;
  const bytes = await buildConsentPdf({
    template: consentTemplate(type),
    playerName: `${permission.player.firstName} ${permission.player.lastName}`,
    playerBirthDate: permission.player.birthDate,
    signerName: evidence.signerName,
    signerRelationship:
      statement.signerRelationship ?? signerLink?.relationship ?? null,
    selections: statement.selections ?? [],
    note: statement.note,
    signedAt: evidence.createdAt,
    childAssentName: evidence.childAssentName,
    signature: signatureData,
    documentHash: evidence.documentHash,
    revokedAt:
      evidence.action === ConsentStatus.REVOKED ? evidence.createdAt : null,
  });
  return pdfResponse(
    res,
    bytes,
    `${consentTemplate(type).shortTitle}-${permission.player.lastName}-${evidence.createdAt.toISOString().slice(0, 10)}`,
  );
}
