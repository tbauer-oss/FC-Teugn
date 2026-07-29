import {
  EventType,
  MatchKind,
  MatchStatus,
  Prisma,
  TickerEventType,
} from '@prisma/client';
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

type PlayerStatisticRow = {
  id: string;
  name: string;
  shirtNumber: number | null;
  appearances: number;
  starts: number;
  minutes: number;
  goals: number;
  assists: number;
};

type PlayerIdentity = {
  id: string;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  shirtNumber: number | null;
};

export function canSelectStatisticsTeam(role: Role) {
  return (
    role === Role.SUPER_ADMIN ||
    role === Role.CLUB_ADMIN ||
    role === Role.TRAINER_ADMIN ||
    role === Role.YOUTH_DIRECTOR
  );
}

export function resolveStatisticsTeamIds(
  user: { role: Role; teamId: string },
  accessibleTeamIds: string[],
  requestedTeamIds: string[],
) {
  if (!canSelectStatisticsTeam(user.role)) {
    return accessibleTeamIds.includes(user.teamId) ? [user.teamId] : [];
  }
  if (requestedTeamIds.some((teamId) => !accessibleTeamIds.includes(teamId))) {
    return null;
  }
  if (requestedTeamIds.length > 0) {
    return [requestedTeamIds[0]];
  }
  if (accessibleTeamIds.includes(user.teamId)) {
    return [user.teamId];
  }
  return accessibleTeamIds.length > 0 ? [accessibleTeamIds[0]] : [];
}

function emptyPlayerStatistic(player: PlayerIdentity): PlayerStatisticRow {
  return {
    id: player.id,
    name: player.preferredName || `${player.firstName} ${player.lastName}`,
    shirtNumber: player.shirtNumber,
    appearances: 0,
    starts: 0,
    minutes: 0,
    goals: 0,
    assists: 0,
  };
}

