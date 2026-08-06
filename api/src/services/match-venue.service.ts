export const HOME_MATCH_VENUE = 'Stadion am Kreutweg, Teugn';
export const AWAY_MEETING_LOCATION = 'Vereinsheim Teugn';

function normalized(value: string | null | undefined) {
  return (value ?? '').trim().replace(/\s+/g, ' ').toLocaleLowerCase('de-DE');
}

export function isFcTeugnHomeVenue(value: string | null | undefined) {
  return normalized(value) === normalized(HOME_MATCH_VENUE);
}

export function normalizedMatchVenue(input: {
  isHome: boolean;
  requested?: string | null;
  previous?: string | null;
  previousWasHome?: boolean;
  opponentVenue?: string | null;
  opponentAddress?: string | null;
}) {
  const requested = input.requested?.trim() || null;
  if (input.isHome) {
    return HOME_MATCH_VENUE;
  }
  if (requested && !isFcTeugnHomeVenue(requested)) return requested;
  const previous = input.previous?.trim() || null;
  if (
    !requested &&
    previous &&
    !input.previousWasHome &&
    !isFcTeugnHomeVenue(previous)
  ) {
    return previous;
  }
  return input.opponentVenue?.trim() || input.opponentAddress?.trim() || '';
}
