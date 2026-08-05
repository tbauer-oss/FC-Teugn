import { Request, Response } from 'express';
import {
  EventType,
  AccountStatus,
  LineupStatus,
  MatchKind,
  MatchStatus,
  NominationStatus,
  PlayerStatus,
  Prisma,
  TickerEventType,
  TickerStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { Role } from '../types/enums';
import { recalculateMatchStatistics } from '../services/statistics.service';
import { rosterTeamIdsForMatch } from '../services/match-roster';
import {
  accessibleTeamIds,
  contextualTeamIds,
  ownPlayerIds,
  youthPlayerPoolTeamIdsForTeam,
} from '../services/team-access';
import { syncSquadWithTeamDefaultLineup } from '../services/default-lineup.service';

const matchInclude = {
  team: {
    select: {
      id: true,
      gameFormat: true,
      defaultFormation: true,
      customFormations: true,
      ageGroup: { select: { code: true } },
    },
  },
  targetTeams: {
    include: {
      team: {
        select: {
          id: true,
          name: true,
          shortName: true,
          gameFormat: true,
          defaultFormation: true,
          customFormations: true,
        },
      },
    },
  },
  matchDetails: true,
  attendance: {
    include: {
      player: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
          shirtNumber: true,
          position: true,
          secondaryPosition: true,
          status: true,
          photoUrl: true,
        },
      },
    },
  },
  squads: {
    include: {
      members: {
        include: {
          player: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              preferredName: true,
              shirtNumber: true,
              position: true,
              secondaryPosition: true,
              status: true,
              photoUrl: true,
            },
          },
        },
      },
      lineup: {
        include: {
          positions: {
            include: {
              player: {
                select: {
                  id: true,
                  firstName: true,
                  lastName: true,
                  preferredName: true,
                  shirtNumber: true,
                  photoUrl: true,
                },
              },
            },
          },
          substitutions: true,
        },
      },
    },
  },
  liveTicker: {
    include: {
      events: {
        where: { revokedAt: null },
        orderBy: { sequence: 'asc' as const },
        include: {
          scorer: { select: { id: true, firstName: true, lastName: true, preferredName: true } },
          assist: { select: { id: true, firstName: true, lastName: true, preferredName: true } },
        },
      },
    },
  },
} as const;

const eligiblePlayerSelect = {
  id: true,
  teamId: true,
  firstName: true,
  lastName: true,
  preferredName: true,
  birthDate: true,
  nationality: true,
  position: true,
  secondaryPosition: true,
  dominantFoot: true,
  shirtNumber: true,
  status: true,
  joinedAt: true,
  photoUrl: true,
  team: {
    select: {
      id: true,
      name: true,
      teamNumber: true,
      ageGroup: { select: { id: true, name: true, code: true } },
    },
  },
} as const;

function text(value: unknown, max = 300) {
  if (typeof value !== 'string') return null;
  const result = value.trim();
  return result ? result.slice(0, max) : null;
}

function integer(value: unknown, minimum: number, maximum: number, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum ? parsed : fallback;
}

function enumValue<T extends Record<string, string>>(
  values: T,
  value: unknown,
  fallback: T[keyof T],
) {
  const normalized = String(value ?? '').toUpperCase();
  return (Object.values(values) as string[]).includes(normalized)
    ? (normalized as T[keyof T])
    : fallback;
}

function scope(teamIds: string[]): Prisma.EventWhereInput {
  return {
    type: EventType.MATCH,
    OR: [{ teamId: { in: teamIds } }, { targetTeams: { some: { teamId: { in: teamIds } } } }],
  };
}

function isStaff(role: Role) {
  return hasPermission(role, Permission.MANAGE_EVENTS);
}

async function canManageTicker(
  user: { id: string; role: Role },
  eventId: string,
) {
  if (hasPermission(user.role, Permission.MANAGE_LIVE_TICKER)) return true;
  if (user.role !== Role.PARENT) return false;
  const delegation = await prisma.matchTickerDelegate.findFirst({
    where: {
      eventId,
      userId: user.id,
      revokedAt: null,
      event: {
        matchDetails: {
          is: {
            status: {
              notIn: [MatchStatus.FINISHED, MatchStatus.RECORDED, MatchStatus.CANCELLED],
            },
          },
        },
      },
    },
    select: { id: true },
  });
  return delegation !== null;
}

async function findMatch(id: string, user: { id: string; teamId: string; role: Role }) {
  const teamIds = await accessibleTeamIds(user);
  return prisma.event.findFirst({ where: { id, ...scope(teamIds) }, include: matchInclude });
}

async function findMatchForSquadUpdate(
  id: string,
  user: { id: string; teamId: string; role: Role },
) {
  const teamIds = await accessibleTeamIds(user);
  return prisma.event.findFirst({
    where: { id, ...scope(teamIds) },
    select: {
      id: true,
      teamId: true,
      team: { select: { id: true, gameFormat: true } },
      targetTeams: {
        select: {
          team: { select: { id: true, gameFormat: true } },
        },
      },
    },
  });
}

