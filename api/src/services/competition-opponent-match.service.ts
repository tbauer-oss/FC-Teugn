import { prisma } from '../lib/prisma';
import {
  competitionTeamIdentity,
  ParsedCompetitionRow,
} from './competition-provider';

export function normalizedCompetitionName(value: string) {
  return value
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('de-DE')
    .replace(/^\s*\(?\s*sg\s*\)?\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Links imported labels to the central opponent pool. Matching is deliberately
 * conservative: club name/short name must match, and the imported squad is
 * preferred exactly. A unique club entry is only used as fallback when the
 * import contains no squad designation at all.
 */
export async function matchCompetitionOpponents(
  teamId: string,
  rows: ParsedCompetitionRow[],
) {
  const team = await prisma.team.findUnique({
    where: { id: teamId },
    select: { ageGroupId: true },
  });
  if (!team) return rows;
  const opponents = await prisma.opponent.findMany({
    where: { ageGroupId: team.ageGroupId, archivedAt: null },
    select: {
      id: true,
      teamDesignation: true,
      shortName: true,
      opponentClub: {
        select: { name: true, shortName: true },
      },
    },
  });

  return rows.map((row) => {
    if (!row.match) return row;
    const identity = competitionTeamIdentity(row.match.opponent);
    const clubKey = normalizedCompetitionName(
      row.match.opponentClubName || identity.clubName,
    );
    const clubCandidates = opponents.filter((opponent) => {
      const aliases = [
        opponent.opponentClub.name,
        opponent.opponentClub.shortName,
        opponent.shortName,
      ].filter((value): value is string => Boolean(value));
      return aliases.some(
        (alias) => normalizedCompetitionName(alias) === clubKey,
      );
    });
    const designation = row.match.opponentTeamDesignation ||
      identity.teamDesignation;
    const exact = designation
      ? clubCandidates.find(
          (opponent) =>
            opponent.teamDesignation.toLocaleUpperCase('de-DE') ===
            designation.toLocaleUpperCase('de-DE'),
        )
      : clubCandidates.length === 1
        ? clubCandidates[0]
        : null;
    if (!exact) {
      const detail = clubCandidates.length && designation
        ? `Verein erkannt, aber Mannschaft ${designation} ist noch nicht angelegt.`
        : 'Noch kein passender Gegnerstammsatz vorhanden.';
      return {
        ...row,
        messages: [
          ...row.messages,
          `${detail} Das Spiel kann trotzdem importiert werden.`,
        ],
      };
    }
    const displayName = `${exact.opponentClub.name} ${exact.teamDesignation}`.trim();
    return {
      ...row,
      match: {
        ...row.match,
        opponent: displayName,
        opponentId: exact.id,
        opponentClubName: exact.opponentClub.name,
        opponentTeamDesignation: exact.teamDesignation,
      },
      messages: [
        ...row.messages,
        `Vorhandenem Gegner „${displayName}“ zugeordnet.`,
      ],
    };
  });
}
