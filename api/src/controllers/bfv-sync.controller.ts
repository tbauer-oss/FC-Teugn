import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds } from '../services/team-access';
import {
  runBfvTeamSync,
  validatedBfvIcalUrl,
  validatedBfvViewUrl,
} from '../services/bfv-sync.service';

function optionalText(value: unknown, max = 1000) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, max) : null;
}

async function requireTeamAccess(req: Request, res: Response) {
  const teamId = optionalText(req.query.teamId ?? req.params.teamId ?? req.body?.teamId, 100);
  if (!teamId) {
    res.status(400).json({ message: 'Mannschaft fehlt.' });
    return null;
  }
  if (!(await accessibleTeamIds(req.user!)).includes(teamId)) {
    res.status(403).json({ message: 'Kein Zugriff auf diese Mannschaft.' });
    return null;
  }
  return teamId;
}

export async function getBfvSyncConfig(req: Request, res: Response) {
  const teamId = await requireTeamAccess(req, res);
  if (!teamId) return;
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: { id: true, name: true, bfvTeamUrl: true, bfvSyncConfig: true },
  });
  if (!team) return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  return res.json(team.bfvSyncConfig ?? {
    teamId,
    teamPageUrl: team.bfvTeamUrl,
    icalUrl: null,
    officialViewUrl: team.bfvTeamUrl,
    enabled: true,
    syncIntervalMinutes: 30,
    lastStatus: 'NOT_CONFIGURED',
    lastMessage: null,
    lastCreatedCount: 0,
    lastUpdatedCount: 0,
    lastSkippedCount: 0,
    lastConflictCount: 0,
  });
}

export async function saveBfvSyncConfig(req: Request, res: Response) {
  const teamId = await requireTeamAccess(req, res);
  if (!teamId) return;
  const teamPageUrl = optionalText(req.body?.teamPageUrl, 1000);
  const icalUrl = optionalText(req.body?.icalUrl, 1500);
  const officialViewUrl = optionalText(req.body?.officialViewUrl, 1500) ?? teamPageUrl;
  try {
    if (teamPageUrl) validatedBfvViewUrl(teamPageUrl);
    if (icalUrl) validatedBfvIcalUrl(icalUrl);
    if (officialViewUrl) validatedBfvViewUrl(officialViewUrl);
  } catch (error) {
    return res.status(400).json({
      message: error instanceof Error ? error.message : 'Ungültige BfV-Adresse.',
    });
  }
  const syncIntervalMinutes = Math.max(
    15,
    Math.min(1440, Number(req.body?.syncIntervalMinutes) || 30),
  );
  const config = await prisma.$transaction(async (tx) => {
    await tx.team.update({ where: { id: teamId }, data: { bfvTeamUrl: teamPageUrl } });
    return tx.bfvTeamSync.upsert({
      where: { teamId },
      update: {
        teamPageUrl,
        icalUrl,
        officialViewUrl,
        enabled: req.body?.enabled !== false,
        syncIntervalMinutes,
        ...(icalUrl ? {} : { lastStatus: 'NOT_CONFIGURED', lastMessage: null }),
      },
      create: {
        teamId,
        teamPageUrl,
        icalUrl,
        officialViewUrl,
        enabled: req.body?.enabled !== false,
        syncIntervalMinutes,
        createdById: req.user!.id,
        lastStatus: icalUrl ? 'READY' : 'NOT_CONFIGURED',
      },
    });
  });
  await prisma.auditLog.create({
    data: {
      actorId: req.user!.id,
      teamId,
      action: 'BFV_SYNC_CONFIG_UPDATED',
      entityType: 'BfvTeamSync',
      entityId: config.id,
      metadata: { enabled: config.enabled, syncIntervalMinutes, hasIcalUrl: Boolean(icalUrl) },
    },
  });
  return res.json(config);
}

export async function runBfvSync(req: Request, res: Response) {
  const teamId = await requireTeamAccess(req, res);
  if (!teamId) return;
  const config = await runBfvTeamSync(teamId);
  await prisma.auditLog.create({
    data: {
      actorId: req.user!.id,
      teamId,
      action: 'BFV_SYNC_RUN',
      entityType: 'BfvTeamSync',
      entityId: config.id,
      metadata: {
        status: config.lastStatus,
        created: config.lastCreatedCount,
        updated: config.lastUpdatedCount,
        conflicts: config.lastConflictCount,
      },
    },
  });
  return res.json(config);
}
