export type TeamPlayingIdentitySource = {
  name?: string;
  shortName?: string | null;
  isPlayingCommunity: boolean;
  playingCommunityName: string | null;
  playingCommunityShortName: string | null;
  playingCommunityLogoUrl: string | null;
  ageGroup?: {
    season?: {
      club?: {
        name: string;
        shortName: string | null;
        logoUrl: string | null;
      };
    };
  };
};

function compactTeamSuffix(team: TeamPlayingIdentitySource) {
  const raw = team.shortName?.trim() || team.name?.trim() || '';
  const compact = raw
    .replace(/[-\s]*(jugend|junioren|juniorinnen)$/iu, '')
    .trim();
  return /^[A-G](?:\d+)?$/iu.test(compact) ? compact.toUpperCase() : raw;
}

function appendTeamSuffix(baseName: string, suffix: string) {
  if (!suffix) return baseName;
  const normalizedBase = baseName.toLocaleLowerCase('de-DE');
  const normalizedSuffix = suffix.toLocaleLowerCase('de-DE');
  if (
    normalizedBase === normalizedSuffix ||
    normalizedBase.endsWith(` ${normalizedSuffix}`) ||
    normalizedBase.endsWith(`-${normalizedSuffix}`)
  ) {
    return baseName;
  }
  return `${baseName} ${suffix}`;
}

export function teamPlayingIdentity(team: TeamPlayingIdentitySource) {
  const club = team.ageGroup?.season?.club;
  const playingCommunityName = team.playingCommunityName?.trim();
  const playingCommunityShortName = team.playingCommunityShortName?.trim();
  const isPlayingCommunity =
    team.isPlayingCommunity && Boolean(playingCommunityName);

  return {
    isPlayingCommunity,
    name: isPlayingCommunity
      ? playingCommunityName!
      : club?.name ?? 'FC Teugn',
    shortName: isPlayingCommunity
      ? playingCommunityShortName || playingCommunityName!
      : club?.shortName ?? club?.name ?? 'FC Teugn',
    logoUrl: isPlayingCommunity
      ? team.playingCommunityLogoUrl?.trim() || null
      : club?.logoUrl ?? null,
  };
}

/**
 * Spielanzeigen benennen nicht nur den Verein, sondern immer die tatsächlich
 * antretende Mannschaft (z. B. „FC Teugn E2“). Die allgemeine Vereinsidentität
 * bleibt davon unberührt und kann weiterhin für Kopfbereiche und Importe
 * verwendet werden.
 */
export function teamPlayingMatchIdentity(team: TeamPlayingIdentitySource) {
  const identity = teamPlayingIdentity(team);
  const suffix = compactTeamSuffix(team);
  return {
    ...identity,
    name: appendTeamSuffix(identity.name, suffix),
    shortName: appendTeamSuffix(identity.shortName, suffix),
  };
}

export function matchTitleForPlayingIdentity(input: {
  ownTeamName: string;
  opponent: string;
  isHome: boolean;
}) {
  return input.isHome
    ? `${input.ownTeamName} – ${input.opponent}`
    : `${input.opponent} – ${input.ownTeamName}`;
}
