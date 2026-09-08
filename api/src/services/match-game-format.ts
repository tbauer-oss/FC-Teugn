import { Prisma, TeamGameFormat } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { DomainError } from './talents-domain';

export function matchFormatsForAge(code: string): TeamGameFormat[] {
  const sizes = code.toUpperCase() === 'G' ? ['2', '3']
    : code.toUpperCase() === 'F' ? ['3', '4_MINI', '4', '5']
      : code.toUpperCase() === 'E' ? ['4_MINI', '4', '5', '7']
        : code.toUpperCase() === 'D' ? ['6', '7', '9']
          : ['A', 'B', 'C'].includes(code.toUpperCase()) ? ['7', '9', '11'] : ['11'];
  return sizes.map((size) => `FOOTBALL_${size}` as TeamGameFormat);
}

export function gameFormatSize(format: string) {
  return Number(/^FOOTBALL_(\d+)/.exec(format)?.[1]) || 7;
}
export function gameFormatHasKeeper(format: string) {
  return gameFormatSize(format) > 3 && format !== 'FOOTBALL_4_MINI';
}

export async function prepareMatchGameFormat(input: unknown, teamId: string) {
  if (input === undefined) return { gameFormat: undefined, error: null };
  const team = await prisma.team.findUnique({ where: { id: teamId }, select: { ageGroup: { select: { code: true } } } });
  const gameFormat = input as TeamGameFormat;
  if (!team || !matchFormatsForAge(team.ageGroup.code).includes(gameFormat)) {
    return { gameFormat: undefined, error: 'Bitte eine für diese Jugend vorgesehene BFV-Spielform auswählen.' };
  }
  return { gameFormat, error: null };
}

/** Runs in the same transaction as the format write, so no old lineup survives. */
export async function resetLineupForGameFormat(tx: Prisma.TransactionClient, eventId: string, gameFormat: TeamGameFormat | undefined) {
  if (gameFormat === undefined) return;
  const event = await tx.event.findUnique({ where: { id: eventId }, select: {
    team: { select: { gameFormat: true } },
    targetTeams: { include: { team: { select: { gameFormat: true } } } },
    matchDetails: { select: { gameFormat: true, status: true } },
  } });
  if (!event || gameFormat === (event.matchDetails?.gameFormat ?? event.targetTeams[0]?.team.gameFormat ?? event.team.gameFormat)) return;
  if (event.matchDetails && ['LIVE', 'HALF_TIME', 'INTERRUPTED', 'FINISHED', 'RECORDED'].includes(event.matchDetails.status)) {
    throw new DomainError(409, 'Die Spielform kann nach Spielbeginn nicht mehr geändert werden.');
  }
  await tx.lineup.deleteMany({ where: { squad: { eventId } } });
  await tx.squad.updateMany({ where: { eventId }, data: { formation: null } });
}