function serializeMatch<T extends Prisma.EventGetPayload<{ include: typeof matchInclude }>>(
  match: T,
  staff: boolean,
  eligiblePlayers: Array<Prisma.PlayerGetPayload<{ select: typeof eligiblePlayerSelect }>> = [],
  tickerEditable = staff,
  viewerPlayerIds: string[] = [],
) {
  const squad = match.squads[0] ?? null;
  const lineup = squad?.lineup;
  const lineupTeam = match.targetTeams[0]?.team ?? match.team;
  const canSeeLineup =
    staff ||
    (squad?.publishedAt !== null &&
      squad?.members.some((member) => viewerPlayerIds.includes(member.playerId)) === true &&
      lineup?.status === LineupStatus.PUBLISHED &&
      (!lineup.visibleAt || lineup.visibleAt.getTime() <= Date.now()));
  const canSeePublishedSquad = staff || tickerEditable || (
    squad?.publishedAt !== null &&
    squad?.members.some((member) => viewerPlayerIds.includes(member.playerId)) === true
  );
  return {
    ...match,
    attendance: staff
      ? match.attendance
      : match.attendance.filter((item) => viewerPlayerIds.includes(item.playerId)),
    teamGameFormat:
      lineupTeam.gameFormat,
    teamDefaultFormation: lineupTeam.defaultFormation,
    teamFormationOptions: [...new Set([
      ...(lineupTeam.defaultFormation ? [lineupTeam.defaultFormation] : []),
      ...lineupTeam.customFormations,
    ])],
    playerPoolAgeGroupCode: match.team.ageGroup.code,
    eligiblePlayers: staff ? eligiblePlayers : undefined,
    capabilities: {
      canManageTicker: tickerEditable,
      canDelegateTicker: staff,
    },
    squads: squad && canSeePublishedSquad
      ? [
          {
            ...squad,
            members: staff
              ? squad.members
              : squad.members.filter(
                  (member) => member.status === NominationStatus.NOMINATED,
                ),
            lineup: canSeeLineup
              ? {
                  ...lineup,
                  tacticalNote: staff ? lineup?.tacticalNote : null,
                }
              : null,
          },
        ]
      : [],
    liveTicker: match.liveTicker
      ? {
          ...match.liveTicker,
          events: match.liveTicker.events.map((event) => ({
            ...event,
            scorer: tickerEditable || match.liveTicker?.publicScorersEnabled ? event.scorer : null,
            assist: tickerEditable || match.liveTicker?.publicScorersEnabled ? event.assist : null,
          })),
        }
      : null,
  };
}

export async function listMatches(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await contextualTeamIds(user);
  const from = req.query.from ? new Date(String(req.query.from)) : undefined;
  const to = req.query.to ? new Date(String(req.query.to)) : undefined;
  const matches = await prisma.event.findMany({
    where: {
      ...scope(teamIds),
      ...(from || to
        ? {
            startAt: {
              ...(from && !Number.isNaN(from.getTime()) ? { gte: from } : {}),
              ...(to && !Number.isNaN(to.getTime()) ? { lte: to } : {}),
            },
          }
        : {}),
    },
    include: matchInclude,
    orderBy: { startAt: 'desc' },
    take: 100,
  });
  const viewerPlayerIds = isStaff(user.role) ? [] : await ownPlayerIds(user);
  return res.json(matches.map((match) =>
    serializeMatch(match, isStaff(user.role), [], false, viewerPlayerIds),
  ));
}

export async function getMatch(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const staff = isStaff(user.role);
  const tickerEditable = await canManageTicker(user, match.id);
  const rosterTeamIds = rosterTeamIdsForMatch(
    await youthPlayerPoolTeamIdsForTeam(match.teamId),
  );
  const eligiblePlayers = staff
    ? await prisma.player.findMany({
        where: {
          teamId: { in: rosterTeamIds },
          status: { in: [PlayerStatus.ACTIVE, PlayerStatus.INJURED] },
        },
        select: eligiblePlayerSelect,
        orderBy: [{ status: 'asc' }, { lastName: 'asc' }, { firstName: 'asc' }],
      })
    : [];
  const viewerPlayerIds = staff ? [] : await ownPlayerIds(user);
  return res.json(serializeMatch(
    match,
    staff,
    eligiblePlayers,
    tickerEditable,
    viewerPlayerIds,
  ));
}

export async function getTickerDelegation(req: Request, res: Response) {
  const user = req.user!;
  if (!hasPermission(user.role, Permission.MANAGE_LIVE_TICKER)) {
    return res.status(403).json({ message: 'Keine Berechtigung für diese Freigabe.' });
  }
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const teamIds = [
    match.teamId,
    ...match.targetTeams.map((target) => target.teamId),
  ];
  const candidates = await prisma.user.findMany({
    where: {
      status: AccountStatus.APPROVED,
      parentLinks: {
        some: { player: { teamId: { in: teamIds } } },
      },
    },
    select: { id: true, name: true, email: true },
    orderBy: { name: 'asc' },
  });
  const delegation = await prisma.matchTickerDelegate.findUnique({
    where: { eventId: match.id },
    include: { user: { select: { id: true, name: true, email: true } } },
  });
  return res.json({
    delegate:
      delegation && delegation.revokedAt === null ? delegation.user : null,
    candidates,
  });
}

