import { mergeCompetitionFields, ImportSnapshot } from './competition-merge';
import { DomainError } from './talents-domain';
import { shiftedResponseDeadline } from './response-deadline';
import { reconcileAbsencesForEvents } from './absence.service';
import {
  EventCategory,
  EventStatus,
  EventType,
  HomeAway,
  MatchKind,
  MatchStatus,
  Prisma,
} from '@prisma/client';
import {
  HOME_MATCH_VENUE,
  isFcTeugnHomeVenue,
} from './match-venue.service';
import {
  competitionMatchChecksum,
  NormalizedCompetitionMatch,
} from './competition-provider';

function matchStatus(value: string) {
  return (Object.values(MatchStatus) as string[]).includes(value)
    ? (value as MatchStatus)
    : MatchStatus.PLANNED;
}

function eventStatus(value: string) {
  return value === MatchStatus.CANCELLED
    ? EventStatus.CANCELLED
    : EventStatus.SCHEDULED;
}

function classification(match: NormalizedCompetitionMatch) {
  const value = `${match.title} ${match.competition ?? ''}`.toLocaleLowerCase('de-DE');
  if (value.includes('turnier')) {
    return { kind: MatchKind.TOURNAMENT, category: EventCategory.TOURNAMENT };
  }
  if (value.includes('pokal') || value.includes('cup')) {
    return { kind: MatchKind.CUP, category: EventCategory.CUP_MATCH };
  }
  if (value.includes('freund') || value.includes('testspiel')) {
    return { kind: MatchKind.FRIENDLY, category: EventCategory.FRIENDLY_MATCH };
  }
  return { kind: MatchKind.LEAGUE, category: EventCategory.LEAGUE_MATCH };
}

export function competitionMatchTiming(
  match: Pick<NormalizedCompetitionMatch, 'periodCount' | 'periodMinutes'>,
  team: { periodCount: number; periodMinutes: number },
) {
  const explicit =
    match.periodCount != null &&
    match.periodMinutes != null &&
    match.periodCount >= 1 &&
    match.periodCount <= 8 &&
    match.periodMinutes >= 1 &&
    match.periodMinutes <= 90 &&
    match.periodCount * match.periodMinutes <= 180;
  const periodCount = explicit ? match.periodCount! : team.periodCount;
  const periodMinutes = explicit ? match.periodMinutes! : team.periodMinutes;
  return {
    periodCount,
    periodMinutes,
    durationMinutes: periodCount * periodMinutes,
    explicit,
  };
}


export function competitionSourceSnapshot(match: NormalizedCompetitionMatch): ImportSnapshot {
  return {
    title: match.title, startAt: new Date(match.startAt).toISOString(),
    endAt: match.endAt ? new Date(match.endAt).toISOString() : null,
    location: match.isHome ? match.location || HOME_MATCH_VENUE
      : isFcTeugnHomeVenue(match.location) ? '' : match.location,
    address: match.address, status: eventStatus(match.status),
    opponent: match.opponent, homeAway: match.isHome ? 'HOME' : 'AWAY',
    competition: match.competition, division: match.division, matchDay: match.matchDay,
    matchStatus: matchStatus(match.status), ourGoals: match.ourGoals, theirGoals: match.theirGoals,
  };
}
export function competitionCurrentSnapshot(event: {
  title: string; startAt: Date; endAt: Date | null; location: string; address: string | null;
  status: string; opponent: string | null; homeAway: string | null;
  matchDetails: { competition: string | null; division: string | null; matchDay: string | null;
    status: string; ourGoals: number | null; theirGoals: number | null } | null;
}): ImportSnapshot {
  return {
    title: event.title, startAt: event.startAt.toISOString(), endAt: event.endAt?.toISOString() ?? null,
    location: event.location, address: event.address, status: event.status, opponent: event.opponent,
    homeAway: event.homeAway, competition: event.matchDetails?.competition ?? null,
    division: event.matchDetails?.division ?? null, matchDay: event.matchDetails?.matchDay ?? null,
    matchStatus: event.matchDetails?.status ?? 'PLANNED', ourGoals: event.matchDetails?.ourGoals ?? null,
    theirGoals: event.matchDetails?.theirGoals ?? null,
  };
}

