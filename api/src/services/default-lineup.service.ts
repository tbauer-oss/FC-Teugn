import {
  LineupStatus,
  NominationStatus,
  Prisma,
  TeamGameFormat,
} from '@prisma/client';

export type DefaultLineupSlot = {
  playerId: string;
  positionCode: string;
  x: number;
  y: number;
  isGoalkeeper: boolean;
  isCaptain: boolean;
  sortOrder: number;
};

export type LineupCandidate = {
  id: string;
  position: string | null;
  secondaryPosition: string | null;
  shirtNumber: number | null;
};

export type PlannedDefaultLineupPosition = DefaultLineupSlot & {
  playerId: string;
  shirtNumber: number | null;
  replacedPlayerId: string | null;
};

const compatiblePositions: Record<string, Set<string>> = {
  LV: new Set(['IV', 'LA']),
  IV: new Set(['LV', 'RV', 'DM']),
  RV: new Set(['IV', 'RA']),
  DM: new Set(['IV', 'ZM', 'MF']),
  ZM: new Set(['DM', 'OM', 'LM', 'RM', 'MF']),
  LM: new Set(['LA', 'ZM', 'MF']),
  RM: new Set(['RA', 'ZM', 'MF']),
  OM: new Set(['ZM', 'ST', 'LA', 'RA', 'MF']),
  LA: new Set(['LM', 'ST', 'OM']),
  RA: new Set(['RM', 'ST', 'OM']),
  ST: new Set(['LA', 'RA', 'OM']),
  MF: new Set(['DM', 'ZM', 'LM', 'RM', 'OM']),
};

function normalizedPosition(value: string | null) {
  return value?.trim().toUpperCase() ?? '';
}

export function lineupFitScore(
  player: Pick<LineupCandidate, 'position' | 'secondaryPosition'>,
  slotCode: string,
) {
  const slot = normalizedPosition(slotCode);
  const primary = normalizedPosition(player.position);
  const secondary = normalizedPosition(player.secondaryPosition);
  if (primary === slot) return 1000;
  if (secondary === slot) return 850;
  if (slot === 'TW') return primary === 'TW' || secondary === 'TW' ? 1000 : -500;
  if (primary === 'TW') return -1000;
  if (secondary === 'TW' && !primary) return -800;
  if (compatiblePositions[slot]?.has(primary)) return 500;
  if (compatiblePositions[slot]?.has(secondary)) return 400;
  return 0;
}

export function planTeamDefaultLineup(
  slots: DefaultLineupSlot[],
  candidates: LineupCandidate[],
) {
  const remaining = new Map(candidates.map((player) => [player.id, player]));
  const preserved = new Map<string, LineupCandidate>();
  const positions: PlannedDefaultLineupPosition[] = [];
  let automaticReplacements = 0;

  const orderedSlots = [...slots].sort((a, b) => a.sortOrder - b.sortOrder);
  // Reserve every nominated default starter before replacements are selected.
  // Otherwise a missing goalkeeper could consume the available default striker
  // while processing the first slot.
  for (const slot of orderedSlots) {
    const player = remaining.get(slot.playerId);
    if (!player) continue;
    preserved.set(slot.playerId, player);
    remaining.delete(slot.playerId);
  }

  for (const slot of orderedSlots) {
    let selected = preserved.get(slot.playerId) ?? null;
    let replacedPlayerId: string | null = null;
    if (!selected) {
      selected = [...remaining.values()].sort((a, b) => {
        const score = lineupFitScore(b, slot.positionCode) -
          lineupFitScore(a, slot.positionCode);
        if (score !== 0) return score;
        return (a.shirtNumber ?? 999) - (b.shirtNumber ?? 999) ||
          a.id.localeCompare(b.id);
      })[0] ?? null;
      if (selected) {
        automaticReplacements += 1;
        replacedPlayerId = slot.playerId;
      }
    }
    if (!selected) continue;
    if (!preserved.has(slot.playerId)) remaining.delete(selected.id);
    positions.push({
      ...slot,
      playerId: selected.id,
      shirtNumber: selected.shirtNumber,
      replacedPlayerId,
    });
  }

  return { positions, automaticReplacements };
}

export function confirmedLineupCandidates<T extends { id: string }>(
  candidates: T[],
  confirmedPlayerIds: Iterable<string>,
) {
  const confirmed = new Set(confirmedPlayerIds);
  return candidates.filter((candidate) => confirmed.has(candidate.id));
}

export function fieldSizeForGameFormat(format: TeamGameFormat) {
  return Number(String(format).replace('FOOTBALL_', '')) || 7;
}

export function shouldSyncTeamDefaultLineup(
  lineup: { usesTeamDefault: boolean } | null,
  force = false,
) {
  return force || lineup === null || lineup.usesTeamDefault;
}

export async function syncSquadWithTeamDefaultLineup(
  tx: Prisma.TransactionClient,
  {
    teamId,
    squadId,
    fieldSize,
    force = false,
  }: {
    teamId: string;
    squadId: string;
    fieldSize: number;
    force?: boolean;
  },
) {
  const [team, squad] = await Promise.all([
    tx.team.findUnique({
      where: { id: teamId },
      select: {
        defaultFormation: true,
        defaultLineupPositions: {
          orderBy: { sortOrder: 'asc' },
          select: {
            playerId: true,
            positionCode: true,
            x: true,
            y: true,
            isGoalkeeper: true,
            isCaptain: true,
            sortOrder: true,
          },
        },
      },
    }),
    tx.squad.findUnique({
      where: { id: squadId },
      select: {
        lineup: {
          select: { id: true, usesTeamDefault: true },
        },
        members: {
          where: { status: NominationStatus.NOMINATED },
          select: {
            player: {
              select: {
                id: true,
                position: true,
                secondaryPosition: true,
                shirtNumber: true,
              },
            },
          },
        },
      },
    }),
  ]);

  if (!team || !squad || team.defaultLineupPositions.length === 0) return null;
  if (!shouldSyncTeamDefaultLineup(squad.lineup, force)) return null;

  // The matchday draft follows the nominated squad immediately. Attendance
  // replies can arrive much later and must not hide the saved team lineup.
  const planned = planTeamDefaultLineup(
    team.defaultLineupPositions.slice(0, fieldSize),
    squad.members.map((member) => member.player),
  );
  const lineup = await tx.lineup.upsert({
    where: { squadId },
    update: {
      formation: team.defaultFormation ?? 'Individuell',
      fieldSize,
      usesTeamDefault: true,
      automaticReplacements: planned.automaticReplacements,
    },
    create: {
      squadId,
      formation: team.defaultFormation ?? 'Individuell',
      fieldSize,
      status: LineupStatus.DRAFT,
      usesTeamDefault: true,
      automaticReplacements: planned.automaticReplacements,
    },
  });
  await tx.lineupPosition.deleteMany({ where: { lineupId: lineup.id } });
  if (planned.positions.length > 0) {
    await tx.lineupPosition.createMany({
      data: planned.positions.map((position) => ({
        lineupId: lineup.id,
        playerId: position.playerId,
        period: 1,
        positionCode: position.positionCode,
        x: position.x,
        y: position.y,
        isStarter: true,
        isGoalkeeper: position.isGoalkeeper,
        isCaptain: position.isCaptain,
        shirtNumber: position.shirtNumber,
      })),
    });
  }
  return lineup;
}