export async function updateTickerDelegation(req: Request, res: Response) {
  const user = req.user!;
  if (!hasPermission(user.role, Permission.MANAGE_LIVE_TICKER)) {
    return res.status(403).json({ message: 'Keine Berechtigung für diese Freigabe.' });
  }
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const closedStatuses = new Set<MatchStatus>([
    MatchStatus.FINISHED,
    MatchStatus.RECORDED,
    MatchStatus.CANCELLED,
  ]);
  if (closedStatuses.has(match.matchDetails?.status ?? MatchStatus.PLANNED)) {
    return res.status(400).json({ message: 'Für dieses Spiel kann keine Freigabe mehr erteilt werden.' });
  }
  const parentId = text(req.body?.parentId, 100);
  if (!parentId) {
    await prisma.matchTickerDelegate.deleteMany({ where: { eventId: match.id } });
    return res.json({ delegate: null });
  }
  const teamIds = [match.teamId, ...match.targetTeams.map((target) => target.teamId)];
  const parent = await prisma.user.findFirst({
    where: {
      id: parentId,
      status: AccountStatus.APPROVED,
      parentLinks: { some: { player: { teamId: { in: teamIds } } } },
    },
    select: { id: true, name: true, email: true },
  });
  if (!parent) {
    return res.status(400).json({ message: 'Das Elternkonto gehört nicht zu diesem Spiel.' });
  }
  await prisma.matchTickerDelegate.upsert({
    where: { eventId: match.id },
    update: { userId: parent.id, grantedById: user.id, revokedAt: null },
    create: { eventId: match.id, userId: parent.id, grantedById: user.id },
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: match.teamId,
      action: 'MATCH_TICKER_DELEGATED',
      entityType: 'Event',
      entityId: match.id,
      metadata: { parentId: parent.id },
    },
  });
  return res.json({ delegate: parent });
}

export async function updateMatch(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const body = req.body ?? {};
  const opponent = text(body.opponent, 120);
  if (!opponent) return res.status(400).json({ message: 'Der Gegner ist erforderlich.' });
  const bfvUrl = text(body.bfvUrl, 500);
  if (bfvUrl) {
    try {
      if (!['http:', 'https:'].includes(new URL(bfvUrl).protocol)) throw new Error();
    } catch {
      return res.status(400).json({ message: 'Die BFV-URL ist ungültig.' });
    }
  }
  const periodCount = Number(
    body.periodCount ?? match.matchDetails?.periodCount ?? 2,
  );
  const periodMinutes = Number(
    body.periodMinutes ?? match.matchDetails?.periodMinutes ?? 30,
  );
  if (
    !Number.isInteger(periodCount) ||
    periodCount < 1 ||
    periodCount > 8 ||
    !Number.isInteger(periodMinutes) ||
    periodMinutes < 1 ||
    periodMinutes > 90 ||
    periodCount * periodMinutes > 180
  ) {
    return res.status(400).json({
      message:
        'Bitte 1–8 Spielabschnitte und 1–90 Minuten je Abschnitt angeben (maximal 180 Minuten insgesamt).',
    });
  }
  const durationMinutes = periodCount * periodMinutes;
  const details = await prisma.matchDetails.upsert({
    where: { eventId: match.id },
    update: {
      opponent,
      opponentShortName: text(body.opponentShortName, 30),
      opponentLogoUrl: text(body.opponentLogoUrl, 500),
      isHome: body.isHome !== false,
      kind: enumValue(MatchKind, body.kind, MatchKind.FRIENDLY),
      status: enumValue(MatchStatus, body.status, MatchStatus.PLANNED),
      competition: text(body.competition, 120),
      division: text(body.division, 120),
      matchDay: text(body.matchDay, 50),
      pitch: text(body.pitch, 100),
      referee: text(body.referee, 100),
      durationMinutes,
      periodMinutes,
      periodCount,
      bfvMatchId: text(body.bfvMatchId, 100),
      bfvUrl,
      notes: text(body.notes, 2000),
    },
    create: {
      eventId: match.id,
      opponent,
      opponentShortName: text(body.opponentShortName, 30),
      opponentLogoUrl: text(body.opponentLogoUrl, 500),
      isHome: body.isHome !== false,
      kind: enumValue(MatchKind, body.kind, MatchKind.FRIENDLY),
      status: enumValue(MatchStatus, body.status, MatchStatus.PLANNED),
      competition: text(body.competition, 120),
      division: text(body.division, 120),
      matchDay: text(body.matchDay, 50),
      pitch: text(body.pitch, 100),
      referee: text(body.referee, 100),
      durationMinutes,
      periodMinutes,
      periodCount,
      bfvMatchId: text(body.bfvMatchId, 100),
      bfvUrl,
      notes: text(body.notes, 2000),
    },
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: match.teamId,
      action: 'MATCH_UPDATED',
      entityType: 'MatchDetails',
      entityId: details.id,
      metadata: { status: details.status, opponent: details.opponent },
    },
  });
  return res.json(details);
}