export async function statisticsOverview(req: Request, res: Response) {
  const user = req.user!;
  const accessible = await accessibleTeamIds(user);
  const accessibleTeams = await prisma.team.findMany({
    where: { id: { in: accessible } },
    select: {
      id: true,
      ageGroup: {
        select: {
          season: {
            select: {
              id: true,
              name: true,
              startDate: true,
              endDate: true,
              isActive: true,
            },
          },
        },
      },
    },
  });
  const requestedTeams = String(req.query.teamIds ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);
  const baseTeamIds = resolveStatisticsTeamIds(
    { role: user.role as Role, teamId: user.teamId },
    accessible,
    requestedTeams,
  );
  if (baseTeamIds === null) {
    return res.status(403).json({ message: 'Mannschaft nicht freigegeben.' });
  }
  if (baseTeamIds.length === 0) {
    return res.status(404).json({ message: 'Keine Mannschaft verfügbar.' });
  }
  const availableSeasons = [
    ...new Map(
      accessibleTeams
        .filter((team) => baseTeamIds.includes(team.id))
        .map((team) => {
          const season = team.ageGroup.season;
          return [season.id, season] as const;
        }),
    ).values(),
  ].sort((a, b) => b.startDate.getTime() - a.startDate.getTime());
  const requestedSeasonId = String(req.query.seasonId ?? '').trim();
  const selectedSeason = requestedSeasonId
    ? availableSeasons.find((season) => season.id === requestedSeasonId)
    : null;
  if (requestedSeasonId && !selectedSeason) {
    return res.status(400).json({ message: 'Die ausgewählte Saison ist nicht verfügbar.' });
  }
  const teamIds = selectedSeason
    ? accessibleTeams
        .filter(
          (team) =>
            baseTeamIds.includes(team.id) &&
            team.ageGroup.season.id === selectedSeason.id,
        )
        .map((team) => team.id)
    : baseTeamIds;
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
          status: {
            in: [MatchStatus.LIVE, MatchStatus.HALF_TIME, MatchStatus.INTERRUPTED, MatchStatus.FINISHED, MatchStatus.RECORDED],
          },
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
  const aggregated = new Map<string, PlayerStatisticRow>();
  for (const match of matches) {
    for (const stat of match.playerMatchStats) {
      if (allowedPlayerIds && !allowedPlayerIds.has(stat.playerId)) continue;
      const current =
        aggregated.get(stat.playerId) ?? emptyPlayerStatistic(stat.player);
      current.appearances += stat.appeared ? 1 : 0;
      current.starts += stat.started ? 1 : 0;
      current.minutes += stat.minutesPlayed;
      current.goals += stat.goals;
      current.assists += stat.assists;
      aggregated.set(stat.playerId, current);
    }
  }
  // Goals and assists are read from the immutable ticker source of truth.
  // This also repairs the display for older matches whose projection failed
  // before automatic recalculation became reliable.
  for (const player of aggregated.values()) {
    player.goals = 0;
    player.assists = 0;
  }
  const goalEvents = await prisma.liveTickerEvent.findMany({
    where: {
      revokedAt: null,
      type: { in: [TickerEventType.HOME_GOAL, TickerEventType.AWAY_GOAL] },
      ticker: { eventId: { in: matches.map((match) => match.id) } },
    },
    include: {
      scorer: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
        },
      },
      assist: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
        },
      },
    },
  });
  const ensurePlayer = (player: PlayerIdentity) => {
    const current =
      aggregated.get(player.id) ?? emptyPlayerStatistic(player);
    aggregated.set(player.id, current);
    return current;
  };
  for (const event of goalEvents) {
    if (event.scorer && (!allowedPlayerIds || allowedPlayerIds.has(event.scorer.id))) {
      ensurePlayer(event.scorer).goals += 1;
    }
    if (event.assist && (!allowedPlayerIds || allowedPlayerIds.has(event.assist.id))) {
      ensurePlayer(event.assist).assists += 1;
    }
  }

  const careerMatchStats = await prisma.playerMatchStatistic.findMany({
    where: {
      event: {
        type: EventType.MATCH,
        ...eventTeamScope(baseTeamIds),
        matchDetails: {
          is: {
            status: {
              in: [
                MatchStatus.LIVE,
                MatchStatus.HALF_TIME,
                MatchStatus.INTERRUPTED,
                MatchStatus.FINISHED,
                MatchStatus.RECORDED,
              ],
            },
          },
        },
      },
      ...(allowedPlayerIds ? { playerId: { in: [...allowedPlayerIds] } } : {}),
    },
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
        },
      },
    },
  });
  const career = new Map<string, PlayerStatisticRow>();
  for (const stat of careerMatchStats) {
    const current =
      career.get(stat.playerId) ?? emptyPlayerStatistic(stat.player);
    current.appearances += stat.appeared ? 1 : 0;
    current.starts += stat.started ? 1 : 0;
    current.minutes += stat.minutesPlayed;
    career.set(stat.playerId, current);
  }
  const careerGoalEvents = await prisma.liveTickerEvent.findMany({
    where: {
      revokedAt: null,
      type: { in: [TickerEventType.HOME_GOAL, TickerEventType.AWAY_GOAL] },
      ticker: {
        event: {
          type: EventType.MATCH,
          ...eventTeamScope(baseTeamIds),
        },
      },
      ...(allowedPlayerIds
        ? {
            OR: [
              { scorerId: { in: [...allowedPlayerIds] } },
              { assistId: { in: [...allowedPlayerIds] } },
            ],
          }
        : {}),
    },
    include: {
      scorer: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
        },
      },
      assist: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
        },
      },
    },
  });
  const ensureCareerPlayer = (player: PlayerIdentity) => {
    const current = career.get(player.id) ?? emptyPlayerStatistic(player);
    career.set(player.id, current);
    return current;
  };
  for (const event of careerGoalEvents) {
    if (event.scorer && (!allowedPlayerIds || allowedPlayerIds.has(event.scorer.id))) {
      ensureCareerPlayer(event.scorer).goals += 1;
    }
    if (event.assist && (!allowedPlayerIds || allowedPlayerIds.has(event.assist.id))) {
      ensureCareerPlayer(event.assist).assists += 1;
    }
  }
  if (!selectedSeason && !from && !to) {
    for (const [playerId, statistic] of career) {
      aggregated.set(playerId, { ...statistic });
    }
  }
  const players = [...new Set([...aggregated.keys(), ...career.keys()])]
    .map((playerId) => {
      const careerStatistic = career.get(playerId);
      const scoped =
        aggregated.get(playerId) ??
        {
          ...careerStatistic!,
          appearances: 0,
          starts: 0,
          minutes: 0,
          goals: 0,
          assists: 0,
        };
      return {
        ...scoped,
        career: careerStatistic ?? scoped,
      };
    })
    .sort(
      (a, b) =>
        b.appearances - a.appearances ||
        b.goals - a.goals ||
        a.name.localeCompare(b.name),
    );

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
    filters: {
      teamIds,
      from,
      to,
      competition: competition || null,
      kind: kindFilter,
      seasonId: selectedSeason?.id ?? null,
    },
    seasons: availableSeasons,
    selectedSeason: selectedSeason ?? null,
    team: teamSummary,
    matches: matchRows.reverse(),
    players,
    trainingAttendance,
    privacy: {
      individualScope: allowedPlayerIds ? 'OWN_PLAYERS' : 'ASSIGNED_TEAMS',
      teamSelection: canSelectStatisticsTeam(user.role as Role)
        ? 'ADMIN_SELECTABLE'
        : 'REGISTRATION_TEAM',
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
