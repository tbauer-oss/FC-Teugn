import {
  AttendanceStatus,
  NominationStatus,
  Prisma,
  PrismaClient,
  TickerEventType,
} from '@prisma/client';
import { prisma } from '../lib/prisma';

type DbClient = PrismaClient | Prisma.TransactionClient;
const goalTypes = new Set<TickerEventType>([
  TickerEventType.HOME_GOAL,
  TickerEventType.AWAY_GOAL,
]);

export type MatchResultRow = {
  ourGoals: number;
  theirGoals: number;
  result: string;
  isHome: boolean;
};

export function summarizeMatchResults(matches: MatchResultRow[]) {
  const wins = matches.filter((match) => match.result === 'WIN').length;
  const draws = matches.filter((match) => match.result === 'DRAW').length;
  const losses = matches.filter((match) => match.result === 'LOSS').length;
  const goalsFor = matches.reduce((sum, match) => sum + match.ourGoals, 0);
  const goalsAgainst = matches.reduce((sum, match) => sum + match.theirGoals, 0);
  return {
    matches: matches.length,
    wins,
    draws,
    losses,
    goalsFor,
    goalsAgainst,
    winRate: matches.length ? Math.round((wins / matches.length) * 1000) / 10 : 0,
    goalsPerMatch: matches.length
      ? Math.round((goalsFor / matches.length) * 100) / 100
      : 0,
    home: {
      matches: matches.filter((match) => match.isHome).length,
      wins: matches.filter((match) => match.isHome && match.result === 'WIN').length,
    },
    away: {
      matches: matches.filter((match) => !match.isHome).length,
      wins: matches.filter((match) => !match.isHome && match.result === 'WIN').length,
    },
    form: matches.slice(-5).map((match) => match.result),
  };
}

export async function recalculateMatchStatistics(
  eventId: string,
  db: DbClient = prisma,
) {
  const event = await db.event.findUnique({
    where: { id: eventId },
    include: {
      matchDetails: true,
      attendance: true,
      squads: {
        include: {
          members: true,
          lineup: { include: { positions: true } },
        },
      },
      liveTicker: {
        include: {
          events: {
            where: { revokedAt: null },
            orderBy: { sequence: 'asc' },
          },
        },
      },
    },
  });
  if (!event?.matchDetails) throw new Error('MATCH_NOT_FOUND');

  const squad = event.squads[0];
  const lineup = squad?.lineup;
  const duration = event.matchDetails.durationMinutes;
  const players = new Set<string>();
  for (const member of squad?.members ?? []) {
    if (member.status !== NominationStatus.DECLINED) players.add(member.playerId);
  }
  for (const position of lineup?.positions ?? []) players.add(position.playerId);
  for (const attendance of event.attendance) {
    if (attendance.actualAttendance === AttendanceStatus.YES) players.add(attendance.playerId);
  }
  for (const tickerEvent of event.liveTicker?.events ?? []) {
    if (tickerEvent.scorerId) players.add(tickerEvent.scorerId);
    if (tickerEvent.assistId) players.add(tickerEvent.assistId);
  }

  const statistics = [...players].map((playerId) => {
    const positions = lineup?.positions.filter((item) => item.playerId === playerId) ?? [];
    const member = squad?.members.find((item) => item.playerId === playerId);
    const attendance = event.attendance.find((item) => item.playerId === playerId);
    const appeared =
      positions.length > 0 ||
      attendance?.actualAttendance === AttendanceStatus.YES ||
      member?.status === NominationStatus.NOMINATED;
    return {
      eventId,
      playerId,
      appeared,
      started: positions.some((item) => item.period === 1 && item.isStarter),
      minutesPlayed: appeared ? member?.plannedMinutes ?? duration : 0,
      goals:
        event.liveTicker?.events.filter(
          (item) =>
            item.scorerId === playerId &&
            goalTypes.has(item.type),
        ).length ?? 0,
      assists:
        event.liveTicker?.events.filter(
          (item) =>
            item.assistId === playerId &&
            goalTypes.has(item.type),
        ).length ?? 0,
      isGoalkeeper: positions.some((item) => item.isGoalkeeper),
      isCaptain: positions.some((item) => item.isCaptain),
      recalculatedAt: new Date(),
    };
  });

  const ourGoals = event.liveTicker?.ourGoals ?? event.matchDetails.ourGoals ?? 0;
  const theirGoals = event.liveTicker?.theirGoals ?? event.matchDetails.theirGoals ?? 0;
  const result = ourGoals > theirGoals ? 'WIN' : ourGoals < theirGoals ? 'LOSS' : 'DRAW';

  await db.teamMatchStatistic.upsert({
    where: { eventId },
    update: {
      ourGoals,
      theirGoals,
      result,
      isHome: event.matchDetails.isHome,
      recalculatedAt: new Date(),
    },
    create: {
      eventId,
      ourGoals,
      theirGoals,
      result,
      isHome: event.matchDetails.isHome,
    },
  });
  await db.playerMatchStatistic.deleteMany({
    where: { eventId, playerId: { notIn: [...players] } },
  });
  for (const statistic of statistics) {
    await db.playerMatchStatistic.upsert({
      where: { eventId_playerId: { eventId, playerId: statistic.playerId } },
      update: statistic,
      create: statistic,
    });
  }
  return { eventId, ourGoals, theirGoals, result, playerStatistics: statistics };
}