export async function updateSquad(req: Request, res: Response) {
  const user = req.user!;
  // Dieser Endpunkt benötigt weder Ticker noch Statistiken oder die komplette
  // bestehende Aufstellung. Die schlanke Abfrage spart bei jedem Speichern
  // mehrere große Joins in der Produktionsdatenbank.
  const match = await findMatchForSquadUpdate(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const members = Array.isArray(req.body?.members) ? req.body.members : [];
  const ids = [...new Set(members.map((item: { playerId?: unknown }) => text(item.playerId, 100)).filter(Boolean))] as string[];
  const rosterTeamIds = rosterTeamIdsForMatch(
    await youthPlayerPoolTeamIdsForTeam(match.teamId),
  );
  const validPlayers = await prisma.player.findMany({
    where: {
      id: { in: ids },
      teamId: { in: rosterTeamIds },
      status: { in: [PlayerStatus.ACTIVE, PlayerStatus.INJURED] },
    },
    select: { id: true },
  });
  if (validPlayers.length !== ids.length) {
    return res.status(400).json({ message: 'Mindestens ein Spieler gehört nicht zum verfügbaren Kader.' });
  }
  const squad = await prisma.$transaction(async (tx) => {
    const saved = await tx.squad.upsert({
      where: { eventId: match.id },
      update: { name: text(req.body.name, 100), formation: text(req.body.formation, 50) },
      create: {
        eventId: match.id,
        name: text(req.body.name, 100),
        formation: text(req.body.formation, 50),
      },
    });
    await Promise.all([
      tx.squadMember.deleteMany({ where: { squadId: saved.id } }),
      tx.eventParticipant.deleteMany({
        where: { eventId: match.id, playerId: { not: null } },
      }),
      tx.attendance.deleteMany({
        where: { eventId: match.id, playerId: { notIn: ids } },
      }),
    ]);
    const writes: Prisma.PrismaPromise<unknown>[] = [
      tx.event.update({
        where: { id: match.id },
        data: { reminderSyncPendingAt: new Date() },
      }),
      tx.auditLog.create({
        data: {
          actorId: user.id,
          teamId: match.teamId,
          action: 'MATCH_SQUAD_UPDATED',
          entityType: 'Squad',
          entityId: saved.id,
          metadata: { memberCount: members.length },
        },
      }),
    ];
    if (members.length) {
      writes.push(
        tx.squadMember.createMany({
          data: members.map((item: Record<string, unknown>) => ({
            squadId: saved.id,
            playerId: String(item.playerId),
            status: enumValue(NominationStatus, item.status, NominationStatus.NOMINATED),
            note: text(item.note, 300),
            plannedMinutes:
              item.plannedMinutes == null
                ? null
                : integer(item.plannedMinutes, 0, 300, 0),
          })),
          skipDuplicates: true,
        }),
      );
    }
    if (ids.length) {
      writes.push(
        tx.eventParticipant.createMany({
          data: ids.map((playerId) => ({
            eventId: match.id,
            playerId,
            responseRequired: true,
          })),
          skipDuplicates: true,
        }),
        tx.attendance.createMany({
          data: ids.map((playerId) => ({ eventId: match.id, playerId })),
          skipDuplicates: true,
        }),
      );
    }
    await Promise.all(writes);
    await syncSquadWithTeamDefaultLineup(tx, {
      teamId: match.targetTeams[0]?.team.id ?? match.team.id,
      squadId: saved.id,
      fieldSize: Number(
        String(
          match.targetTeams[0]?.team.gameFormat ?? match.team.gameFormat,
        ).replace('FOOTBALL_', ''),
      ),
    });
    return tx.squad.findUnique({
      where: { id: saved.id },
      include: {
        members: { include: { player: true } },
        lineup: {
          include: {
            positions: { include: { player: true } },
            substitutions: true,
          },
        },
      },
    });
  });
  // Die Antwort hängt ausschließlich vom atomaren Kader-Commit ab.
  // Erinnerungsjobs werden durch den Cron anhand reminderSyncPendingAt
  // zuverlässig nachgezogen und blockieren diese Kernfunktion nie wieder.
  return res.json(squad);
}

export async function publishSquad(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const squad = await prisma.squad.findUnique({
    where: { eventId: match.id },
    include: {
      members: {
        where: { status: { not: NominationStatus.DECLINED } },
        include: {
          player: {
            include: {
              parentLinks: {
                where: { receivesCommunication: true },
                select: { parentId: true },
              },
            },
          },
        },
      },
    },
  });
  if (!squad) return res.status(400).json({ message: 'Zuerst muss ein Kader gespeichert werden.' });
  const recipients = new Map<string, string[]>();
  for (const member of squad.members) {
    const playerName = member.player.preferredName || member.player.firstName;
    if (member.player.userId) {
      recipients.set(member.player.userId, [
        ...(recipients.get(member.player.userId) ?? []),
        playerName,
      ]);
    }
    for (const link of member.player.parentLinks) {
      recipients.set(link.parentId, [
        ...(recipients.get(link.parentId) ?? []),
        playerName,
      ]);
    }
  }
  const updated = await prisma.$transaction(async (tx) => {
    const saved = await tx.squad.update({
      where: { id: squad.id },
      data: { publishedAt: new Date() },
    });
    for (const [recipientId, playerNames] of recipients) {
      const names = [...new Set(playerNames)].join(', ');
      await tx.notification.upsert({
        where: { dedupeKey: `nomination:${match.id}:${recipientId}` },
        update: {
          title: 'Kader veröffentlicht',
          body: `Die Kadernominierung für ${names} wurde veröffentlicht.`,
          readAt: null,
        },
        create: {
          userId: recipientId,
          category: 'NOMINATION',
          title: 'Kader veröffentlicht',
          body: `Die Kadernominierung für ${names} wurde veröffentlicht.`,
          actionUrl: `/matches/${match.id}`,
          entityType: 'Event',
          entityId: match.id,
          dedupeKey: `nomination:${match.id}:${recipientId}`,
        },
      });
    }
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'MATCH_SQUAD_PUBLISHED',
        entityType: 'Squad',
        entityId: squad.id,
        metadata: { recipientCount: recipients.size },
      },
    });
    return saved;
  });
  return res.json(updated);
}

