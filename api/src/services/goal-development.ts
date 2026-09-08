import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { berlinCalendarDayRange } from './daily-attendance-conflict.service';

type GoalContext = {
  id: string; playerId: string; teamId: string; startsOn: string; endsOn: string;
  observations: { id: string; createdAt: Date; note: string; progress: number }[];
};

// Context from the same child and goal period; it is not a claim that a
// particular match or older development note measures this goal directly.
export async function goalDevelopment(goal: GoalContext, access: {
  notes: 'STAFF' | 'FAMILY' | 'NONE'; statistics: boolean; family: boolean;
}) {
  const from = berlinCalendarDayRange(new Date(`${goal.startsOn}T12:00:00Z`)).startAt;
  const to = berlinCalendarDayRange(new Date(`${goal.endsOn}T12:00:00Z`)).endAt;
  const eventScope: Prisma.EventWhereInput = {
    teamId: goal.teamId, status: 'SCHEDULED', startAt: { gte: from, lt: to },
    ...(access.family ? { familyReleasedAt: { not: null } } : {}),
  };
  const [notes, matches, training] = await Promise.all([
    access.notes === 'NONE' ? Promise.resolve([]) : prisma.playerDevelopmentNote.findMany({
      where: { playerId: goal.playerId, observedAt: { gte: from, lt: to },
        ...(access.notes === 'FAMILY' ? { visibility: 'GUARDIANS_AND_STAFF' as const } : {}) },
      select: { id: true, title: true, notes: true, observedAt: true, visibility: true },
      orderBy: [{ observedAt: 'desc' }, { id: 'asc' }],
    }),
    access.statistics ? prisma.playerMatchStatistic.findMany({
      where: { playerId: goal.playerId, event: { ...eventScope, type: 'MATCH', OR: [
        { matchDetails: { is: { status: { in: ['FINISHED', 'RECORDED'] } } } },
        { liveTicker: { is: { status: 'FINISHED' } } },
      ] } },
      select: { id: true, appeared: true, minutesPlayed: true, goals: true, assists: true,
        event: { select: { title: true, startAt: true } } },
    }) : Promise.resolve([]),
    access.statistics ? prisma.attendance.findMany({
      where: { playerId: goal.playerId, actualAttendance: { not: null },
        event: { ...eventScope, type: 'TRAINING' } },
      select: { id: true, actualAttendance: true, event: { select: { title: true, startAt: true } } },
    }) : Promise.resolve([]),
  ]);
  const timeline = [
    ...goal.observations.map(o => ({ id: o.id, kind: 'GOAL', at: o.createdAt,
      title: 'Zielbeobachtung', text: o.note, progress: o.progress })),
    ...notes.map(n => ({ id: n.id, kind: 'NOTE', at: n.observedAt,
      title: n.title, text: n.notes, visibility: n.visibility })),
    ...matches.map(m => ({ id: m.id, kind: 'MATCH', at: m.event.startAt,
      title: m.event.title, text: m.appeared
        ? `${m.minutesPlayed} Min. · ${m.goals} Tore · ${m.assists} Vorlagen`
        : 'Kein Einsatz erfasst' })),
    ...training.map(t => ({ id: t.id, kind: 'TRAINING', at: t.event.startAt,
      title: t.event.title, text: t.actualAttendance === 'YES' ? 'Teilgenommen'
        : t.actualAttendance === 'NO' ? 'Nicht teilgenommen' : 'Anwesenheit nicht abschließend geklärt' })),
  ].sort((a, b) => b.at.getTime() - a.at.getTime() || a.id.localeCompare(b.id));
  return {
    from: goal.startsOn, to: goal.endsOn, timeline,
    statistics: access.statistics ? {
      recordedMatches: matches.length,
      appearances: matches.filter(m => m.appeared).length,
      minutes: matches.reduce((sum, m) => sum + (m.appeared ? m.minutesPlayed : 0), 0),
      goals: matches.reduce((sum, m) => sum + m.goals, 0),
      assists: matches.reduce((sum, m) => sum + m.assists, 0),
      attendedTrainings: training.filter(t => t.actualAttendance === 'YES').length,
      recordedTrainings: training.filter(t => ['YES', 'NO'].includes(t.actualAttendance ?? '')).length,
    } : null,
  };
}
