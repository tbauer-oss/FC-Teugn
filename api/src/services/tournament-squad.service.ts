import { AttendanceStatus, MatchStatus, NominationStatus, PlayerStatus, Prisma, TickerStatus } from '@prisma/client';
import { attendanceAfterRevision } from './attendance-revision';

export function canInheritTournamentSquad(fixture: {
  parentTournamentId: string | null;
  matchDetails: { status: MatchStatus } | null;
  liveTicker: { status: TickerStatus; events: unknown[] } | null;
  squads: Array<{ inheritsTournamentSquad: boolean }>;
}) {
  return Boolean(fixture.parentTournamentId) &&
    (!fixture.squads[0] || fixture.squads[0].inheritsTournamentSquad) &&
    (!fixture.matchDetails || new Set<MatchStatus>([MatchStatus.PLANNED, MatchStatus.CONFIRMED, MatchStatus.POSTPONED]).has(fixture.matchDetails.status)) &&
    (!fixture.liveTicker || (fixture.liveTicker.status === TickerStatus.NOT_STARTED && !fixture.liveTicker.events.length));
}

/** Materialize a fixture's default on opening it. No invitations or pushes:
 * the tournament remains the single invitation and response context.
 * An explicit fixture squad edit detaches the default; started games freeze it.
 */
export async function inheritTournamentSquad(tx: Prisma.TransactionClient, fixtureId: string) {
  // Serialize initialization and edits for this fixture, including parallel opens.
  await tx.$queryRaw`SELECT id FROM "Event" WHERE id = ${fixtureId} FOR UPDATE`;
  const fixture = await tx.event.findUnique({
    where: { id: fixtureId },
    include: {
      matchDetails: true,
      liveTicker: { include: { events: { take: 1, select: { id: true } } } },
      squads: { include: { members: true, lineup: true } },
      attendance: true,
      parentTournament: { include: {
        attendance: true,
        squads: { include: {
          members: { include: { player: { select: { status: true } } } },
          lineup: { include: { positions: true } },
        } },
      } },
    },
  });
  if (!fixture || !canInheritTournamentSquad({ ...fixture, squads: [] })) return false;
  const tournament = fixture.parentTournament;
  const source = tournament?.squads[0];
  if (!tournament || !source) return false;
  const replies = tournament.attendance.map(reply => attendanceAfterRevision(reply, tournament));
  const declined = new Set(replies.filter(reply => reply.status === AttendanceStatus.NO).map(reply => reply.playerId));
  const members = source.members.filter(member =>
    member.status === NominationStatus.NOMINATED &&
    member.player.status === PlayerStatus.ACTIVE && !declined.has(member.playerId));
  const ids = members.map(member => member.playerId);
  const existing = fixture.squads[0];
  const inherited = !existing || existing.inheritsTournamentSquad;
  const responseIds = inherited ? ids : existing.members.map(member => member.playerId);
  const replyChanges = responseIds.flatMap(playerId => {
    const previous = fixture.attendance.find(item => item.playerId === playerId);
    if (previous?.respondedById) return [];
    const sourceReply = replies.find(item => item.playerId === playerId);
    const data = { status: sourceReply?.status ?? AttendanceStatus.UNKNOWN,
      goalkeeperAvailable: sourceReply?.goalkeeperAvailable ?? null };
    return previous?.status === data.status && previous?.goalkeeperAvailable === data.goalkeeperAvailable
      ? [] : [{ playerId, data }];
  });
  if (!inherited) {
    for (const { playerId, data } of replyChanges) {
      await tx.attendance.createMany({ data: [{ eventId: fixture.id, playerId, ...data }], skipDuplicates: true });
      await tx.attendance.updateMany({ where: { eventId: fixture.id, playerId, respondedById: null }, data });
    }
    return replyChanges.length > 0;
  }
  const changed = !existing || existing.members.length !== members.length ||
    existing.members.some(member => member.status !== NominationStatus.NOMINATED || !ids.includes(member.playerId));
  const metadataChanged = !existing || existing.name !== source.name || existing.formation !== source.formation ||
    existing.publishedAt?.getTime() !== source.publishedAt?.getTime();
  if (!changed && !metadataChanged && !replyChanges.length && (existing?.lineup || !source.lineup)) return false;
  // Lock the squad as well: a simultaneous explicit edit must always win.
  const squad = await tx.squad.upsert({
    where: { eventId: fixture.id },
    create: { eventId: fixture.id, inheritsTournamentSquad: true },
    update: {},
  });
  if (!squad.inheritsTournamentSquad) return false;
  const memberData = members.map(member => ({
    squadId: squad.id, playerId: member.playerId, status: member.status,
    // Tournament minutes/notes are not per-fixture plans.
  }));
  if (changed) {
    if (existing?.lineup) {
      await tx.lineupPosition.deleteMany({ where: { lineupId: existing.lineup.id, playerId: { notIn: ids } } });
      await tx.plannedSubstitution.deleteMany({ where: { lineupId: existing.lineup.id, OR: [
        { playerInId: { notIn: ids } }, { playerOutId: { notIn: ids } },
      ] } });
    }
    await tx.squadMember.deleteMany({ where: { squadId: squad.id } });
    if (memberData.length) await tx.squadMember.createMany({ data: memberData });
  }
  if (metadataChanged) await tx.squad.update({ where: { id: squad.id }, data: {
    name: source.name, formation: source.formation, publishedAt: source.publishedAt,
  } });
  // Copy only unanswered fixture rows; real fixture-specific replies take priority.
  for (const { playerId, data } of replyChanges) {
    await tx.attendance.createMany({ data: [{ eventId: fixture.id, playerId, ...data }], skipDuplicates: true });
    await tx.attendance.updateMany({ where: { eventId: fixture.id, playerId, respondedById: null }, data });
  }
  // Only seed a lineup once; a fixture's own formation is never overwritten.
  if (!existing?.lineup && source.lineup) {
    const positions = source.lineup.positions.filter(position => position.period === 1 && ids.includes(position.playerId));
    await tx.lineup.upsert({
      where: { squadId: squad.id }, update: {},
      create: {
        squadId: squad.id, formation: source.lineup.formation,
        fieldSize: source.lineup.fieldSize, status: source.lineup.status, usesTeamDefault: true,
        publishedAt: source.lineup.publishedAt, visibleAt: source.lineup.visibleAt,
        positions: { create: positions.map(position => ({
          playerId: position.playerId, positionCode: position.positionCode,
          x: position.x, y: position.y, isStarter: position.isStarter,
          isGoalkeeper: position.isGoalkeeper, isCaptain: position.isCaptain,
          shirtNumber: position.shirtNumber,
        })) },
      },
    });
  }
  return true;
}

/** The parent release is authoritative for every tournament fixture. */
export function withTournamentRelease<T extends {
  familyReleasedAt: Date | null;
  parentTournament?: { familyReleasedAt: Date | null; familyReleaseAudience: string | null } | null;
}>(event: T): T {
  if (!event.parentTournament) return event;
  return { ...event, familyReleasedAt: event.parentTournament.familyReleasedAt,
    familyReleaseAudience: event.parentTournament.familyReleaseAudience };
}
