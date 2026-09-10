import { AttendanceStatus, MatchStatus, NominationStatus, PlayerStatus, Prisma, TickerStatus } from '@prisma/client';
import { attendanceAfterRevision } from './attendance-revision';

export function canInheritTournamentSquad(fixture: {
  parentTournamentId: string | null;
  matchDetails: { status: MatchStatus } | null;
  liveTicker: { status: TickerStatus; events: unknown[] } | null;
  squads: Array<{ inheritsTournamentSquad: boolean }>;
}) {
  return Boolean(fixture.parentTournamentId) &&
    (!fixture.matchDetails || new Set<MatchStatus>([MatchStatus.PLANNED, MatchStatus.CONFIRMED, MatchStatus.POSTPONED]).has(fixture.matchDetails.status)) &&
    (!fixture.liveTicker || (fixture.liveTicker.status === TickerStatus.NOT_STARTED && !fixture.liveTicker.events.length));
}

/** Materialize a fixture's default on opening it. No invitations or pushes:
 * the tournament remains the single invitation and response context.
 * The tournament is the roster/response master. Started games freeze their roster.
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
  if (!fixture) return false;
  const tournament = fixture.parentTournament;
  const source = tournament?.squads[0];
  if (!tournament) return false;
  const replies = tournament.attendance.map(reply => attendanceAfterRevision(reply, tournament));
  // Mirror ALL master replies, including trainer corrections and legacy child
  // answers. A child answer never takes precedence over the tournament.
  const responseIds = [...new Set([...replies.map(reply => reply.playerId),
    ...(source?.members.map(member => member.playerId) ?? [])])];
  let responsesChanged = false;
  for (const playerId of responseIds) {
    const reply = replies.find(item => item.playerId === playerId);
    const data = { status: reply?.status ?? AttendanceStatus.UNKNOWN,
      goalkeeperAvailable: reply?.goalkeeperAvailable ?? null,
      respondedAt: reply?.respondedAt ?? null, respondedById: reply?.respondedById ?? null,
      responseSource: reply?.responseSource ?? null, responderRelationship: reply?.responderRelationship ?? null,
      reason: reply?.reason ?? null };
    const previous = fixture.attendance.find(item => item.playerId === playerId);
    if (!previous || Object.entries(data).some(([key, value]) =>
      String(previous[key as keyof typeof previous]) !== String(value))) {
      await tx.attendance.upsert({ where: { eventId_playerId: { eventId: fixture.id, playerId } },
        create: { eventId: fixture.id, playerId, ...data }, update: { ...data, absenceId: null, beforeAbsence: Prisma.DbNull } });
      responsesChanged = true;
    }
  }
  const removed = await tx.attendance.deleteMany({ where: { eventId: fixture.id, playerId: { notIn: responseIds } } });
  if (fixture.responseRevisionAt) {
    await tx.event.update({ where: { id: fixture.id }, data: { responseRevisionAt: null } });
    responsesChanged = true;
  }
  responsesChanged ||= removed.count > 0;
  if (!source || !canInheritTournamentSquad(fixture)) return responsesChanged;
  const declined = new Set(replies.filter(reply => reply.status === AttendanceStatus.NO).map(reply => reply.playerId));
  const members = source.members.filter(member =>
    member.status === NominationStatus.NOMINATED &&
    member.player.status === PlayerStatus.ACTIVE && !declined.has(member.playerId));
  const ids = members.map(member => member.playerId);
  const existing = fixture.squads[0];
  const changed = !existing || existing.members.length !== members.length ||
    existing.members.some(member => member.status !== NominationStatus.NOMINATED || !ids.includes(member.playerId));
  const metadataChanged = !existing || existing.name !== source.name || existing.formation !== source.formation ||
    existing.publishedAt?.getTime() !== source.publishedAt?.getTime();
  const masterPositions = source.lineup?.positions.filter(position => position.period === 1 && ids.includes(position.playerId));
  const shouldFollowLineup = !existing?.lineup || existing.lineup.usesTeamDefault;
  // Compare the canonical fields only, so repeat opens are read-only.
  const positionFields = (positions: Array<{ playerId: string; positionCode: string; x: number; y: number; isStarter: boolean; isGoalkeeper: boolean; isCaptain: boolean; shirtNumber: number | null }>) =>
    JSON.stringify(positions.map(p => [p.playerId, p.positionCode, p.x, p.y, p.isStarter, p.isGoalkeeper, p.isCaptain, p.shirtNumber]).sort());
  const currentPositions = existing?.lineup ? await tx.lineupPosition.findMany({ where: { lineupId: existing.lineup.id } }) : [];
  const lineupChanged = shouldFollowLineup && !!source.lineup && (!existing?.lineup ||
    existing.lineup.formation !== source.lineup.formation || existing.lineup.status !== source.lineup.status ||
    existing.lineup.fieldSize !== source.lineup.fieldSize ||
    existing.lineup.publishedAt?.getTime() !== source.lineup.publishedAt?.getTime() ||
    existing.lineup.visibleAt?.getTime() !== source.lineup.visibleAt?.getTime() ||
    positionFields(currentPositions) !== positionFields(masterPositions ?? []));
  if (!changed && !metadataChanged && existing?.inheritsTournamentSquad && !lineupChanged) return responsesChanged;
  // The event lock serializes this write with explicit per-game lineup edits.
  const squad = await tx.squad.upsert({
    where: { eventId: fixture.id },
    create: { eventId: fixture.id, inheritsTournamentSquad: true },
    update: { inheritsTournamentSquad: true },
  });
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
  // Follow the master until the trainer deliberately edits this game's lineup.
  if (lineupChanged && source.lineup) {
    const positions = source.lineup.positions.filter(position => position.period === 1 && ids.includes(position.playerId));
    if (existing?.lineup) await tx.lineup.delete({ where: { id: existing.lineup.id } });
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
