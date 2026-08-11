import { EventCategory } from '@prisma/client';

import { AWAY_MEETING_LOCATION } from './match-venue.service';

const berlinDateFormatter = new Intl.DateTimeFormat('de-DE', {
  timeZone: 'Europe/Berlin',
  weekday: 'long',
  day: 'numeric',
  month: 'long',
  year: 'numeric',
});

const berlinTimeFormatter = new Intl.DateTimeFormat('de-DE', {
  timeZone: 'Europe/Berlin',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

export type ResolvedMeetingPoint = {
  at: Date | null;
  location: string | null;
  summary: string;
};

function cleaned(value: string | null | undefined) {
  const result = value?.trim().replace(/\s+/g, ' ');
  return result || null;
}

function isTournamentCategory(category: EventCategory) {
  return category === EventCategory.TOURNAMENT ||
    category === EventCategory.INDOOR_TOURNAMENT ||
    category === EventCategory.FOOTBALL_FESTIVAL;
}

function tournamentDescription(category: EventCategory, title?: string | null) {
  const label = matchCategoryLabel(category);
  const tournamentTitle = cleaned(title);
  return tournamentTitle ? `${label} „${tournamentTitle}“` : label;
}

export function matchCategoryLabel(category: EventCategory) {
  switch (category) {
    case EventCategory.FRIENDLY_MATCH:
      return 'Freundschaftsspiel';
    case EventCategory.LEAGUE_MATCH:
      return 'Ligaspiel';
    case EventCategory.CUP_MATCH:
      return 'Pokalspiel';
    case EventCategory.TOURNAMENT:
      return 'Turnier';
    case EventCategory.INDOOR_TOURNAMENT:
      return 'Hallenturnier';
    case EventCategory.FOOTBALL_FESTIVAL:
      return 'Fußballfestival';
    default:
      return 'Spiel';
  }
}

export function resolveMeetingPoint(input: {
  startAt: Date;
  meetingAt?: Date | null;
  meetingMinutesBefore?: number | null;
  meetingLocation?: string | null;
  useClubhouseDefault?: boolean;
}): ResolvedMeetingPoint {
  const relativeMinutes = input.meetingMinutesBefore;
  const relativeAt = Number.isFinite(relativeMinutes) && Number(relativeMinutes) >= 0
    ? new Date(input.startAt.getTime() - Number(relativeMinutes) * 60_000)
    : null;
  const at = input.meetingAt ?? relativeAt;
  const location = cleaned(input.meetingLocation) ??
    (input.useClubhouseDefault === false ? null : AWAY_MEETING_LOCATION);
  const time = at ? berlinTimeFormatter.format(at) : null;
  const summary = time && location
    ? `Treffpunkt: ${time} Uhr am ${location}`
    : time
      ? `Treffpunkt: ${time} Uhr`
      : location
        ? `Treffpunktort: ${location} – Uhrzeit noch offen`
        : 'Treffpunkt noch offen';
  return { at, location, summary };
}

export function buildFamilyReleaseMessage(input: {
  category: EventCategory;
  opponent: string;
  title?: string | null;
  startAt: Date;
  meeting: ResolvedMeetingPoint;
}) {
  const date = berlinDateFormatter.format(input.startAt);
  const time = berlinTimeFormatter.format(input.startAt);
  if (isTournamentCategory(input.category)) {
    return `Das ${tournamentDescription(input.category, input.title)} wurde für ${date} um ${time} Uhr freigegeben. ${input.meeting.summary}.`;
  }
  return `Das ${matchCategoryLabel(input.category)} gegen ${input.opponent} wurde für ${date} um ${time} Uhr freigegeben. ${input.meeting.summary}.`;
}

export function buildInternalPublicationMessage(input: {
  category: EventCategory;
  team: string;
  opponent: string;
  title?: string | null;
}) {
  if (isTournamentCategory(input.category)) {
    return `Kader und Aufstellung für das ${tournamentDescription(input.category, input.title)} der ${input.team} wurden mit dem Trainerteam geteilt.`;
  }
  return `Kader und Aufstellung für das ${matchCategoryLabel(input.category)} der ${input.team} gegen ${input.opponent} wurden mit dem Trainerteam geteilt.`;
}