export async function updateLineup(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const squad = await prisma.squad.findUnique({
    where: { eventId: match.id },
    include: { members: true },
  });
  if (!squad) return res.status(400).json({ message: 'Zuerst muss ein Kader gespeichert werden.' });
  const positions = Array.isArray(req.body?.positions) ? req.body.positions : [];
  const substitutions = Array.isArray(req.body?.substitutions) ? req.body.substitutions : [];
  const fieldSize = Number(
    String(
      match.targetTeams[0]?.team.gameFormat ?? match.team.gameFormat,
    ).replace('FOOTBALL_', ''),
  );
  const starters = positions.filter(
    (position: Record<string, unknown>) => position.isStarter !== false,
  );
  if (starters.length > fieldSize) {
    return res.status(400).json({
      message: `Für diese Mannschaft sind höchstens ${fieldSize} Startspieler vorgesehen.`,
    });
  }
  const memberIds = new Set(
    squad.members
      .filter((member) => member.status !== NominationStatus.DECLINED)
      .map((member) => member.playerId),
  );
  for (const position of positions as Record<string, unknown>[]) {
    if (!memberIds.has(String(position.playerId))) {
      return res.status(400).json({ message: 'Die Aufstellung enthält einen nicht nominierten Spieler.' });
    }
    const x = Number(position.x);
    const y = Number(position.y);
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
      return res.status(400).json({ message: 'Ungültige Spielfeldposition.' });
    }
  }
  const positionKeys = new Set<string>();
  for (const position of positions as Record<string, unknown>[]) {
    const key = `${position.playerId}:${integer(position.period, 1, 8, 1)}`;
    if (positionKeys.has(key)) {
      return res.status(400).json({ message: 'Ein Spieler ist im selben Abschnitt doppelt aufgestellt.' });
    }
    positionKeys.add(key);
  }
  const periodCount = match.matchDetails?.periodCount ?? 2;
  const periodMinutes = match.matchDetails?.periodMinutes ?? 30;
  for (const substitution of substitutions as Record<string, unknown>[]) {
    const playerInId = String(substitution.playerInId ?? '');
    const playerOutId = String(substitution.playerOutId ?? '');
    if (!memberIds.has(playerInId) || !memberIds.has(playerOutId)) {
      return res.status(400).json({
        message: 'Der Wechselplan enthält einen nicht nominierten Spieler.',
      });
    }
    if (!playerInId || playerInId === playerOutId) {
      return res.status(400).json({ message: 'Ungültiger geplanter Wechsel.' });
    }
    const period = integer(substitution.period, 1, periodCount, 1);
    if (Number(substitution.period ?? 1) !== period) {
      return res.status(400).json({ message: 'Ungültiger Spielabschnitt im Wechselplan.' });
    }
    if (substitution.minute != null) {
      const minute = integer(substitution.minute, 0, periodMinutes, 0);
      if (Number(substitution.minute) !== minute) {
        return res.status(400).json({ message: 'Ungültige Minute im Wechselplan.' });
      }
    }
  }
  const saved = await prisma.$transaction(async (tx) => {
    const lineup = await tx.lineup.upsert({
      where: { squadId: squad.id },
      update: {
        formation: text(req.body.formation, 50) ?? 'Individuell',
        fieldSize,
        status: enumValue(LineupStatus, req.body.status, LineupStatus.DRAFT),
        publicNote: text(req.body.publicNote, 1000),
        tacticalNote: text(req.body.tacticalNote, 2000),
        visibleAt: req.body.visibleAt ? new Date(String(req.body.visibleAt)) : null,
        ...(String(req.body.status).toUpperCase() === LineupStatus.PUBLISHED
          ? { publishedAt: new Date() }
          : {}),
        usesTeamDefault: false,
        automaticReplacements: 0,
      },
      create: {
        squadId: squad.id,
        formation: text(req.body.formation, 50) ?? 'Individuell',
        fieldSize,
        status: enumValue(LineupStatus, req.body.status, LineupStatus.DRAFT),
        publicNote: text(req.body.publicNote, 1000),
        tacticalNote: text(req.body.tacticalNote, 2000),
        visibleAt: req.body.visibleAt ? new Date(String(req.body.visibleAt)) : null,
        ...(String(req.body.status).toUpperCase() === LineupStatus.PUBLISHED
          ? { publishedAt: new Date() }
          : {}),
        usesTeamDefault: false,
        automaticReplacements: 0,
      },
    });
    await tx.lineupPosition.deleteMany({ where: { lineupId: lineup.id } });
    await tx.plannedSubstitution.deleteMany({ where: { lineupId: lineup.id } });
    if (positions.length) {
      await tx.lineupPosition.createMany({
        data: (positions as Record<string, unknown>[]).map((position) => ({
          lineupId: lineup.id,
          playerId: String(position.playerId),
          period: integer(position.period, 1, 8, 1),
          positionCode: text(position.positionCode, 30) ?? 'FELD',
          x: Number(position.x),
          y: Number(position.y),
          isStarter: position.isStarter !== false,
          isGoalkeeper: position.isGoalkeeper === true,
          isCaptain: position.isCaptain === true,
          shirtNumber:
            position.shirtNumber == null ? null : integer(position.shirtNumber, 0, 99, 0),
        })),
      });
    }
    if (substitutions.length) {
      await tx.plannedSubstitution.createMany({
        data: (substitutions as Record<string, unknown>[]).map((substitution) => ({
          lineupId: lineup.id,
          period: integer(substitution.period, 1, periodCount, 1),
          minute:
            substitution.minute == null
              ? null
              : integer(substitution.minute, 0, periodMinutes, 0),
          playerInId: String(substitution.playerInId),
          playerOutId: String(substitution.playerOutId),
          note: text(substitution.note, 500),
        })),
      });
    }
    return tx.lineup.findUnique({
      where: { id: lineup.id },
      include: { positions: { include: { player: true } }, substitutions: true },
    });
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: match.teamId,
      action:
        saved?.status === LineupStatus.PUBLISHED ? 'MATCH_LINEUP_PUBLISHED' : 'MATCH_LINEUP_UPDATED',
      entityType: 'Lineup',
      entityId: saved?.id,
      metadata: {
        status: saved?.status,
        positions: positions.length,
        substitutions: substitutions.length,
      },
    },
  });
  return res.json(saved);
}

