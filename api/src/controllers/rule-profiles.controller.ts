import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

async function clubIdForUser(teamId: string) {
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: { ageGroup: { select: { season: { select: { clubId: true } } } } },
  });
  return team?.ageGroup.season.clubId ?? null;
}
export async function listRuleProfiles(req: Request, res: Response) {
  const clubId = await clubIdForUser(req.user!.teamId);
  if (!clubId) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  const teamId = typeof req.query.teamId === 'string' ? req.query.teamId : undefined;
  const profiles = await prisma.ruleProfile.findMany({
    where: {
      ...(teamId ? { teamId } : {}),
      team: { ageGroup: { season: { clubId } } },
    },
    orderBy: [{ team: { name: 'asc' } }, { name: 'asc' }, { version: 'desc' }],
    include: {
      team: { select: { id: true, name: true, ageGroup: { select: { code: true } } } },
      createdBy: { select: { id: true, name: true } },
      approvedBy: { select: { id: true, name: true } },
    },
  });
  return res.json(profiles);
}

export async function createRuleProfile(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await clubIdForUser(user.teamId);
  if (!clubId) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  const {
    teamId,
    name,
    validFrom,
    validUntil,
    gameFormat,
    teamSize,
    maxSquadSize,
    periodCount,
    periodMinutes,
    substitutionsRolling = true,
    showResults = true,
    showTable = true,
    festivalMode = false,
    sourceNote,
  } = req.body as Record<string, unknown>;

  if (
    typeof teamId !== 'string' ||
    typeof name !== 'string' ||
    typeof validFrom !== 'string' ||
    typeof gameFormat !== 'string' ||
    !Number.isInteger(teamSize) ||
    !Number.isInteger(periodCount) ||
    !Number.isInteger(periodMinutes)
  ) {
    return res.status(400).json({ message: 'Mannschaft, Name, Gültigkeit und Spielregeln sind erforderlich.' });
  }
  const parsedFrom = new Date(validFrom);
  const parsedUntil = typeof validUntil === 'string' && validUntil ? new Date(validUntil) : null;
  if (
    Number.isNaN(parsedFrom.getTime()) ||
    (parsedUntil && (Number.isNaN(parsedUntil.getTime()) || parsedUntil < parsedFrom))
  ) {
    return res.status(400).json({ message: 'Der Gültigkeitszeitraum ist ungültig.' });
  }
  if (
    (teamSize as number) < 1 ||
    (periodCount as number) < 1 ||
    (periodMinutes as number) < 1
  ) {
    return res.status(400).json({ message: 'Mannschaftsgröße und Spielzeit müssen positiv sein.' });
  }
  const team = await prisma.team.findFirst({
    where: { id: teamId, ageGroup: { season: { clubId } } },
  });
  if (!team) return res.status(404).json({ message: 'Mannschaft nicht gefunden.' });

  const latest = await prisma.ruleProfile.findFirst({
    where: { teamId, name: { equals: name.trim(), mode: 'insensitive' } },
    orderBy: { version: 'desc' },
    select: { version: true },
  });
  const profile = await prisma.$transaction(async (tx) => {
    const created = await tx.ruleProfile.create({
      data: {
        teamId,
        name: name.trim(),
        validFrom: parsedFrom,
        validUntil: parsedUntil,
        gameFormat: gameFormat.trim(),
        teamSize: teamSize as number,
        maxSquadSize: Number.isInteger(maxSquadSize) ? (maxSquadSize as number) : null,
        periodCount: periodCount as number,
        periodMinutes: periodMinutes as number,
        substitutionsRolling: substitutionsRolling !== false,
        showResults: showResults !== false,
        showTable: showTable !== false,
        festivalMode: festivalMode === true,
        sourceNote: typeof sourceNote === 'string' ? sourceNote.trim() || null : null,
        version: (latest?.version ?? 0) + 1,
        createdById: user.id,
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'RULE_PROFILE_CREATED',
        entityType: 'RuleProfile',
        entityId: created.id,
        metadata: { name: created.name, version: created.version },
      },
    });
    return created;
  });
  return res.status(201).json(profile);
}

export async function approveRuleProfile(req: Request, res: Response) {
  const user = req.user!;
  const clubId = await clubIdForUser(user.teamId);
  if (!clubId) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  const profile = await prisma.ruleProfile.findFirst({
    where: { id: req.params.id, team: { ageGroup: { season: { clubId } } } },
  });
  if (!profile) return res.status(404).json({ message: 'Regelprofil nicht gefunden.' });
  if (profile.approvedAt) return res.json(profile);

  const approved = await prisma.$transaction(async (tx) => {
    const updated = await tx.ruleProfile.update({
      where: { id: profile.id },
      data: { approvedAt: new Date(), approvedById: user.id },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: profile.teamId,
        action: 'RULE_PROFILE_APPROVED',
        entityType: 'RuleProfile',
        entityId: profile.id,
        metadata: { name: profile.name, version: profile.version },
      },
    });
    return updated;
  });
  return res.json(approved);
}
