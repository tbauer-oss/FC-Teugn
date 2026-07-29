import { randomUUID } from 'crypto';
import { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import {
  buildTransitionTeamPlans,
  TransitionTeamOverride,
} from '../services/season-transition';

async function organizationForUser(teamId: string) {
  return prisma.team.findUnique({
    where: { id: teamId },
    include: {
      ageGroup: {
        include: {
          season: { include: { club: true } },
        },
      },
    },
  });
}
export async function previewSeasonTransition(req: Request, res: Response) {
  const user = req.user!;
  const {
    name,
    startDate,
    endDate,
    idempotencyKey,
    teams: overrides = [],
    archivePlayerIds = [],
  } = req.body as {
    name?: string;
    startDate?: string;
    endDate?: string;
    idempotencyKey?: string;
    teams?: TransitionTeamOverride[];
    archivePlayerIds?: string[];
  };

  if (!name?.trim() || !startDate || !endDate) {
    return res.status(400).json({ message: 'Name, Beginn und Ende der neuen Saison sind erforderlich.' });
  }
  const parsedStart = new Date(startDate);
  const parsedEnd = new Date(endDate);
  if (
    Number.isNaN(parsedStart.getTime()) ||
    Number.isNaN(parsedEnd.getTime()) ||
    parsedEnd <= parsedStart
  ) {
    return res.status(400).json({ message: 'Der Saisonzeitraum ist ungültig.' });
  }

  const current = await organizationForUser(user.teamId);
  if (!current) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  const sourceSeason = current.ageGroup.season;
  const key = idempotencyKey?.trim() || randomUUID();
  const existing = await prisma.seasonTransition.findUnique({ where: { idempotencyKey: key } });
  if (existing) {
    if (existing.clubId !== sourceSeason.clubId) {
      return res.status(409).json({ message: 'Der Idempotenzschlüssel wird bereits verwendet.' });
    }
    return res.json(existing);
  }

  const duplicateSeason = await prisma.season.findUnique({
    where: { clubId_name: { clubId: sourceSeason.clubId, name: name.trim() } },
  });
  if (duplicateSeason) {
    return res.status(409).json({ message: 'Eine Saison mit diesem Namen existiert bereits.' });
  }

  const sourceTeams = await prisma.team.findMany({
    where: { isActive: true, ageGroup: { seasonId: sourceSeason.id } },
    orderBy: [{ ageGroup: { sortOrder: 'asc' } }, { name: 'asc' }],
    include: {
      ageGroup: true,
      players: { select: { id: true, status: true } },
      memberships: {
        where: { status: 'APPROVED' },
        select: { id: true },
      },
    },
  });
  const sourceTeamIds = new Set(sourceTeams.map((team) => team.id));
  if (overrides.some((item) => !sourceTeamIds.has(item.sourceTeamId))) {
    return res.status(400).json({ message: 'Mindestens eine Mannschaft gehört nicht zur aktiven Saison.' });
  }

  const teamPlans = buildTransitionTeamPlans(
    sourceTeams.map((team) => ({
      id: team.id,
      name: team.name,
      shortName: team.shortName,
      level: team.level,
      ageGroup: { code: team.ageGroup.code, name: team.ageGroup.name },
      playerCount: team.players.length,
      activePlayerCount: team.players.filter((player) => player.status !== 'LEFT').length,
      staffCount: team.memberships.length,
    })),
    overrides,
  );
  const validPlayerIds = new Set(sourceTeams.flatMap((team) => team.players.map((player) => player.id)));
  if (archivePlayerIds.some((id) => !validPlayerIds.has(id))) {
    return res.status(400).json({ message: 'Mindestens ein zu archivierender Spieler gehört nicht zum Verein.' });
  }

  const plan = {
    targetSeason: {
      name: name.trim(),
      startDate: parsedStart.toISOString(),
      endDate: parsedEnd.toISOString(),
    },
    teams: teamPlans,
    archivePlayerIds: [...new Set(archivePlayerIds)],
  };
  const preview = {
    sourceSeason: { id: sourceSeason.id, name: sourceSeason.name },
    targetSeason: plan.targetSeason,
    teams: teamPlans,
    totals: {
      teams: teamPlans.length,
      playersToMove: teamPlans.reduce(
        (sum, team) => sum + (team.includePlayers ? team.activePlayerCount : 0),
        0,
      ) - archivePlayerIds.length,
      playersToArchive:
        teamPlans.reduce((sum, team) => sum + team.archivedPlayerCount, 0) +
        archivePlayerIds.length,
      membershipsToCopy: teamPlans.reduce(
        (sum, team) => sum + (team.includeStaff ? team.staffCount : 0),
        0,
      ),
    },
    warnings: teamPlans
      .filter((team) => team.sourceAgeGroupCode === 'A' && team.targetAgeGroupCode === 'A')
      .map((team) => `${team.sourceName}: A-Jugend bleibt A-Jugend; Abgänge bitte archivieren.`),
  };

  const transition = await prisma.seasonTransition.create({
    data: {
      clubId: sourceSeason.clubId,
      sourceSeasonId: sourceSeason.id,
      actorId: user.id,
      idempotencyKey: key,
      plan: plan as Prisma.InputJsonValue,
      preview: preview as Prisma.InputJsonValue,
    },
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: user.teamId,
      action: 'SEASON_TRANSITION_PREVIEWED',
      entityType: 'SeasonTransition',
      entityId: transition.id,
      metadata: preview as Prisma.InputJsonValue,
    },
  });
  return res.status(201).json(transition);
}

