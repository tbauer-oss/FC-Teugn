import { EventType, MatchKind, MatchStatus, Prisma } from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { Role } from '../types/enums';
import {
  accessibleTeamIds,
  eventTeamScope,
  ownPlayerIds,
} from '../services/team-access';
import {
  recalculateMatchStatistics,
  summarizeMatchResults,
} from '../services/statistics.service';

function date(value: unknown) {
  if (!value) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export async function statisticsOverview(req: Request, res: Response) {
  const user = req.user!;
  const accessible = await accessibleTeamIds(user);
  const requestedTeams = String(req.query.teamIds ?? '')
    .split(',')
    .filter((id) => accessible.includes(id));
  const teamIds = requestedTeams.length ? requestedTeams : accessible;
  const from = date(req.query.from);
  const to = date(req.query.to);
  const competition = String(req.query.competition ?? '').trim();
  const kind = String(req.query.kind ?? '').toUpperCase();
  const kindFilter = Object.values(MatchKind).includes(kind as MatchKind)
    ? (kind as MatchKind)
    : undefined;

  const matches = await prisma.event.findMany({
    where: {
      type: EventType.MATCH,
      ...eventTeamScope(teamIds),
      ...(from || to
        ? {
            startAt: {
              ...(from ? { gte: from } : {}),
              ...(to ? { lte: to } : {}),
            },
          }
        : {}),
      matchDetails: {
        is: {
          status: { in: [MatchStatus.FINISHED, MatchStatus.RECORDED] },
          ...(competition
            ? { competition: { contains: competition, mode: 'insensitive' as const } }
            : {}),
          ...(kindFilter ? { kind: kindFilter } : {}),
        },
      },
    },
    include: {
      team: { select: { id: true, name: true, shortName: true } },
      matchDetails: true,
      teamMatchStatistic: true,
      playerMatchStats: {
        include: {
          player: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              preferredName: true,
              shirtNumber: true,
              teamId: true,
            },
          },
        },
      },
    },
    orderBy: { startAt: 'asc' },
  });

  const matchRows = matches.map((match) => {
    const ourGoals =
      match.teamMatchStatistic?.ourGoals ?? match.matchDetails?.ourGoals ?? 0;
    const theirGoals =
      match.teamMatchStatistic?.theirGoals ?? match.matchDetails?.theirGoals ?? 0;
    const result =
      match.teamMatchStatistic?.result ??
      (ourGoals > theirGoals ? 'WIN' : ourGoals < theirGoals ? 'LOSS' : 'DRAW');
    return {
      id: match.id,
      team: match.team,
      startAt: match.startAt,
      opponent: match.matchDetails?.opponent,
      competition: match.matchDetails?.competition,
      kind: match.matchDetails?.kind,
      isHome: match.matchDetails?.isHome ?? true,
      ourGoals,
      theirGoals,
      result,
    };
  });

  const teamSummary = summarizeMatchResults(matchRows);

  const allowedPlayerIds = hasPermission(
    user.role as Role,
    Permission.MANAGE_STATISTICS,
  )
    ? null
    : new Set(await ownPlayerIds(user));
  const aggregated = new Map<
    string,
    {
      id: string;
      name: string;
      shirtNumber: number | null;
      appearances: number;
      starts: number;
      minutes: number;
      goals: number;
      assists: number;
    }
  >();
  for (const match of matches) {
    for (const stat of match.playerMatchStats) {
      if (allowedPlayerIds && !allowedPlayerIds.has(stat.playerId)) continue;
      const current = aggregated.get(stat.playerId) ?? {
        id: stat.playerId,
        name:
          stat.player.preferredName ||
          `${stat.player.firstName} ${stat.player.lastName}`,
        shirtNumber: stat.player.shirtNumber,
        appearances: 0,
        starts: 0,
        minutes: 0,
        goals: 0,
        assists: 0,
      };
      current.appearances += stat.appeared ? 1 : 0;
      current.starts += stat.started ? 1 : 0;
      current.minutes += stat.minutesPlayed;
      current.goals += stat.goals;
      current.assists += stat.assists;
      aggregated.set(stat.playerId, current);
    }
  }

  const trainingAttendance = await prisma.attendance.groupBy({
    by: ['playerId', 'actualAttendance'],
    where: {
      event: {
        type: EventType.TRAINING,
        ...eventTeamScope(teamIds),
        ...(from || to
          ? {
              startAt: {
                ...(from ? { gte: from } : {}),
                ...(to ? { lte: to } : {}),
              },
            }
          : {}),
      },
      ...(allowedPlayerIds ? { playerId: { in: [...allowedPlayerIds] } } : {}),
      actualAttendance: { not: null },
    },
    _count: true,
  });

  return res.json({
    filters: { teamIds, from, to, competition: competition || null, kind: kindFilter },
    team: teamSummary,
    matches: matchRows.reverse(),
    players: [...aggregated.values()].sort(
      (a, b) => b.appearances - a.appearances || a.name.localeCompare(b.name),
    ),
    trainingAttendance,
    privacy: {
      individualScope: allowedPlayerIds ? 'OWN_PLAYERS' : 'ASSIGNED_TEAMS',
      publicRanking: false,
    },
  });
}

export async function recalculateMatch(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const event = await prisma.event.findFirst({
    where: { id: req.params.matchId, type: EventType.MATCH, ...eventTeamScope(teamIds) },
    select: { id: true, teamId: true },
  });
  if (!event) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  try {
    const result = await recalculateMatchStatistics(event.id);
    await prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: event.teamId,
        action: 'MATCH_STATISTICS_RECALCULATED',
        entityType: 'Event',
        entityId: event.id,
        metadata: {
          result: result.result,
          playerCount: result.playerStatistics.length,
        } as Prisma.InputJsonValue,
      },
    });
    return res.json(result);
  } catch {
    return res.status(400).json({ message: 'Statistiken konnten nicht berechnet werden.' });
  }
}