function elapsed(ticker: {
  elapsedSeconds: number;
  clockStartedAt: Date | null;
  status: TickerStatus;
}) {
  if (ticker.status !== TickerStatus.LIVE || !ticker.clockStartedAt) return ticker.elapsedSeconds;
  return ticker.elapsedSeconds + Math.max(0, Math.floor((Date.now() - ticker.clockStartedAt.getTime()) / 1000));
}

export async function getTicker(req: Request, res: Response) {
  const match = await findMatch(req.params.id, req.user!);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const after = integer(req.query.after, 0, Number.MAX_SAFE_INTEGER, 0);
  const ticker = await prisma.liveTicker.findUnique({
    where: { eventId: match.id },
    include: {
      events: {
        where: { sequence: { gt: after } },
        orderBy: { sequence: 'asc' },
        take: 250,
        include: {
          scorer: { select: { id: true, firstName: true, lastName: true, preferredName: true } },
          assist: { select: { id: true, firstName: true, lastName: true, preferredName: true } },
        },
      },
    },
  });
  if (!ticker) {
    return res.json({
      status: TickerStatus.NOT_STARTED,
      currentPeriod: 1,
      elapsedSeconds: 0,
      ourGoals: 0,
      theirGoals: 0,
      lastSequence: 0,
      events: [],
    });
  }
  const tickerEditable = await canManageTicker(req.user!, match.id);
  return res.json({
    ...ticker,
    elapsedSeconds: elapsed(ticker),
    events: ticker.events.map((event) => ({
      ...event,
      scorer: tickerEditable || ticker.publicScorersEnabled ? event.scorer : null,
      assist: tickerEditable || ticker.publicScorersEnabled ? event.assist : null,
    })),
  });
}

const goalTypes = new Set<TickerEventType>([
  TickerEventType.HOME_GOAL,
  TickerEventType.AWAY_GOAL,
]);

