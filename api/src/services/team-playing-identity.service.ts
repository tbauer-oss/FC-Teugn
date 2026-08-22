export type TeamPlayingIdentitySource = {
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

export function matchTitleForPlayingIdentity(input: {
  ownTeamName: string;
  opponent: string;
  isHome: boolean;
}) {
  return input.isHome
    ? `${input.ownTeamName} – ${input.opponent}`
    : `${input.opponent} – ${input.ownTeamName}`;
}