export async function listSeasonTransitions(req: Request, res: Response) {
  const current = await organizationForUser(req.user!.teamId);
  if (!current) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  const transitions = await prisma.seasonTransition.findMany({
    where: { clubId: current.ageGroup.season.clubId },
    orderBy: { createdAt: 'desc' },
    take: 20,
    include: {
      actor: { select: { id: true, name: true } },
      sourceSeason: { select: { id: true, name: true } },
      targetSeason: { select: { id: true, name: true } },
    },
  });
  return res.json(transitions);
}

export async function applySeasonTransition(req: Request, res: Response) {
  const user = req.user!;
  const current = await organizationForUser(user.teamId);
  if (!current) return res.status(404).json({ message: 'Verein nicht gefunden.' });
  const transition = await prisma.seasonTransition.findFirst({
    where: { id: req.params.id, clubId: current.ageGroup.season.clubId },
  });
  if (!transition) return res.status(404).json({ message: 'Saisonwechsel nicht gefunden.' });
  if (transition.status === 'APPLIED') return res.json(transition);

  const plan = transition.plan as {
    targetSeason: { name: string; startDate: string; endDate: string };
    teams: Array<{
      sourceTeamId: string;
      targetAgeGroupCode: string;
      targetName: string;
      shortName: string | null;
      level: string | null;
      includePlayers: boolean;
      includeStaff: boolean;
    }>;
    archivePlayerIds: string[];
  };
  const archivePlayerIds = new Set(plan.archivePlayerIds);

  try {
    const completed = await prisma.$transaction(async (tx) => {
      const sourceSeason = await tx.season.findUnique({
        where: { id: transition.sourceSeasonId },
        include: {
          ageGroups: {
            include: {
              teams: {
                include: {
                  players: true,
                  memberships: { where: { status: 'APPROVED' } },
                  ruleProfiles: { where: { approvedAt: { not: null } } },
                },
              },
            },
          },
        },
      });
      if (!sourceSeason || sourceSeason.clubId !== transition.clubId) {
        throw new Error('Die Ausgangssaison ist nicht mehr verfügbar.');
      }
      const duplicate = await tx.season.findUnique({
        where: {
          clubId_name: { clubId: transition.clubId, name: plan.targetSeason.name },
        },
      });
      if (duplicate) throw new Error('Die Zielsaison existiert bereits.');

      await tx.season.updateMany({
        where: { clubId: transition.clubId, isActive: true },
        data: { isActive: false },
      });
      const targetSeason = await tx.season.create({
        data: {
          clubId: transition.clubId,
          name: plan.targetSeason.name,
          startDate: new Date(plan.targetSeason.startDate),
          endDate: new Date(plan.targetSeason.endDate),
          isActive: true,
        },
      });

      const sourceAgeGroups = new Map(
        sourceSeason.ageGroups.map((ageGroup) => [ageGroup.code.toUpperCase(), ageGroup]),
      );
      const requiredCodes = new Set([
        ...sourceAgeGroups.keys(),
        ...plan.teams.map((team) => team.targetAgeGroupCode.toUpperCase()),
      ]);
      const targetAgeGroups = new Map<string, string>();
      for (const [index, code] of [...requiredCodes].sort().entries()) {
        const source = sourceAgeGroups.get(code);
        const created = await tx.ageGroup.create({
          data: {
            seasonId: targetSeason.id,
            code,
            name: source?.name || `${code}-Jugend`,
            sortOrder: source?.sortOrder ?? index,
          },
        });
        targetAgeGroups.set(code, created.id);
      }

      const allSourceTeams = sourceSeason.ageGroups.flatMap((ageGroup) => ageGroup.teams);
      const sourceTeamById = new Map(allSourceTeams.map((team) => [team.id, team]));
      const teamMapping: Record<string, string> = {};
      let movedPlayers = 0;
      let archivedPlayers = 0;
      let copiedMemberships = 0;
      let copiedRuleProfiles = 0;

      for (const teamPlan of plan.teams) {
        const sourceTeam = sourceTeamById.get(teamPlan.sourceTeamId);
        if (!sourceTeam) throw new Error(`Mannschaft ${teamPlan.sourceTeamId} wurde nicht gefunden.`);
        const targetAgeGroupId = targetAgeGroups.get(teamPlan.targetAgeGroupCode.toUpperCase());
        if (!targetAgeGroupId) throw new Error('Ziel-Altersklasse wurde nicht angelegt.');
        const targetTeam = await tx.team.create({
          data: {
            ageGroupId: targetAgeGroupId,
            name: teamPlan.targetName,
            shortName: teamPlan.shortName,
            level: teamPlan.level,
            gameFormat: sourceTeam.gameFormat,
          },
        });
        teamMapping[sourceTeam.id] = targetTeam.id;

        for (const player of sourceTeam.players) {
          const explicitlyArchived = archivePlayerIds.has(player.id);
          await tx.playerSeasonAssignment.upsert({
            where: {
              playerId_seasonId: { playerId: player.id, seasonId: sourceSeason.id },
            },
            create: {
              playerId: player.id,
              seasonId: sourceSeason.id,
              teamId: sourceTeam.id,
              status: player.status,
              assignedAt: player.joinedAt ?? player.createdAt,
              endedAt: new Date(plan.targetSeason.startDate),
            },
            update: { endedAt: new Date(plan.targetSeason.startDate), status: player.status },
          });
          if (explicitlyArchived || player.status === 'LEFT' || !teamPlan.includePlayers) {
            if (explicitlyArchived) await tx.player.update({ where: { id: player.id }, data: { status: 'LEFT' } });
            archivedPlayers += 1;
            continue;
          }
          await tx.playerSeasonAssignment.create({
            data: {
              playerId: player.id,
              seasonId: targetSeason.id,
              teamId: targetTeam.id,
              status: player.status,
              assignedAt: new Date(plan.targetSeason.startDate),
            },
          });
          await tx.player.update({ where: { id: player.id }, data: { teamId: targetTeam.id } });
          movedPlayers += 1;
        }

        if (teamPlan.includeStaff) {
          for (const membership of sourceTeam.memberships) {
            await tx.teamMembership.upsert({
              where: { userId_teamId: { userId: membership.userId, teamId: targetTeam.id } },
              create: {
                userId: membership.userId,
                teamId: targetTeam.id,
                role: membership.role,
                status: membership.status,
              },
              update: { role: membership.role, status: membership.status },
            });
            await tx.user.updateMany({
              where: { id: membership.userId, teamId: sourceTeam.id },
              data: { teamId: targetTeam.id },
            });
            copiedMemberships += 1;
          }
        }
        for (const profile of sourceTeam.ruleProfiles) {
          await tx.ruleProfile.create({
            data: {
              teamId: targetTeam.id,
              name: profile.name,
              validFrom: new Date(plan.targetSeason.startDate),
              validUntil: new Date(plan.targetSeason.endDate),
              gameFormat: profile.gameFormat,
              teamSize: profile.teamSize,
              maxSquadSize: profile.maxSquadSize,
              periodCount: profile.periodCount,
              periodMinutes: profile.periodMinutes,
              substitutionsRolling: profile.substitutionsRolling,
              showResults: profile.showResults,
              showTable: profile.showTable,
              festivalMode: profile.festivalMode,
              sourceNote: profile.sourceNote,
              version: profile.version + 1,
              createdById: user.id,
            },
          });
          copiedRuleProfiles += 1;
        }
      }

      const result = {
        targetSeasonId: targetSeason.id,
        teamMapping,
        movedPlayers,
        archivedPlayers,
        copiedMemberships,
        copiedRuleProfiles,
      };
      await tx.auditLog.create({
        data: {
          actorId: user.id,
          teamId: teamMapping[user.teamId] ?? user.teamId,
          action: 'SEASON_TRANSITION_APPLIED',
          entityType: 'SeasonTransition',
          entityId: transition.id,
          metadata: result,
        },
      });
      return tx.seasonTransition.update({
        where: { id: transition.id },
        data: {
          status: 'APPLIED',
          targetSeasonId: targetSeason.id,
          result,
          appliedAt: new Date(),
        },
      });
    });
    return res.json(completed);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Saisonwechsel fehlgeschlagen.';
    await prisma.seasonTransition.update({
      where: { id: transition.id },
      data: { status: 'FAILED', result: { message } },
    });
    return res.status(409).json({ message });
  }
}