export async function tickerCommand(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  if (!(await canManageTicker(user, match.id))) {
    return res.status(403).json({ message: 'Der Liveticker ist für dieses Konto nicht freigegeben.' });
  }
  const clientEventId = text(req.body?.clientEventId, 100);
  if (!clientEventId) return res.status(400).json({ message: 'clientEventId ist erforderlich.' });
  const type = enumValue(TickerEventType, req.body?.type, TickerEventType.COMMENT);
  const fcIsHome = match.matchDetails?.isHome !== false;
  const isOurGoal =
    (fcIsHome && type === TickerEventType.HOME_GOAL) ||
    (!fcIsHome && type === TickerEventType.AWAY_GOAL);
  const allowedPlayerIds = new Set(
    match.squads[0]?.members
      .filter((member) => member.status === NominationStatus.NOMINATED)
      .map((member) => member.playerId) ?? [],
  );
  const scorerId = text(req.body?.scorerId, 100);
  const assistId = text(req.body?.assistId, 100);
  if (isOurGoal && !scorerId) {
    return res
      .status(400)
      .json({ message: 'Bei einem eigenen Tor ist der Torschütze erforderlich.' });
  }
  if (
    (scorerId && !allowedPlayerIds.has(scorerId)) ||
    (assistId && !allowedPlayerIds.has(assistId))
  ) {
    return res
      .status(400)
      .json({ message: 'Torschütze oder Vorlagengeber gehört nicht zum Kader.' });
  }
  if (scorerId && scorerId === assistId) {
    return res.status(400).json({ message: 'Torschütze und Vorlagengeber müssen verschieden sein.' });
  }
  const result = await prisma.$transaction(async (tx) => {
    let ticker = await tx.liveTicker.upsert({
      where: { eventId: match.id },
      update: {},
      create: { eventId: match.id },
    });
    const duplicate = await tx.liveTickerEvent.findUnique({
      where: { tickerId_clientEventId: { tickerId: ticker.id, clientEventId } },
      include: { scorer: true, assist: true },
    });
    if (duplicate) return { ticker, event: duplicate, duplicate: true };

    const now = new Date();
    const currentElapsed = elapsed(ticker);
    let status = ticker.status;
    let clockStartedAt = ticker.clockStartedAt;
    let elapsedSeconds = currentElapsed;
    let currentPeriod = ticker.currentPeriod;
    let ourGoals = ticker.ourGoals;
    let theirGoals = ticker.theirGoals;
    let startedAt = ticker.startedAt;
    let finishedAt = ticker.finishedAt;

    if (type === TickerEventType.MATCH_START || type === TickerEventType.RESUME || type === TickerEventType.PERIOD_START) {
      status = TickerStatus.LIVE;
      clockStartedAt = now;
      startedAt ??= now;
    } else if (type === TickerEventType.PERIOD_END) {
      status = TickerStatus.HALF_TIME;
      clockStartedAt = null;
    } else if (type === TickerEventType.INTERRUPTION || type === TickerEventType.INJURY) {
      status = TickerStatus.INTERRUPTED;
      clockStartedAt = null;
    } else if (type === TickerEventType.MATCH_END) {
      status = TickerStatus.FINISHED;
      clockStartedAt = null;
      finishedAt = now;
    } else if (type === TickerEventType.HOME_GOAL) {
      if (match.matchDetails?.isHome !== false) ourGoals += 1;
      else theirGoals += 1;
    } else if (type === TickerEventType.AWAY_GOAL) {
      if (match.matchDetails?.isHome !== false) theirGoals += 1;
      else ourGoals += 1;
    }
    if (req.body?.period != null) currentPeriod = integer(req.body.period, 1, 8, currentPeriod);
    if (req.body?.elapsedSeconds != null) {
      elapsedSeconds = integer(req.body.elapsedSeconds, 0, 10800, currentElapsed);
      if (status === TickerStatus.LIVE) clockStartedAt = now;
    }
    const sequence = ticker.lastSequence + 1;
    ticker = await tx.liveTicker.update({
      where: { id: ticker.id },
      data: {
        status,
        currentPeriod,
        elapsedSeconds,
        clockStartedAt,
        ourGoals,
        theirGoals,
        lastSequence: sequence,
        startedAt,
        finishedAt,
        publicScorersEnabled:
          req.body?.publicScorersEnabled == null
            ? ticker.publicScorersEnabled
            : req.body.publicScorersEnabled === true,
      },
    });
    const event = await tx.liveTickerEvent.create({
      data: {
        tickerId: ticker.id,
        clientEventId,
        sequence,
        type,
        period: currentPeriod,
        elapsedSeconds,
        ourGoals,
        theirGoals,
        scorerId: isOurGoal ? scorerId : null,
        assistId: isOurGoal ? assistId : null,
        authorId: user.id,
        comment: text(req.body?.comment, 500),
      },
      include: { scorer: true, assist: true },
    });
    if (type === TickerEventType.MATCH_END) {
      await tx.matchDetails.updateMany({
        where: { eventId: match.id },
        data: { status: MatchStatus.FINISHED, ourGoals, theirGoals },
      });
    } else if (type === TickerEventType.MATCH_START) {
      await tx.matchDetails.updateMany({
        where: { eventId: match.id },
        data: { status: MatchStatus.LIVE },
      });
    }
    return { ticker, event, duplicate: false };
  });
  if (!result.duplicate) {
    await prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'LIVE_TICKER_EVENT',
        entityType: 'LiveTickerEvent',
        entityId: result.event.id,
        metadata: { type, sequence: result.event.sequence },
      },
    });
  }
  if (goalTypes.has(type) || type === TickerEventType.MATCH_END) {
    await recalculateMatchStatistics(match.id);
  }
  return res.status(result.duplicate ? 200 : 201).json({
    ...result,
    ticker: { ...result.ticker, elapsedSeconds: elapsed(result.ticker) },
  });
}

