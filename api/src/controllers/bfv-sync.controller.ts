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

function validatedWidgetTeamId(value: unknown) {
  const teamId = optionalText(value, 160);
  if (teamId && !/^[A-Za-z0-9_-]{6,160}$/.test(teamId)) {
    throw new Error('Die BfV-Widget-Mannschaftskennung ist ungültig.');
  }
  return teamId;
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
    select: {
      id: true,
      name: true,
      bfvTeamId: true,
      bfvTeamUrl: true,
      bfvSyncConfig: true,
    },
  });
  if (!team) return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });
  const config = team.bfvSyncConfig ?? {
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
  };
  return res.json({ ...config, widgetTeamId: team.bfvTeamId });
}

export async function saveBfvSyncConfig(req: Request, res: Response) {
  const teamId = await requireTeamAccess(req, res);
  if (!teamId) return;
  const teamPageUrl = optionalText(req.body?.teamPageUrl, 1000);
  const icalUrl = optionalText(req.body?.icalUrl, 1500);
  const officialViewUrl = optionalText(req.body?.officialViewUrl, 1500) ?? teamPageUrl;
  let widgetTeamId: string | null = null;
  try {
    widgetTeamId = validatedWidgetTeamId(req.body?.widgetTeamId);
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
    await tx.team.update({
      where: { id: teamId },
      data: { bfvTeamId: widgetTeamId, bfvTeamUrl: teamPageUrl },
    });
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
      metadata: {
        enabled: config.enabled,
        syncIntervalMinutes,
        hasIcalUrl: Boolean(icalUrl),
        hasWidgetTeamId: Boolean(widgetTeamId),
      },
    },
  });
  return res.json({ ...config, widgetTeamId });
}

async function persistedBfvWidgetTeamIds() {
  const teams = await prisma.team.findMany({
    where: {
      deletedAt: null,
      isActive: true,
    },
    select: {
      id: true,
      bfvTeamId: true,
    },
  });
  return teams.map((team) => ({
    teamId: team.id,
    widgetTeamId: team.bfvTeamId,
  }));
}

export async function listBfvWidgetTeamIds(_req: Request, res: Response) {
  return res.json({ teams: await persistedBfvWidgetTeamIds() });
}

export async function saveBfvWidgetTeamIds(req: Request, res: Response) {
  const rawTeams = req.body?.teams;
  if (!Array.isArray(rawTeams) || rawTeams.length > 100) {
    return res.status(400).json({
      message: 'Bitte gültige Mannschaftskennungen übermitteln.',
    });
  }

  const teams: Array<{ teamId: string; widgetTeamId: string | null }> = [];
  const seenTeamIds = new Set<string>();
  try {
    for (const raw of rawTeams) {
      const teamId = optionalText(raw?.teamId, 100);
      if (!teamId || seenTeamIds.has(teamId)) {
        return res.status(400).json({
          message: 'Eine Mannschaft fehlt oder wurde doppelt übermittelt.',
        });
      }
      seenTeamIds.add(teamId);
      teams.push({
        teamId,
        widgetTeamId: validatedWidgetTeamId(raw?.widgetTeamId),
      });
    }
  } catch (error) {
    return res.status(400).json({
      message: error instanceof Error
        ? error.message
        : 'Eine BfV-Mannschaftskennung ist ungültig.',
    });
  }

  const existingTeams = await prisma.team.findMany({
    where: {
      id: { in: teams.map((team) => team.teamId) },
      deletedAt: null,
    },
    select: { id: true },
  });
  if (existingTeams.length !== teams.length) {
    return res.status(400).json({
      message: 'Mindestens eine Mannschaft ist nicht mehr verfügbar.',
    });
  }

  if (teams.length) {
    await prisma.$transaction(
      teams.map((team) => prisma.team.update({
        where: { id: team.teamId },
        data: { bfvTeamId: team.widgetTeamId },
      })),
    );
  }

  await prisma.auditLog.create({
    data: {
      actorId: req.user!.id,
      action: 'BFV_WIDGET_TEAM_IDS_UPDATED',
      entityType: 'Team',
      entityId: 'BFV_WIDGET_TEAM_IDS',
      metadata: {
        teamCount: teams.length,
        configuredCount: teams.filter((team) => Boolean(team.widgetTeamId)).length,
        teamIds: teams.map((team) => team.teamId),
      },
    },
  });

  // Return the authoritative persisted state, not merely the submitted body.
  // The central editor can therefore confirm the assignment and never falls
  // back to a stale organization snapshot after saving.
  return res.json({ teams: await persistedBfvWidgetTeamIds() });
}

export async function runBfvSync(req: Request, res: Response) {
  const teamId = await requireTeamAccess(req, res);
  if (!teamId) return;
  const config = await runBfvTeamSync(teamId);
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: { bfvTeamId: true },
  });
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
  return res.json({ ...config, widgetTeamId: team?.bfvTeamId ?? null });
}
