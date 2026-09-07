import { Prisma } from '@prisma/client';

export function carryAbsenceTeams(teamIds: string[], mapping: Record<string, string>) {
  return [...new Set(teamIds.map(id => mapping[id] ?? id))];
}
export async function carryTalentsSeason(tx: Prisma.TransactionClient, mapping: Record<string, string>,
  options: { goals: boolean; absences: boolean }, startsOn: string, actorId: string) {
  let goals = 0, absences = 0;
  for (const [oldTeamId, newTeamId] of Object.entries(mapping)) {
    const moved = await tx.player.findMany({ where: { teamId: newTeamId }, select: { id: true } });
    const playerIds = moved.map(p => p.id);
    const activeGoals = await tx.learningGoal.findMany({ where: { teamId: oldTeamId, playerId: { in: playerIds }, status: 'ACTIVE' }, include: { observations: true } });
    for (const goal of activeGoals) {
      await tx.learningGoal.update({ where: { id: goal.id }, data: { status: 'ARCHIVED' } });
      if (!options.goals) continue;
      // Preserve the original season record; the successor references it in the narrative.
      const responsible = await tx.teamMembership.findFirst({ where: { teamId: newTeamId, userId: goal.responsibleUserId, status: 'APPROVED' } });
      const next = await tx.learningGoal.create({ data: { playerId: goal.playerId, teamId: newTeamId, authorId: actorId,
        responsibleUserId: responsible ? goal.responsibleUserId : actorId, title: goal.title, description: goal.description,
        startsOn, endsOn: goal.endsOn < startsOn ? startsOn : goal.endsOn, visibility: goal.visibility,
        // Old training links remain in the historic goal. New season links are selected by the trainer.
      } });
      const last = goal.observations.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0];
      await tx.goalObservation.create({ data: { goalId: next.id, authorId: actorId,
        note: `Aus der Vorsaison übernommen. Zeitraum und verantwortlichen Trainer prüfen.${last ? ' Letzte Beobachtung: ' + last.note : ''}`,
        progress: last?.progress ?? 0 } });
      goals++;
    }
    const existing = await tx.playerAbsence.findMany({ where: { playerId: { in: playerIds }, endedAt: null, endsOn: { gte: startsOn } } });
    for (const absence of existing) {
      if (options.absences) {
        await tx.playerAbsence.update({ where: { id: absence.id }, data: { teamIds: carryAbsenceTeams(absence.teamIds, mapping) } });
        absences++;
      } else {
        // End at the actual season boundary, not at the day the transition is prepared.
        const previousDay = new Date(`${startsOn}T12:00:00Z`); previousDay.setUTCDate(previousDay.getUTCDate() - 1);
        await tx.playerAbsence.update({ where: { id: absence.id }, data: absence.startsOn >= startsOn ? { endedAt: new Date() } : { endsOn: previousDay.toISOString().slice(0, 10) } });
      }
    }
  }
  return { carriedGoals: goals, carriedAbsences: absences };
}