export async function writeCompetitionMatch(
  tx: Prisma.TransactionClient, teamId: string, provider: string,
  match: NormalizedCompetitionMatch, entityId?: string | null, sourceWins = false,
  resolutions: Record<string, 'LOCAL' | 'SOURCE'> = {},
) {
  const reference = await tx.externalReference.findFirst({ where: {
    provider: provider === 'ICS' || provider === 'BFV_ICS' ? { in: ['ICS', 'BFV_ICS'] } : provider,
    entityType: 'Event', externalId: match.externalId,
  } });
  if (reference && reference.teamId !== teamId) throw new DomainError(409, 'Dieses Spiel ist bereits einer anderen Mannschaft zugeordnet.');
  let existingId = entityId ?? reference?.entityId;
  if (!existingId) {
    const candidates = await tx.event.findMany({ where: { teamId, type: EventType.MATCH,
      startAt: new Date(match.startAt), OR: [{ opponent: { equals: match.opponent, mode: 'insensitive' } },
        { matchDetails: { opponent: { equals: match.opponent, mode: 'insensitive' } } }] }, select: { id: true }, take: 2 });
    if (candidates.length > 1) throw new DomainError(409, 'Mehrere passende Spiele gefunden. Bitte Dubletten vor dem Import prüfen.');
    existingId = candidates[0]?.id;
  }
  const previous = existingId ? await tx.event.findUnique({ where: { id: existingId }, include: { matchDetails: true } }) : null;
  if (previous && previous.teamId !== teamId) throw new DomainError(403, 'Fremdes Spiel darf nicht überschrieben werden.');
  if (existingId && !previous && !sourceWins) throw new DomainError(409, 'Das Spiel wurde zwischenzeitlich entfernt. Vorschau neu laden.');
  const team = await tx.team.findUniqueOrThrow({ where: { id: teamId }, select: { periodCount: true, periodMinutes: true } });
  const timing = competitionMatchTiming(match, team);
  const sourceSnapshot = competitionSourceSnapshot(match);
  const before = previous ? competitionCurrentSnapshot(previous) : sourceSnapshot;
  const legacyLocallyChanged = previous && reference && Math.max(previous.updatedAt.getTime(), previous.matchDetails?.updatedAt.getTime() ?? 0) > reference.lastSyncedAt.getTime() + 1000;
  const base = reference?.sourceSnapshot as ImportSnapshot | null ?? (legacyLocallyChanged ? null : before);
  const { merged, conflicts } = mergeCompetitionFields(base, before, sourceSnapshot, sourceWins, resolutions);
  if (conflicts.length && !sourceWins) throw new DomainError(409, 'Lokale Konflikte: ' + conflicts.join(', ') + '. Bitte Importvorschau prüfen.');
  const type = classification(match);
  const eventData = {
    teamId, type: EventType.MATCH, category: type.category,
    status: merged.status as EventStatus, title: String(merged.title),
    startAt: new Date(String(merged.startAt)), endAt: merged.endAt ? new Date(String(merged.endAt)) : null,
    location: String(merged.location), address: merged.address as string | null,
    homeAway: merged.homeAway as HomeAway, opponent: merged.opponent as string,
    reminderSyncPendingAt: new Date(),
  };
  const fields = previous ? ['startAt', 'endAt', 'location', 'address', 'status'].filter(key => before[key] !== merged[key]) : [];
  const significant = fields.length > 0 && eventData.startAt > new Date() && !previous?.attendanceFinalized;
  const event = previous
    ? await tx.event.update({ where: { id: previous.id }, data: { ...eventData,
        responseDeadline: shiftedResponseDeadline(previous.responseDeadline, previous.startAt, eventData.startAt),
        ...(significant ? { responseRevisionAt: new Date() } : {}) } })
    : await tx.event.create({ data: eventData });
  if (fields.length && previous) await tx.eventChange.create({ data: {
    eventId: event.id, before, after: merged, fields,
  } });
  await tx.eventTargetTeam.upsert({ where: { eventId_teamId: { eventId: event.id, teamId } }, update: {}, create: { eventId: event.id, teamId } });
  const detailsData = {
    opponent: String(merged.opponent), opponentId: match.opponentId,
    isHome: merged.homeAway === 'HOME', kind: type.kind, status: merged.matchStatus as MatchStatus,
    competition: merged.competition as string | null, division: merged.division as string | null,
    matchDay: merged.matchDay as string | null, bfvMatchId: match.externalId, bfvUrl: match.sourceUrl,
    externalSource: provider, externalUpdatedAt: new Date(), ourGoals: merged.ourGoals as number | null,
    theirGoals: merged.theirGoals as number | null,
  };
  await tx.matchDetails.upsert({ where: { eventId: event.id }, update: detailsData,
    create: { ...detailsData, eventId: event.id, periodCount: timing.periodCount,
      periodMinutes: timing.periodMinutes, durationMinutes: timing.durationMinutes } });
  const effectiveProvider = reference?.provider ?? provider;
  await tx.externalReference.upsert({ where: { provider_entityType_externalId: {
      provider: effectiveProvider, entityType: 'Event', externalId: match.externalId } },
    update: { teamId, entityId: event.id, sourceChecksum: competitionMatchChecksum(match), sourceSnapshot,
      sourceUrl: match.sourceUrl, lastSyncedAt: new Date() },
    create: { teamId, provider: effectiveProvider, entityType: 'Event', externalId: match.externalId,
      entityId: event.id, sourceChecksum: competitionMatchChecksum(match), sourceSnapshot, sourceUrl: match.sourceUrl },
  });
  await reconcileAbsencesForEvents(tx, [event.id]);
  return event.id;
}
