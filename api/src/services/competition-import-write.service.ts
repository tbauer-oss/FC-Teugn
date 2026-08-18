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

export async function writeCompetitionMatch(
  tx: Prisma.TransactionClient,
  teamId: string,
  provider: string,
  match: NormalizedCompetitionMatch,
  entityId?: string | null,
) {
  const team = await tx.team.findUniqueOrThrow({
    where: { id: teamId },
    select: { periodCount: true, periodMinutes: true },
  });
  const timing = competitionMatchTiming(match, team);
  const startAt = new Date(match.startAt);
  const type = classification(match);
  const eventData = {
    teamId,
    type: EventType.MATCH,
    category: type.category,
    status: eventStatus(match.status),
    title: match.title,
    startAt,
    endAt: match.endAt ? new Date(match.endAt) : null,
    location: match.isHome
      ? match.location || HOME_MATCH_VENUE
      : isFcTeugnHomeVenue(match.location) ? '' : match.location,
    address: match.address,
    homeAway: match.isHome ? HomeAway.HOME : HomeAway.AWAY,
    opponent: match.opponent,
  };
  const event = entityId
    ? await tx.event.update({ where: { id: entityId }, data: eventData })
    : await tx.event.create({ data: eventData });
  await tx.eventTargetTeam.upsert({
    where: { eventId_teamId: { eventId: event.id, teamId } },
    update: {},
    create: { eventId: event.id, teamId },
  });
  await tx.matchDetails.upsert({
    where: { eventId: event.id },
    update: {
      opponent: match.opponent,
      opponentId: match.opponentId,
      isHome: match.isHome,
      kind: type.kind,
      status: matchStatus(match.status),
      competition: match.competition,
      division: match.division,
      matchDay: match.matchDay,
      bfvMatchId: match.externalId,
      bfvUrl: match.sourceUrl,
      externalSource: provider,
      externalUpdatedAt: new Date(),
      ourGoals: match.ourGoals,
      theirGoals: match.theirGoals,
    },
    create: {
      eventId: event.id,
      opponent: match.opponent,
      opponentId: match.opponentId,
      isHome: match.isHome,
      kind: type.kind,
      status: matchStatus(match.status),
      competition: match.competition,
      division: match.division,
      matchDay: match.matchDay,
      bfvMatchId: match.externalId,
      bfvUrl: match.sourceUrl,
      externalSource: provider,
      externalUpdatedAt: new Date(),
      ourGoals: match.ourGoals,
      theirGoals: match.theirGoals,
      periodCount: timing.periodCount,
      periodMinutes: timing.periodMinutes,
      durationMinutes: timing.durationMinutes,
    },
  });
  await tx.externalReference.upsert({
    where: {
      provider_entityType_externalId: {
        provider,
        entityType: 'Event',
        externalId: match.externalId,
      },
    },
    update: {
      teamId,
      entityId: event.id,
      sourceChecksum: competitionMatchChecksum(match),
      sourceUrl: match.sourceUrl,
      lastSyncedAt: new Date(),
    },
    create: {
      teamId,
      provider,
      entityType: 'Event',
      externalId: match.externalId,
      entityId: event.id,
      sourceChecksum: competitionMatchChecksum(match),
      sourceUrl: match.sourceUrl,
      lastSyncedAt: new Date(),
    },
  });
  return event.id;
}