export async function undoTickerEvent(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  if (!(await canManageTicker(user, match.id))) {
    return res.status(403).json({ message: 'Der Liveticker ist für dieses Konto nicht freigegeben.' });
  }
  const ticker = await prisma.liveTicker.findUnique({ where: { eventId: match.id } });
  if (!ticker) return res.status(400).json({ message: 'Der Liveticker wurde noch nicht gestartet.' });
  const target = await prisma.liveTickerEvent.findFirst({
    where: {
      tickerId: ticker.id,
      revokedAt: null,
      type: { in: [TickerEventType.HOME_GOAL, TickerEventType.AWAY_GOAL, TickerEventType.COMMENT] },
    },
    orderBy: { sequence: 'desc' },
  });
  if (!target) return res.status(400).json({ message: 'Keine rückgängig machbare Aktion gefunden.' });
  const clientEventId = text(req.body?.clientEventId, 100);
  if (!clientEventId) return res.status(400).json({ message: 'clientEventId ist erforderlich.' });
  const result = await prisma.$transaction(async (tx) => {
    const duplicate = await tx.liveTickerEvent.findUnique({
      where: { tickerId_clientEventId: { tickerId: ticker.id, clientEventId } },
    });
    if (duplicate) return duplicate;
    const fcWasHome = match.matchDetails?.isHome !== false;
    const ourGoal =
      (target.type === TickerEventType.HOME_GOAL && fcWasHome) ||
      (target.type === TickerEventType.AWAY_GOAL && !fcWasHome);
    const theirGoal =
      (target.type === TickerEventType.AWAY_GOAL && fcWasHome) ||
      (target.type === TickerEventType.HOME_GOAL && !fcWasHome);
    const ourGoals = Math.max(0, ticker.ourGoals - (ourGoal ? 1 : 0));
    const theirGoals = Math.max(0, ticker.theirGoals - (theirGoal ? 1 : 0));
    const sequence = ticker.lastSequence + 1;
    await tx.liveTickerEvent.update({ where: { id: target.id }, data: { revokedAt: new Date() } });
    await tx.liveTicker.update({
      where: { id: ticker.id },
      data: { ourGoals, theirGoals, lastSequence: sequence },
    });
    return tx.liveTickerEvent.create({
      data: {
        tickerId: ticker.id,
        clientEventId,
        sequence,
        type: TickerEventType.EVENT_REVOKED,
        period: ticker.currentPeriod,
        elapsedSeconds: elapsed(ticker),
        ourGoals,
        theirGoals,
        authorId: user.id,
        correctsId: target.id,
        comment: text(req.body?.comment, 500) ?? 'Letzte Aktion rückgängig gemacht',
      },
    });
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: match.teamId,
      action: 'LIVE_TICKER_CORRECTION',
      entityType: 'LiveTickerEvent',
      entityId: result.id,
      metadata: { correctedEventId: target.id },
    },
  });
  await recalculateMatchStatistics(match.id);
  return res.json(result);
}

export async function resetTicker(req: Request, res: Response) {
  const user = req.user!;
  if (!hasPermission(user.role, Permission.MANAGE_LIVE_TICKER)) {
    return res.status(403).json({
      message: 'Nur Trainer und Administratoren dürfen ein Spiel zurücksetzen.',
    });
  }
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });

  await prisma.$transaction(async (tx) => {
    await tx.liveTicker.deleteMany({ where: { eventId: match.id } });
    await tx.playerMatchStatistic.deleteMany({ where: { eventId: match.id } });
    await tx.teamMatchStatistic.deleteMany({ where: { eventId: match.id } });
    await tx.matchTickerDelegate.deleteMany({ where: { eventId: match.id } });
    await tx.matchDetails.updateMany({
      where: { eventId: match.id },
      data: {
        status: MatchStatus.PLANNED,
        ourGoals: null,
        theirGoals: null,
        halfTimeOurGoals: null,
        halfTimeTheirGoals: null,
      },
    });
  });

  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: match.teamId,
      action: 'LIVE_TICKER_RESET',
      entityType: 'Event',
      entityId: match.id,
      metadata: {
        previousStatus: match.liveTicker?.status ?? TickerStatus.NOT_STARTED,
        previousOurGoals: match.liveTicker?.ourGoals ?? match.matchDetails?.ourGoals ?? 0,
        previousTheirGoals: match.liveTicker?.theirGoals ?? match.matchDetails?.theirGoals ?? 0,
        removedEvents: match.liveTicker?.events.length ?? 0,
      },
    },
  });

  return res.json({
    status: TickerStatus.NOT_STARTED,
    currentPeriod: 1,
    elapsedSeconds: 0,
    ourGoals: 0,
    theirGoals: 0,
    lastSequence: 0,
    events: [],
  });
}
