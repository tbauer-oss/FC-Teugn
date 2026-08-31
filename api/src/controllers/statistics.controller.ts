import {
  EventType,
  MatchKind,
  MatchStatus,
  Prisma,
  TickerStatus,
  TickerEventType,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hasEffectivePermission, Permission } from '../security/permissions';
import { Role } from '../types/enums';
import {
  accessibleTeamIds,
  contextualTeamIds,
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
  cleanSheets: number;
  cleanSheetEligible: boolean;
};

type PlayerIdentity = {
  id: string;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  shirtNumber: number | null;
  position?: string | null;
  secondaryPosition?: string | null;
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
    return accessibleTeamIds;
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

export function statisticsMatchLifecycleScope(): Prisma.EventWhereInput {
  return {
    OR: [
      {
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
      {
        liveTicker: {
          is: {
            status: {
              in: [
                TickerStatus.LIVE,
                TickerStatus.PAUSED,
                TickerStatus.HALF_TIME,
                TickerStatus.INTERRUPTED,
                TickerStatus.FINISHED,
              ],
            },
          },
        },
      },
    ],
  };
}

export function isStatisticsMatchFinished(match: {
  matchDetails?: { status: MatchStatus } | null;
  liveTicker?: { status: TickerStatus } | null;
}) {
  return match.matchDetails?.status === MatchStatus.FINISHED ||
    match.matchDetails?.status === MatchStatus.RECORDED ||
    match.liveTicker?.status === TickerStatus.FINISHED;
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
    cleanSheets: 0,
    cleanSheetEligible: isDefensivePlayer(
      player.position,
      player.secondaryPosition,
      false,
    ),
  };
}

export function isDefensivePlayer(
  position: string | null | undefined,
  secondaryPosition: string | null | undefined,
  isGoalkeeper: boolean,
) {
  if (isGoalkeeper) return true;
  const value = `${position ?? ''} ${secondaryPosition ?? ''}`.toLocaleUpperCase('de-DE');
  return /(^|\W)(TW|TORHÜTER|TORWART|IV|LV|RV|LIBERO|VERTEIDIGER|ABWEHR)(\W|$)/.test(value);
}

export async function statisticsOverview(req: Request, res: Response) {
  const user = req.user!;
  const accessible = await accessibleTeamIds(user);
  const contextual = await contextualTeamIds(user);
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
    requestedTeams.length ? accessible : contextual,
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
      AND: [
        eventTeamScope(teamIds),
        statisticsMatchLifecycleScope(),
      ],
      ...(from || to
        ? {
            startAt: {
              ...(from ? { gte: from } : {}),
              ...(to ? { lte: to } : {}),
            },
          }
        : {}),
      ...(competition || kindFilter
        ? {
            matchDetails: {
              is: {
                ...(competition
                  ? { competition: { contains: competition, mode: 'insensitive' as const } }
                  : {}),
                ...(kindFilter ? { kind: kindFilter } : {}),
              },
            },
          }
        : {}),
    },
    include: {
      team: { select: { id: true, name: true, shortName: true } },
      matchDetails: true,
      liveTicker: {
        select: {
          status: true,
          ourGoals: true,
          theirGoals: true,
        },
      },
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
              position: true,
              secondaryPosition: true,
            },
          },
        },
      },
    },
    orderBy: { startAt: 'asc' },
  });

  const matchRows = matches.map((match) => {
    const ourGoals =
      match.teamMatchStatistic?.ourGoals ??
      match.matchDetails?.ourGoals ??
      match.liveTicker?.ourGoals ??
      0;
    const theirGoals =
      match.teamMatchStatistic?.theirGoals ??
      match.matchDetails?.theirGoals ??
      match.liveTicker?.theirGoals ??
      0;
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

  const canManageStatistics = hasEffectivePermission(
    user.role as Role,
    Permission.MANAGE_STATISTICS,
    user.permissions,
  );
  const allowedPlayerIds = canManageStatistics
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
      const finished = isStatisticsMatchFinished(match);
      const conceded = match.teamMatchStatistic?.theirGoals ?? match.matchDetails?.theirGoals;
      if (
        finished &&
        conceded === 0 &&
        stat.appeared &&
        isDefensivePlayer(
          stat.player.position,
          stat.player.secondaryPosition,
          stat.isGoalkeeper,
        )
      ) {
        current.cleanSheets += 1;
      }
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
          position: true,
          secondaryPosition: true,
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
        AND: [
          eventTeamScope(baseTeamIds),
          statisticsMatchLifecycleScope(),
        ],
      },
      ...(allowedPlayerIds ? { playerId: { in: [...allowedPlayerIds] } } : {}),
    },
    include: {
      event: {
        include: {
          matchDetails: true,
          liveTicker: { select: { status: true } },
          teamMatchStatistic: true,
        },
      },
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
          position: true,
          secondaryPosition: true,
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
    const finished = isStatisticsMatchFinished(stat.event);
    const conceded = stat.event.teamMatchStatistic?.theirGoals ??
      stat.event.matchDetails?.theirGoals;
    if (
      finished &&
      conceded === 0 &&
      stat.appeared &&
      isDefensivePlayer(
        stat.player.position,
        stat.player.secondaryPosition,
        stat.isGoalkeeper,
      )
    ) {
      current.cleanSheets += 1;
    }
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
          cleanSheets: 0,
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

  const scopedRatings = canManageStatistics
    ? await prisma.playerMatchRating.findMany({
        where: { eventId: { in: matches.map((match) => match.id) } },
        include: {
          event: {
            select: {
              id: true,
              startAt: true,
              matchDetails: { select: { opponent: true } },
            },
          },
          player: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              preferredName: true,
              shirtNumber: true,
              position: true,
              secondaryPosition: true,
            },
          },
        },
        orderBy: { event: { startAt: 'desc' } },
      })
    : [];
  const scopedParentRatings = canManageStatistics
    ? await prisma.parentPlayerMatchRating.findMany({
        where: { eventId: { in: matches.map((match) => match.id) } },
        include: {
          event: {
            select: {
              id: true,
              startAt: true,
              matchDetails: { select: { opponent: true } },
            },
          },
          player: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              preferredName: true,
              shirtNumber: true,
              position: true,
              secondaryPosition: true,
            },
          },
        },
        orderBy: { event: { startAt: 'desc' } },
      })
    : [];
  const ratingsByPlayer = new Map<string, typeof scopedRatings>();
  for (const rating of scopedRatings) {
    const rows = ratingsByPlayer.get(rating.playerId) ?? [];
    rows.push(rating);
    ratingsByPlayer.set(rating.playerId, rows);
  }
  const parentRatingsByPlayer = new Map<string, typeof scopedParentRatings>();
  for (const rating of scopedParentRatings) {
    const rows = parentRatingsByPlayer.get(rating.playerId) ?? [];
    rows.push(rating);
    parentRatingsByPlayer.set(rating.playerId, rows);
  }
  const ratedMatchIds = new Set(scopedRatings.map((rating) => rating.eventId));
  const completedMatches = matches.filter(
    isStatisticsMatchFinished,
  );
  const performanceCenter = canManageStatistics
    ? {
        visibility: 'STAFF_ONLY',
        teamAverage: scopedRatings.length
          ? scopedRatings.reduce((sum, rating) => sum + rating.score, 0) /
            scopedRatings.length
          : null,
        parentTeamAverage: scopedParentRatings.length
          ? scopedParentRatings.reduce((sum, rating) => sum + rating.score, 0) /
            scopedParentRatings.length
          : null,
        parentRatingCount: scopedParentRatings.length,
        ratedMatches: ratedMatchIds.size,
        unratedMatches: completedMatches.filter(
          (match) => !ratedMatchIds.has(match.id),
        ).length,
        players: [...new Set([
          ...ratingsByPlayer.keys(),
          ...parentRatingsByPlayer.keys(),
        ])]
          .map((playerId) => {
            const ratings = ratingsByPlayer.get(playerId) ?? [];
            const parentRatings = parentRatingsByPlayer.get(playerId) ?? [];
            const player = ratings[0]?.player ?? parentRatings[0].player;
            const chronological = [...ratings].sort(
              (a, b) => a.event.startAt.getTime() - b.event.startAt.getTime(),
            );
            const chronologicalParent = [...parentRatings].sort(
              (a, b) => a.event.startAt.getTime() - b.event.startAt.getTime(),
            );
            const recent = chronological.slice(-5);
            const previous = chronological.slice(-10, -5);
            const recentAverage = recent.length
              ? recent.reduce((sum, rating) => sum + rating.score, 0) / recent.length
              : 0;
            const previousAverage = previous.length
              ? previous.reduce((sum, rating) => sum + rating.score, 0) / previous.length
              : recentAverage;
            const parentByEvent = new Map<string, typeof parentRatings>();
            for (const rating of chronologicalParent) {
              const rows = parentByEvent.get(rating.eventId) ?? [];
              rows.push(rating);
              parentByEvent.set(rating.eventId, rows);
            }
            const trainerByEvent = new Map(
              chronological.map((rating) => [rating.eventId, rating]),
            );
            const timelineEventIds = [...new Set([
              ...trainerByEvent.keys(),
              ...parentByEvent.keys(),
            ])].sort((a, b) => {
              const aEvent = trainerByEvent.get(a)?.event ?? parentByEvent.get(a)![0].event;
              const bEvent = trainerByEvent.get(b)?.event ?? parentByEvent.get(b)![0].event;
              return aEvent.startAt.getTime() - bEvent.startAt.getTime();
            });
            const parentEventAverages = [...parentByEvent.values()].map(
              (rows) => rows.reduce((sum, rating) => sum + rating.score, 0) / rows.length,
            );
            return {
              playerId,
              name:
                player.preferredName || `${player.firstName} ${player.lastName}`,
              shirtNumber: player.shirtNumber,
              position: player.position,
              secondaryPosition: player.secondaryPosition,
              average:
                ratings.length
                  ? ratings.reduce((sum, rating) => sum + rating.score, 0) /
                    ratings.length
                  : null,
              ratedMatches: ratings.length,
              lastScore: chronological.length
                ? chronological[chronological.length - 1].score
                : null,
              trend: recentAverage - previousAverage,
              parentAverage: parentRatings.length
                ? parentRatings.reduce((sum, rating) => sum + rating.score, 0) /
                  parentRatings.length
                : null,
              parentRatedMatches: parentByEvent.size,
              parentRatingCount: parentRatings.length,
              lastParentScore: parentEventAverages.length
                ? parentEventAverages[parentEventAverages.length - 1]
                : null,
              recent: [...recent].reverse().map((rating) => ({
                eventId: rating.eventId,
                startAt: rating.event.startAt,
                opponent: rating.event.matchDetails?.opponent ?? 'Gegner',
                score: rating.score,
              })),
              timeline: timelineEventIds.map((eventId) => {
                const trainerRating = trainerByEvent.get(eventId);
                const parentRows = parentByEvent.get(eventId) ?? [];
                const event = trainerRating?.event ?? parentRows[0].event;
                return {
                  eventId,
                  startAt: event.startAt,
                  opponent: event.matchDetails?.opponent ?? 'Gegner',
                  trainerScore: trainerRating?.score ?? null,
                  parentAverage: parentRows.length
                    ? parentRows.reduce((sum, rating) => sum + rating.score, 0) /
                      parentRows.length
                    : null,
                  parentRatingCount: parentRows.length,
                };
              }),
            };
          })
          .sort((a, b) => a.name.localeCompare(b.name, 'de-DE')),
      }
    : null;

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
    performanceCenter,
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
