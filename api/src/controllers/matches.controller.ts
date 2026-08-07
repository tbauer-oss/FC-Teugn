import { Request, Response } from 'express';
import {
  EventType,
  EventCommunicationStatus,
  AttendanceStatus,
  AccountStatus,
  HomeAway,
  LineupStatus,
  MatchKind,
  MatchStatus,
  NotificationCategory,
  NominationStatus,
  PlayerStatus,
  Prisma,
  TickerEventType,
  TickerStatus,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import {
  hasEffectivePermission,
  hasPermission,
  Permission,
} from '../security/permissions';
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
import { mediaAssetUrl } from '../services/media-access';
import {
  reminderRecipientsForEvent,
  syncScheduledRemindersForEvent,
} from '../services/reminder.service';
import { notifyUsers } from '../services/notification.service';
import { settlePostCommitTasks } from '../services/post-commit.service';
import {
  AWAY_MEETING_LOCATION,
  HOME_MATCH_VENUE,
  normalizedMatchVenue,
} from '../services/match-venue.service';
import {
  buildFamilyReleaseMessage,
  buildInternalPublicationMessage,
  resolveMeetingPoint,
} from '../services/match-publication.service';

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
  matchDetails: {
    include: {
      opponentRecord: {
        include: { logoAsset: true },
      },
    },
  },
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
  playerRatings: {
    orderBy: { updatedAt: 'desc' as const },
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
        },
      },
      ratedBy: { select: { id: true, name: true } },
    },
  },
  leagueMatch: true,
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

function isStaff(role: Role, permissions?: readonly string[]) {
  return hasEffectivePermission(role, Permission.MANAGE_EVENTS, permissions);
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

async function findAccessibleTickerMatch(
  id: string,
  user: { id: string; teamId: string; role: Role },
) {
  const teamIds = await accessibleTeamIds(user);
  return prisma.event.findFirst({
    where: { id, ...scope(teamIds) },
    select: { id: true, familyReleasedAt: true },
  });
}

async function findTickerCommandMatch(
  id: string,
  user: { id: string; teamId: string; role: Role },
) {
  const teamIds = await accessibleTeamIds(user);
  return prisma.event.findFirst({
    where: { id, ...scope(teamIds) },
    select: {
      id: true,
      teamId: true,
      matchDetails: { select: { isHome: true, status: true } },
      squads: {
        take: 1,
        select: {
          members: {
            select: { playerId: true, status: true },
          },
        },
      },
    },
  });
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
  canDelete = false,
  canReschedule = false,
  canCancel = canDelete,
  canPublishInternal = staff,
  canNominateSquad = staff,
  canReleaseFamily = staff,
  familyTeamViewer = false,
  canRatePlayers = false,
) {
  const squad = match.squads[0] ?? null;
  const lineup = squad?.lineup;
  const lineupTeam = match.targetTeams[0]?.team ?? match.team;
  const familyDetailsVisible =
    familyTeamViewer && match.familyReleasedAt !== null;
  const canSeeLineup =
    staff ||
    (familyDetailsVisible &&
      lineup?.status === LineupStatus.PUBLISHED &&
      (!lineup.visibleAt || lineup.visibleAt.getTime() <= Date.now())) ||
    (match.familyReleasedAt !== null &&
      squad?.publishedAt !== null &&
      squad?.members.some((member) => viewerPlayerIds.includes(member.playerId)) === true &&
      lineup?.status === LineupStatus.PUBLISHED &&
      (!lineup.visibleAt || lineup.visibleAt.getTime() <= Date.now()));
  const canSeePublishedSquad = staff || tickerEditable || familyDetailsVisible || (
    squad?.publishedAt !== null &&
    squad?.members.some((member) => viewerPlayerIds.includes(member.playerId)) === true
  );
  return {
    ...match,
    matchDetails: match.matchDetails
      ? {
          ...match.matchDetails,
          opponentRecord: undefined,
          opponentLogoUrl:
            match.matchDetails.opponentRecord?.logoAsset &&
            match.matchDetails.opponentRecord.logoAsset.deletedAt === null
              ? mediaAssetUrl(
                  match.matchDetails.opponentRecord.logoAsset.id,
                  '12h',
                )
              : match.matchDetails.opponentLogoUrl,
        }
      : null,
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
      canDelete,
      canReschedule,
      canCancel,
      canPublishInternal,
      canNominateSquad,
      canReleaseFamily,
      canRatePlayers,
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
            scorer: tickerEditable || familyDetailsVisible || match.liveTicker?.publicScorersEnabled ? event.scorer : null,
            assist: tickerEditable || familyDetailsVisible || match.liveTicker?.publicScorersEnabled ? event.assist : null,
          })),
        }
      : null,
    playerRatings: canRatePlayers ? match.playerRatings : undefined,
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
  const staff = isStaff(user.role, user.permissions);
  const viewerPlayerIds = staff ? [] : await ownPlayerIds(user);
  const canDelete = hasEffectivePermission(
    user.role,
    Permission.MATCH_DELETE,
    user.permissions,
  );
  const canReschedule = hasEffectivePermission(
    user.role,
    Permission.MATCH_RESCHEDULE,
    user.permissions,
  );
  return res.json(matches.map((match) =>
    serializeMatch(
      match,
      staff,
      [],
      false,
      viewerPlayerIds,
      canDelete,
      canReschedule,
      hasEffectivePermission(user.role, Permission.MATCH_CANCEL, user.permissions),
      hasEffectivePermission(user.role, Permission.PUBLISH_LINEUP_INTERNAL, user.permissions),
      hasEffectivePermission(user.role, Permission.NOMINATE_SQUAD, user.permissions),
      hasEffectivePermission(user.role, Permission.RELEASE_MATCH_FAMILY, user.permissions),
      user.role === Role.PARENT,
      hasEffectivePermission(user.role, Permission.MANAGE_STATISTICS, user.permissions),
    ),
  ));
}

export async function getMatch(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) {
    const tombstone = await prisma.auditLog.findFirst({
      where: {
        entityId: req.params.id,
        entityType: 'Match',
        action: { in: ['MATCH_DELETED', 'MATCH_PERMANENTLY_DELETED'] },
      },
      orderBy: { createdAt: 'desc' },
      select: { createdAt: true },
    });
    if (tombstone) {
      return res.status(410).json({
        code: 'MATCH_DELETED',
        message: 'Dieses Spiel wurde dauerhaft gelöscht und ist nicht mehr verfügbar.',
        deletedAt: tombstone.createdAt,
      });
    }
    return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  }
  const staff = isStaff(user.role, user.permissions);
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
    hasEffectivePermission(user.role, Permission.MATCH_DELETE, user.permissions),
    hasEffectivePermission(user.role, Permission.MATCH_RESCHEDULE, user.permissions),
    hasEffectivePermission(user.role, Permission.MATCH_CANCEL, user.permissions),
    hasEffectivePermission(user.role, Permission.PUBLISH_LINEUP_INTERNAL, user.permissions),
    hasEffectivePermission(user.role, Permission.NOMINATE_SQUAD, user.permissions),
    hasEffectivePermission(user.role, Permission.RELEASE_MATCH_FAMILY, user.permissions),
    user.role === Role.PARENT,
    hasEffectivePermission(user.role, Permission.MANAGE_STATISTICS, user.permissions),
  ));
}

async function matchCancellationAudience(eventId: string) {
  const match = await prisma.event.findUnique({
    where: { id: eventId },
    include: {
      targetTeams: { select: { teamId: true } },
      squads: {
        take: 1,
        include: {
          members: {
            where: { status: NominationStatus.NOMINATED },
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
      },
    },
  });
  if (!match) return null;
  const teamIds = match.targetTeams.length
    ? match.targetTeams.map((target) => target.teamId)
    : [match.teamId];
  const publishedSquad = match.squads.find((squad) => squad.publishedAt != null);
  const players = publishedSquad
    ? publishedSquad.members.map((member) => member.player)
    : await prisma.player.findMany({
        where: { teamId: { in: teamIds }, status: PlayerStatus.ACTIVE },
        include: {
          parentLinks: {
            where: { receivesCommunication: true },
            select: { parentId: true },
          },
        },
      });
  const staff = await prisma.teamMembership.findMany({
    where: {
      teamId: { in: teamIds },
      status: AccountStatus.APPROVED,
      role: {
        in: [
          Role.SUPER_ADMIN,
          Role.CLUB_ADMIN,
          Role.YOUTH_DIRECTOR,
          Role.TRAINER_ADMIN,
          Role.COACH,
          Role.TRAINER,
          Role.ASSISTANT_COACH,
          Role.TEAM_MANAGER,
        ],
      },
      user: { status: AccountStatus.APPROVED },
    },
    select: { userId: true },
  });
  const userIds = new Set<string>();
  for (const player of players) {
    if (player.userId) userIds.add(player.userId);
    player.parentLinks.forEach((link) => userIds.add(link.parentId));
  }
  staff.forEach((membership) => userIds.add(membership.userId));
  return {
    match,
    teamIds,
    playerCount: players.length,
    userIds: [...userIds],
    audienceMode: publishedSquad ? 'PUBLISHED_SQUAD' : 'FULL_TEAM',
  } as const;
}

export async function cancelMatchPreview(req: Request, res: Response) {
  const match = await findMatch(req.params.id, req.user!);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const audience = await matchCancellationAudience(match.id);
  return res.json({
    playerCount: audience?.playerCount ?? 0,
    recipientCount: audience?.userIds.length ?? 0,
    audienceMode: audience?.audienceMode ?? 'FULL_TEAM',
    mandatoryPush: true,
  });
}

export async function cancelMatch(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  if (match.status === 'CANCELLED' || match.matchDetails?.status === MatchStatus.CANCELLED) {
    return res.status(409).json({ message: 'Dieses Spiel ist bereits abgesagt.' });
  }
  const reason = text(req.body.reason, 1000);
  if (!reason) return res.status(400).json({ message: 'Bitte einen Absagegrund angeben.' });
  const audience = await matchCancellationAudience(match.id);
  if (!audience) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const now = new Date();
  const auditId = await prisma.$transaction(async (tx) => {
    await tx.event.update({
      where: { id: match.id },
      data: {
        status: 'CANCELLED',
        cancellationReason: reason,
        cancelledAt: now,
        attendanceFinalized: true,
      },
    });
    await tx.matchDetails.updateMany({
      where: { eventId: match.id },
      data: { status: MatchStatus.CANCELLED },
    });
    await tx.leagueMatch.updateMany({
      where: { eventId: match.id },
      data: { status: 'CANCELLED' },
    });
    await tx.scheduledReminder.updateMany({
      where: {
        eventId: match.id,
        status: { in: ['SCHEDULED', 'FAILED', 'PROCESSING'] },
      },
      data: { status: 'CANCELLED', cancelledAt: now },
    });
    const audit = await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'MATCH_CANCELLED',
        entityType: 'Match',
        entityId: match.id,
        metadata: {
          reason,
          audienceMode: audience.audienceMode,
          playerCount: audience.playerCount,
          recipientCount: audience.userIds.length,
          opponent: match.opponent,
          scheduledAt: match.startAt,
          location: match.location,
          leagueId: match.matchDetails?.leagueId ?? null,
        },
      },
    });
    return audit.id;
  });
  const date = match.startAt.toLocaleString('de-DE', {
    timeZone: 'Europe/Berlin',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
  const delivery = await notifyUsers(
    audience.userIds.filter((id) => id !== user.id),
    {
      category: NotificationCategory.MATCH,
      title: 'Spiel abgesagt',
      body: `„${match.title}“ am ${date} wurde abgesagt. Grund: ${reason}`,
      actionUrl: `/matches/${match.id}`,
      entityType: 'MatchCancellation',
      entityId: match.id,
      dedupeKey: `match-cancelled:${match.id}`,
      forceInApp: true,
      forcePush: true,
    },
  );
  await prisma.auditLog.update({
    where: { id: auditId },
    data: {
      metadata: {
        reason,
        audienceMode: audience.audienceMode,
        playerCount: audience.playerCount,
        recipientCount: audience.userIds.length,
        opponent: match.opponent,
        scheduledAt: match.startAt,
        location: match.location,
        leagueId: match.matchDetails?.leagueId ?? null,
        inAppNotifications: delivery.notifications,
        pushSent: delivery.sent,
        pushFailed: delivery.failed,
        pushPending: delivery.pending,
      },
    },
  });
  return res.json({
    status: 'CANCELLED',
    cancellationReason: reason,
    cancelledAt: now,
    audience: {
      mode: audience.audienceMode,
      playerCount: audience.playerCount,
      recipientCount: audience.userIds.length,
    },
    delivery,
  });
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
  const opponentId = text(body.opponentId, 100);
  const opponentRecord = opponentId
    ? await prisma.opponent.findFirst({
        where: {
          id: opponentId,
          archivedAt: null,
          ageGroup: { teams: { some: { id: match.teamId } } },
        },
      })
    : null;
  if (opponentId && !opponentRecord) {
    return res.status(400).json({ message: 'Die gegnerische Mannschaft ist nicht verfügbar.' });
  }
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
  const isHome = body.isHome !== false;
  const location = normalizedMatchVenue({
    isHome,
    requested: text(body.location, 160),
    previous: match.location,
    previousWasHome: match.matchDetails?.isHome !== false,
    opponentVenue: opponentRecord?.venue,
    opponentAddress: opponentRecord?.address,
  });
  const meetingLocation = isHome
    ? text(body.meetingLocation, 160) ?? match.meetingLocation
    : text(body.meetingLocation, 160) ?? AWAY_MEETING_LOCATION;
  const details = await prisma.$transaction(async (tx) => {
    const saved = await tx.matchDetails.upsert({
      where: { eventId: match.id },
      update: {
        opponent,
        opponentId: opponentRecord?.id ?? null,
        opponentShortName: text(body.opponentShortName, 30),
        opponentLogoUrl: text(body.opponentLogoUrl, 500),
        isHome,
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
        opponentId: opponentRecord?.id ?? null,
        opponentShortName: text(body.opponentShortName, 30),
        opponentLogoUrl: text(body.opponentLogoUrl, 500),
        isHome,
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
    await tx.event.update({
      where: { id: match.id },
      data: {
        opponent,
        homeAway: isHome ? HomeAway.HOME : HomeAway.AWAY,
        location,
        address:
          text(body.address, 240) ?? opponentRecord?.address ?? match.address,
        meetingLocation,
      },
    });
    return saved;
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

type RescheduleRetention = 'KEEP' | 'RESET_RESPONSES' | 'RESET_SQUAD';
type RescheduleNotification = 'NONE' | 'IN_APP' | 'PUSH';

function validDate(value: unknown) {
  if (!value) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export async function rescheduleMatch(req: Request, res: Response) {
  const user = req.user!;
  if (!hasEffectivePermission(
    user.role,
    Permission.MATCH_RESCHEDULE,
    user.permissions,
  )) {
    return res.status(403).json({
      message: 'Für die Spielverlegung fehlt die erforderliche Berechtigung.',
      permission: Permission.MATCH_RESCHEDULE,
    });
  }
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const status = match.matchDetails?.status ?? MatchStatus.PLANNED;
  const tickerStarted = match.liveTicker && (
    match.liveTicker.status !== TickerStatus.NOT_STARTED ||
    match.liveTicker.events.length > 0
  );
  if (
    tickerStarted ||
    new Set<MatchStatus>([
      MatchStatus.LIVE,
      MatchStatus.HALF_TIME,
      MatchStatus.INTERRUPTED,
      MatchStatus.FINISHED,
      MatchStatus.RECORDED,
    ]).has(status)
  ) {
    return res.status(409).json({
      message:
        'Ein laufendes oder abgeschlossenes Spiel kann nicht normal verlegt werden.',
    });
  }

  const startAt = validDate(req.body?.startAt);
  const meetingAt = validDate(req.body?.meetingAt);
  if (!startAt) {
    return res.status(400).json({ message: 'Das neue Spieldatum ist ungültig.' });
  }
  if (meetingAt && meetingAt >= startAt) {
    return res.status(400).json({
      message: 'Der Treffpunkt muss vor dem Spielbeginn liegen.',
    });
  }
  const isHome = req.body?.isHome === undefined
    ? match.matchDetails?.isHome !== false
    : req.body.isHome === true;
  const location = normalizedMatchVenue({
    isHome,
    requested: text(req.body?.location, 160),
    previous: match.location,
    previousWasHome: match.matchDetails?.isHome !== false,
    opponentVenue: match.matchDetails?.opponentRecord?.venue,
    opponentAddress: match.matchDetails?.opponentRecord?.address,
  });
  const meetingLocation = isHome
    ? text(req.body?.meetingLocation, 160)
    : text(req.body?.meetingLocation, 160) ?? AWAY_MEETING_LOCATION;
  const durationMinutes = match.matchDetails?.durationMinutes ?? 60;
  const endAt = validDate(req.body?.endAt) ??
    new Date(startAt.getTime() + durationMinutes * 60_000);
  if (endAt <= startAt) {
    return res.status(400).json({ message: 'Das Spielende muss nach dem Beginn liegen.' });
  }

  const teamIds = match.targetTeams.length
    ? match.targetTeams.map((target) => target.teamId)
    : [match.teamId];
  const conflictWhere: Prisma.EventWhereInput = {
    id: { not: match.id },
    status: { not: 'CANCELLED' },
    startAt: { lt: endAt },
    OR: [
      { endAt: { gt: startAt } },
      { endAt: null, startAt: { gte: new Date(startAt.getTime() - 3 * 60 * 60_000) } },
    ],
    AND: [{
      OR: [
        { teamId: { in: teamIds } },
        { targetTeams: { some: { teamId: { in: teamIds } } } },
        ...(isHome
          ? [{
              homeAway: { not: HomeAway.AWAY },
              location: HOME_MATCH_VENUE,
            } as Prisma.EventWhereInput]
          : []),
      ],
    }],
  };
  const conflicts = await prisma.event.findMany({
    where: conflictWhere,
    select: { id: true, title: true, startAt: true, endAt: true, location: true },
    orderBy: { startAt: 'asc' },
    take: 10,
  });
  if (conflicts.length && req.body?.confirmConflicts !== true) {
    return res.status(409).json({
      message: 'Der neue Termin überschneidet sich mit bestehenden Belegungen.',
      conflicts,
    });
  }

  const retention = ['KEEP', 'RESET_RESPONSES', 'RESET_SQUAD'].includes(
    String(req.body?.retention ?? '').toUpperCase(),
  )
    ? String(req.body.retention).toUpperCase() as RescheduleRetention
    : 'KEEP';
  const notification = ['NONE', 'IN_APP', 'PUSH'].includes(
    String(req.body?.notification ?? '').toUpperCase(),
  )
    ? String(req.body.notification).toUpperCase() as RescheduleNotification
    : 'IN_APP';
  const old = {
    startAt: match.startAt,
    meetingAt: match.meetingAt,
    meetingLocation: match.meetingLocation,
    location: match.location,
    isHome: match.matchDetails?.isHome !== false,
    matchDay: match.matchDetails?.matchDay,
  };
  const now = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.event.update({
      where: { id: match.id },
      data: {
        startAt,
        endAt,
        meetingAt,
        meetingLocation,
        location,
        address: text(req.body?.address, 240) ?? match.address,
        homeAway: isHome ? HomeAway.HOME : HomeAway.AWAY,
        internalNote: text(req.body?.internalNote, 2000) ?? match.internalNote,
        reminderSyncPendingAt: now,
      },
    });
    await tx.matchDetails.update({
      where: { eventId: match.id },
      data: {
        isHome,
        pitch: text(req.body?.pitch, 100),
        matchDay: text(req.body?.matchDay, 50) ?? match.matchDetails?.matchDay,
        status: status === MatchStatus.CONFIRMED
          ? MatchStatus.CONFIRMED
          : MatchStatus.PLANNED,
        notes: text(req.body?.publicNotice, 2000) ?? match.matchDetails?.notes,
      },
    });
    if (match.leagueMatch) {
      await tx.leagueMatch.update({
        where: { id: match.leagueMatch.id },
        data: {
          startsAt: startAt,
          venue: location,
          status: 'SCHEDULED',
          notes: text(req.body?.reason, 1000) ?? match.leagueMatch.notes,
        },
      });
    }
    if (retention === 'RESET_RESPONSES') {
      const nominatedPlayerIds = match.squads[0]?.members.map((member) => member.playerId) ?? [];
      await tx.attendance.updateMany({
        where: {
          eventId: match.id,
          ...(nominatedPlayerIds.length ? { playerId: { in: nominatedPlayerIds } } : {}),
        },
        data: {
          status: AttendanceStatus.UNKNOWN,
          reason: null,
          goalkeeperAvailable: null,
          respondedById: null,
          respondedAt: null,
        },
      });
    } else if (retention === 'RESET_SQUAD') {
      await tx.squad.deleteMany({ where: { eventId: match.id } });
      await tx.attendance.deleteMany({ where: { eventId: match.id } });
    }
    await tx.notification.deleteMany({
      where: {
        entityId: match.id,
        category: NotificationCategory.EVENT_REMINDER,
        expiresAt: { gt: now },
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'MATCH_RESCHEDULED',
        entityType: 'Match',
        entityId: match.id,
        metadata: {
          opponent: match.matchDetails?.opponent,
          old,
          next: {
            startAt,
            meetingAt,
            meetingLocation,
            location,
            isHome,
            matchDay: text(req.body?.matchDay, 50) ?? match.matchDetails?.matchDay,
          },
          reason: text(req.body?.reason, 500),
          retention,
          notification,
          leagueId: match.matchDetails?.leagueId,
          leagueMatchId: match.leagueMatch?.id,
          externalSource: match.matchDetails?.externalSource,
          externalId: match.matchDetails?.bfvMatchId,
          conflictsConfirmed: conflicts.length > 0,
        },
      },
    });
  });

  const reminderTask = (async () => {
    await syncScheduledRemindersForEvent(match.id);
    await prisma.event.update({
      where: { id: match.id },
      data: { reminderSyncPendingAt: null },
    });
  })();
  const notificationTask = notification !== 'NONE' ? (async () => {
    const { recipientIds } = await reminderRecipientsForEvent(match.id);
    const opponent = match.matchDetails?.opponent ?? 'Gegner';
    const local = startAt.toLocaleString('de-DE', {
      timeZone: 'Europe/Berlin',
      dateStyle: 'medium',
      timeStyle: 'short',
    });
    await notifyUsers(recipientIds, {
      category: NotificationCategory.EVENT_REMINDER,
      title: `Spiel gegen ${opponent} wurde verlegt`,
      body: `Neuer Termin: ${local} Uhr · Treffpunkt: ${meetingLocation ?? 'noch offen'} · ${location}`,
      actionUrl: `/trainer/matches/${match.id}`,
      entityType: 'Event',
      entityId: match.id,
      pushEnabled: notification === 'PUSH',
      dedupeKey: `match-rescheduled:${match.id}:${startAt.toISOString()}`,
    });
  })() : Promise.resolve();
  await settlePostCommitTasks([
    { name: 'match-reschedule-reminders', promise: reminderTask },
    { name: 'match-reschedule-notification', promise: notificationTask },
  ]);
  const updated = await findMatch(match.id, user);
  return res.json(updated ? serializeMatch(
    updated,
    isStaff(user.role, user.permissions),
    [],
    false,
    [],
    hasEffectivePermission(user.role, Permission.MATCH_DELETE, user.permissions),
    hasEffectivePermission(user.role, Permission.MATCH_RESCHEDULE, user.permissions),
    hasEffectivePermission(user.role, Permission.MATCH_CANCEL, user.permissions),
    hasEffectivePermission(user.role, Permission.PUBLISH_LINEUP_INTERNAL, user.permissions),
    hasEffectivePermission(user.role, Permission.NOMINATE_SQUAD, user.permissions),
    hasEffectivePermission(user.role, Permission.RELEASE_MATCH_FAMILY, user.permissions),
  ) : null);
}

export async function updateSquad(req: Request, res: Response) {
  const startedAt = performance.now();
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
  const previousSquad = await prisma.squad.findUnique({
    where: { eventId: match.id },
    select: { publishedAt: true },
  });
  const wasPublished = previousSquad?.publishedAt != null;
  const squad = await prisma.$transaction(async (tx) => {
    const saved = await tx.squad.upsert({
      where: { eventId: match.id },
      update: {
        name: text(req.body.name, 100),
        formation: text(req.body.formation, 50),
        ...(wasPublished ? { publishedAt: null } : {}),
      },
      create: {
        eventId: match.id,
        name: text(req.body.name, 100),
        formation: text(req.body.formation, 50),
      },
    });
    await Promise.all([
      tx.squadMember.deleteMany({ where: { squadId: saved.id } }),
      tx.eventParticipant.deleteMany({
        where: {
          eventId: match.id,
          playerId: { not: null, notIn: ids },
        },
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
    // Entwürfe erzeugen bewusst noch keine Rückmeldeanfragen. Bereits
    // veröffentlichte, weiterhin nominierte Spieler behalten ihre Antworten;
    // neue Anfragen entstehen atomar erst beim erneuten Veröffentlichen.
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
  }, {
    // The normal path remains well below this limit. These explicit values
    // prevent Prisma's short interactive-transaction defaults from aborting a
    // valid squad update during a brief production connection spike.
    maxWait: 10_000,
    timeout: 15_000,
  });
  // Die Antwort hängt ausschließlich vom atomaren Kader-Commit ab.
  // Erinnerungsjobs werden durch den Cron anhand reminderSyncPendingAt
  // zuverlässig nachgezogen und blockieren diese Kernfunktion nie wieder.
  res.setHeader(
    'Server-Timing',
    `squad-save;dur=${(performance.now() - startedAt).toFixed(1)}`,
  );
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
        where: { status: NominationStatus.NOMINATED },
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
  if (!squad.members.length) {
    return res.status(400).json({ message: 'Bitte mindestens einen Spieler nominieren.' });
  }
  const selectedIds = squad.members.map((member) => member.playerId);
  const previousRequests = await prisma.eventParticipant.findMany({
    where: { eventId: match.id, playerId: { not: null } },
    select: { playerId: true },
  });
  const previousIds = new Set(previousRequests.map((item) => item.playerId!));
  const removedIds = [...previousIds].filter((playerId) => !selectedIds.includes(playerId));
  const resendAll = req.body.resendAll === true;
  const playersToNotify = resendAll
    ? squad.members
    : squad.members.filter((member) => !previousIds.has(member.playerId));
  const updated = await prisma.$transaction(async (tx) => {
    const saved = await tx.squad.update({
      where: { id: squad.id },
      data: { publishedAt: new Date() },
    });
    await tx.eventParticipant.deleteMany({
      where: { eventId: match.id, playerId: { not: null, notIn: selectedIds } },
    });
    await tx.attendance.deleteMany({
      where: { eventId: match.id, playerId: { notIn: selectedIds } },
    });
    if (removedIds.length) {
      await tx.notification.deleteMany({
        where: {
          entityType: 'AttendanceRequest',
          entityId: { in: removedIds.map((playerId) => `${match.id}:${playerId}`) },
        },
      });
    }
    await tx.eventParticipant.createMany({
      data: selectedIds.map((playerId) => ({
        eventId: match.id,
        playerId,
        responseRequired: true,
      })),
      skipDuplicates: true,
    });
    await tx.attendance.createMany({
      data: selectedIds.map((playerId) => ({
        eventId: match.id,
        playerId,
        status: AttendanceStatus.UNKNOWN,
      })),
      skipDuplicates: true,
    });
    await tx.event.update({
      where: { id: match.id },
      data: { reminderSyncPendingAt: new Date() },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'MATCH_SQUAD_PUBLISHED',
        entityType: 'Squad',
        entityId: squad.id,
        metadata: {
          nominatedCount: selectedIds.length,
          newlyRequestedCount: playersToNotify.length,
          pushEnabled: req.body.pushEnabled !== false,
          resendAll,
        },
      },
    });
    return saved;
  });
  const summaries = [];
  for (const member of playersToNotify) {
    const playerName = member.player.preferredName || member.player.firstName;
    const recipientIds = [
      ...(member.player.userId ? [member.player.userId] : []),
      ...member.player.parentLinks.map((link) => link.parentId),
    ];
    summaries.push(await notifyUsers(recipientIds, {
      category: NotificationCategory.NOMINATION,
      title: 'Kadernominierung – Rückmeldung erforderlich',
      body: `${playerName} wurde für „${match.title}“ nominiert. Bitte jetzt zu- oder absagen.`,
      actionUrl: `/family?eventId=${match.id}&playerId=${member.playerId}`,
      entityType: 'AttendanceRequest',
      entityId: `${match.id}:${member.playerId}`,
      dedupeKey: `nomination:${match.id}:${member.playerId}:${squad.updatedAt.getTime()}`,
      pushEnabled: req.body.pushEnabled !== false,
    }));
  }
  return res.json({
    squad: updated,
    publication: {
      nominatedPlayers: selectedIds.length,
      requestedPlayers: playersToNotify.length,
      recipients: summaries.reduce((sum, item) => sum + item.recipients, 0),
      notifications: summaries.reduce((sum, item) => sum + item.notifications, 0),
      deliveries: summaries.reduce((sum, item) => sum + item.deliveries, 0),
      sent: summaries.reduce((sum, item) => sum + item.sent, 0),
      failed: summaries.reduce((sum, item) => sum + item.failed, 0),
      pending: summaries.reduce((sum, item) => sum + item.pending, 0),
      pushEnabled: req.body.pushEnabled !== false,
    },
  });
}

function matchTeamIds(match: { teamId: string; targetTeams: Array<{ teamId: string }> }) {
  return match.targetTeams.length
    ? match.targetTeams.map((target) => target.teamId)
    : [match.teamId];
}

const internalPublicationRoles = [
  Role.COACH,
  Role.TRAINER,
  Role.ASSISTANT_COACH,
  Role.TEAM_MANAGER,
] as const;

function internalRoleLabel(role: Role) {
  switch (role) {
    case Role.COACH:
    case Role.TRAINER:
      return 'Trainer';
    case Role.ASSISTANT_COACH:
      return 'Co-Trainer';
    case Role.TEAM_MANAGER:
      return 'Mannschaftsverantwortlicher';
    default:
      return role;
  }
}

async function eligibleInternalPublicationRecipients(
  match: { teamId: string; targetTeams: Array<{ teamId: string }> },
) {
  const staff = await prisma.teamMembership.findMany({
    where: {
      teamId: { in: matchTeamIds(match) },
      status: AccountStatus.APPROVED,
      role: { in: [...internalPublicationRoles] },
      user: { status: AccountStatus.APPROVED },
    },
    select: {
      userId: true,
      role: true,
      user: { select: { name: true } },
      team: { select: { id: true, name: true, shortName: true } },
    },
    orderBy: [
      { team: { name: 'asc' } },
      { user: { name: 'asc' } },
    ],
  });
  const recipients = new Map<string, {
    id: string;
    name: string;
    roles: Set<string>;
    teams: Map<string, string>;
  }>();
  for (const membership of staff) {
    const recipient = recipients.get(membership.userId) ?? {
      id: membership.userId,
      name: membership.user.name,
      roles: new Set<string>(),
      teams: new Map<string, string>(),
    };
    recipient.roles.add(internalRoleLabel(membership.role));
    recipient.teams.set(
      membership.team.id,
      membership.team.shortName || membership.team.name,
    );
    recipients.set(membership.userId, recipient);
  }
  return [...recipients.values()]
    .map((recipient) => ({
      id: recipient.id,
      name: recipient.name,
      functions: [...recipient.roles],
      teams: [...recipient.teams.values()],
    }))
    .sort((left, right) => left.name.localeCompare(right.name, 'de-DE'));
}

function publicationOpponent(match: {
  opponent: string | null;
  matchDetails: { opponent: string } | null;
}) {
  return match.matchDetails?.opponent || match.opponent || 'den Gegner';
}

function publicationTeam(match: {
  team: { ageGroup: { code: string } };
  targetTeams: Array<{ team: { name: string; shortName: string | null } }>;
}) {
  return match.targetTeams[0]?.team.shortName ||
    match.targetTeams[0]?.team.name ||
    match.team.ageGroup.code;
}

export async function internalPublicationPreview(req: Request, res: Response) {
  const match = await findMatch(req.params.id, req.user!);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const recipients = await eligibleInternalPublicationRecipients(match);
  const messagePreview = buildInternalPublicationMessage({
    category: match.category,
    team: publicationTeam(match),
    opponent: publicationOpponent(match),
  });
  return res.json({
    recipients: recipients.map((recipient) => ({
      ...recipient,
      isSender: recipient.id === req.user!.id,
    })),
    recipientCount: recipients.length,
    pushEnabled: true,
    messagePreview,
  });
}

async function nominatedAudience(eventId: string) {
  const squad = await prisma.squad.findUnique({
    where: { eventId },
    include: {
      members: {
        where: { status: NominationStatus.NOMINATED },
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
  const recipients = new Set<string>();
  squad?.members.forEach((member) => {
    if (member.player.userId) recipients.add(member.player.userId);
    member.player.parentLinks.forEach((link) => recipients.add(link.parentId));
  });
  return { squad, recipients: [...recipients] };
}

export async function nominationPreview(req: Request, res: Response) {
  const match = await findMatch(req.params.id, req.user!);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const { squad, recipients } = await nominatedAudience(match.id);
  if (!squad?.members.length) {
    return res.status(400).json({ message: 'Zuerst muss ein Kader gespeichert werden.' });
  }
  return res.json({
    matchId: match.id,
    title: match.title,
    opponent: match.matchDetails?.opponent ?? match.opponent,
    players: squad.members.map((member) => ({
      id: member.playerId,
      name: member.player.preferredName ||
        `${member.player.firstName} ${member.player.lastName}`.trim(),
    })),
    recipients: recipients.length,
  });
}

export async function publishMatchInternally(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const eligibleRecipients = await eligibleInternalPublicationRecipients(match);
  const eligibleIds = new Set(eligibleRecipients.map((recipient) => recipient.id));
  const requestedIds = req.body?.recipientIds;
  if (requestedIds !== undefined && !Array.isArray(requestedIds)) {
    return res.status(400).json({ message: 'Die Empfängerauswahl ist ungültig.' });
  }
  const recipientIds: string[] = requestedIds === undefined
    ? [...eligibleIds]
    : [...new Set<string>(
        (requestedIds as unknown[])
          .filter((id: unknown): id is string => typeof id === 'string')
          .map((id: string) => id.trim())
          .filter(Boolean),
      )];
  if (!recipientIds.length) {
    return res.status(400).json({ message: 'Mindestens ein Trainerteam-Mitglied muss ausgewählt sein.' });
  }
  const invalidRecipientIds = recipientIds.filter((id) => !eligibleIds.has(id));
  if (invalidRecipientIds.length) {
    return res.status(403).json({
      message: 'Die Auswahl enthält Personen außerhalb des zuständigen Trainerteams.',
      invalidRecipientIds,
    });
  }
  const squad = match.squads[0];
  const lineup = squad?.lineup;
  const message = buildInternalPublicationMessage({
    category: match.category,
    team: publicationTeam(match),
    opponent: publicationOpponent(match),
  });
  const delivery = await notifyUsers(recipientIds, {
    category: NotificationCategory.MATCH,
    title: 'Kader und Aufstellung mit Trainerteam geteilt',
    body: message,
    actionUrl: `/matches/${match.id}`,
    entityType: 'MatchInternalPublication',
    entityId: match.id,
    dedupeKey: `match-internal:${match.id}:${squad?.updatedAt.getTime() ?? 0}:${lineup?.updatedAt.getTime() ?? 0}`,
    forceInApp: true,
    pushEnabled: req.body.pushEnabled === true,
  });
  await prisma.$transaction([
    prisma.event.update({
      where: { id: match.id },
      data: {
        communicationStatus: EventCommunicationStatus.INTERNAL_PUBLISHED,
        internalPublishedAt: new Date(),
      },
    }),
    prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'MATCH_INTERNALLY_PUBLISHED',
        entityType: 'Event',
        entityId: match.id,
        metadata: {
          recipientIds,
          pushEnabled: req.body.pushEnabled === true,
          message,
          delivery,
        },
      },
    }),
    ...(lineup
      ? [prisma.lineup.update({
          where: { id: lineup.id },
          data: {
            status: LineupStatus.PUBLISHED,
            publishedAt: new Date(),
          },
        })]
      : []),
  ]);
  return res.json({
    status: 'INTERNAL_PUBLISHED',
    recipients: recipientIds.length,
    recipientIds,
    message,
    delivery,
  });
}

async function fullTeamFamilyAudience(teamIds: string[]) {
  const players = await prisma.player.findMany({
    where: { teamId: { in: teamIds }, status: PlayerStatus.ACTIVE },
    include: {
      parentLinks: {
        where: { receivesCommunication: true },
        select: { parentId: true },
      },
    },
  });
  const recipients = new Set<string>();
  players.forEach((player) => {
    if (player.userId) recipients.add(player.userId);
    player.parentLinks.forEach((link) => recipients.add(link.parentId));
  });
  return { players, recipients: [...recipients] };
}

export async function familyReleasePreview(req: Request, res: Response) {
  const match = await findMatch(req.params.id, req.user!);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const nominated = await nominatedAudience(match.id);
  const audienceMode = nominated.squad?.members.length ? 'NOMINATED_SQUAD' : 'FULL_TEAM_REQUIRED';
  const full = audienceMode === 'FULL_TEAM_REQUIRED'
    ? await fullTeamFamilyAudience(matchTeamIds(match))
    : null;
  const meeting = resolveMeetingPoint({
    startAt: match.startAt,
    meetingAt: match.meetingAt,
    meetingLocation: match.meetingLocation,
  });
  const messagePreview = buildFamilyReleaseMessage({
    category: match.category,
    opponent: publicationOpponent(match),
    startAt: match.startAt,
    meeting,
  });
  return res.json({
    team: match.targetTeams[0]?.team.name ?? match.team.ageGroup.code,
    category: match.category,
    opponent: match.matchDetails?.opponent ?? match.opponent,
    startAt: match.startAt,
    meetingAt: meeting.at,
    meetingLocation: meeting.location,
    meetingSummary: meeting.summary,
    location: match.location,
    isHome: match.matchDetails?.isHome !== false,
    audienceMode,
    players: nominated.squad?.members.length ?? full?.players.length ?? 0,
    recipients: nominated.recipients.length || full?.recipients.length || 0,
    alreadyReleased: Boolean(match.familyReleasedAt),
    messagePreview,
  });
}

export async function releaseMatchToFamilies(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  if (match.familyReleasedAt) {
    return res.json({ status: 'FAMILY_RELEASED', alreadyReleased: true, delivery: null });
  }
  const nominated = await nominatedAudience(match.id);
  const hasSquad = Boolean(nominated.squad?.members.length);
  if (!hasSquad && req.body.audienceMode !== 'FULL_TEAM') {
    return res.status(409).json({
      message: 'Ohne nominierten Kader muss die gesamte Mannschaft ausdrücklich gewählt werden.',
    });
  }
  const full = hasSquad ? null : await fullTeamFamilyAudience(matchTeamIds(match));
  const recipientIds = hasSquad ? nominated.recipients : full!.recipients;
  const meeting = resolveMeetingPoint({
    startAt: match.startAt,
    meetingAt: match.meetingAt,
    meetingLocation: match.meetingLocation,
  });
  const message = buildFamilyReleaseMessage({
    category: match.category,
    opponent: publicationOpponent(match),
    startAt: match.startAt,
    meeting,
  });
  const delivery = await notifyUsers(recipientIds, {
    category: NotificationCategory.MATCH,
    title: 'Spiel freigegeben',
    body: message,
    actionUrl: `/matches/${match.id}`,
    entityType: 'MatchFamilyRelease',
    entityId: match.id,
    dedupeKey: `match-family-release:${match.id}`,
    forceInApp: true,
    forcePush: true,
  });
  await prisma.$transaction([
    prisma.event.update({
      where: { id: match.id },
      data: {
        communicationStatus: EventCommunicationStatus.FAMILY_RELEASED,
        familyReleasedAt: new Date(),
        familyReleaseAudience: hasSquad ? 'NOMINATED_SQUAD' : 'FULL_TEAM',
        meetingAt: meeting.at,
        meetingLocation: meeting.location,
      },
    }),
    prisma.auditLog.create({
      data: {
        actorId: user.id,
        teamId: match.teamId,
        action: 'MATCH_RELEASED_TO_FAMILIES',
        entityType: 'Event',
        entityId: match.id,
        metadata: {
          audience: hasSquad ? 'NOMINATED_SQUAD' : 'FULL_TEAM',
          recipientIds,
          message,
          delivery,
        },
      },
    }),
    ...(match.squads[0]?.lineup
      ? [prisma.lineup.update({
          where: { id: match.squads[0].lineup.id },
          data: {
            status: LineupStatus.PUBLISHED,
            publishedAt: new Date(),
          },
        })]
      : []),
  ]);
  return res.json({
    status: 'FAMILY_RELEASED',
    alreadyReleased: false,
    recipients: recipientIds.length,
    message,
    meeting,
    delivery,
  });
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

export async function updateMatchRatings(req: Request, res: Response) {
  const user = req.user!;
  const match = await findMatch(req.params.id, user);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const finished =
    match.matchDetails?.status === MatchStatus.FINISHED ||
    match.matchDetails?.status === MatchStatus.RECORDED ||
    match.liveTicker?.status === TickerStatus.FINISHED;
  if (!finished) {
    return res.status(409).json({
      message: 'Spielerbewertungen sind erst nach Spielende möglich.',
    });
  }
  const rawRatings = Array.isArray(req.body?.ratings) ? req.body.ratings : null;
  if (!rawRatings || rawRatings.length > 60) {
    return res.status(400).json({ message: 'Ungültige Spielerliste.' });
  }
  const nominatedPlayerIds = new Set(
    (match.squads[0]?.members ?? [])
      .filter((member) => member.status === NominationStatus.NOMINATED)
      .map((member) => member.playerId),
  );
  const normalized = new Map<string, number | null>();
  for (const raw of rawRatings as Array<Record<string, unknown>>) {
    const playerId = text(raw.playerId, 100);
    if (!playerId || !nominatedPlayerIds.has(playerId)) {
      return res.status(400).json({
        message: 'Bewertet werden dürfen nur nominierte Spieler.',
      });
    }
    if (raw.score === null) {
      normalized.set(playerId, null);
      continue;
    }
    const score = Number(raw.score);
    if (!Number.isInteger(score) || score < 1 || score > 10) {
      return res.status(400).json({ message: 'Bewertungen müssen zwischen 1 und 10 liegen.' });
    }
    normalized.set(playerId, score);
  }
  await prisma.$transaction(async (tx) => {
    for (const [playerId, score] of normalized) {
      if (score === null) {
        await tx.playerMatchRating.deleteMany({
          where: { eventId: match.id, playerId },
        });
      } else {
        await tx.playerMatchRating.upsert({
          where: { eventId_playerId: { eventId: match.id, playerId } },
          update: { score, ratedById: user.id },
          create: { eventId: match.id, playerId, score, ratedById: user.id },
        });
      }
    }
  });
  const ratings = await prisma.playerMatchRating.findMany({
    where: { eventId: match.id },
    orderBy: { updatedAt: 'desc' },
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
        },
      },
      ratedBy: { select: { id: true, name: true } },
    },
  });
  await prisma.auditLog.create({
    data: {
      actorId: user.id,
      teamId: match.teamId,
      action: 'MATCH_PLAYER_RATINGS_UPDATED',
      entityType: 'Event',
      entityId: match.id,
      metadata: { ratedPlayers: ratings.length },
    },
  });
  return res.json({ ratings });
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
  const match = await findAccessibleTickerMatch(req.params.id, req.user!);
  if (!match) return res.status(404).json({ message: 'Spiel nicht gefunden.' });
  const after = integer(req.query.after, 0, Number.MAX_SAFE_INTEGER, 0);
  const ticker = await prisma.liveTicker.findUnique({
    where: { eventId: match.id },
    include: {
      events: {
        where: { sequence: { gt: after }, revokedAt: null },
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
  const familyAttributionVisible =
    req.user!.role === Role.PARENT && match.familyReleasedAt !== null;
  return res.json({
    ...ticker,
    elapsedSeconds: elapsed(ticker),
    events: ticker.events.map((event) => ({
      ...event,
      scorer: tickerEditable || familyAttributionVisible || ticker.publicScorersEnabled ? event.scorer : null,
      assist: tickerEditable || familyAttributionVisible || ticker.publicScorersEnabled ? event.assist : null,
    })),
  });
}

export async function tickerCommand(req: Request, res: Response) {
  const user = req.user!;
  const match = await findTickerCommandMatch(req.params.id, user);
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
    } else if (type === TickerEventType.INTERRUPTION) {
      status = TickerStatus.PAUSED;
      clockStartedAt = null;
    } else if (type === TickerEventType.INJURY) {
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
  if (type === TickerEventType.MATCH_END) {
    await recalculateMatchStatistics(match.id);
  }
  return res.status(result.duplicate ? 200 : 201).json({
    ...result,
    ticker: { ...result.ticker, elapsedSeconds: elapsed(result.ticker) },
  });
}

export async function undoTickerEvent(req: Request, res: Response) {
  const user = req.user!;
  const match = await findTickerCommandMatch(req.params.id, user);
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
  if (ticker.status === TickerStatus.FINISHED) {
    await recalculateMatchStatistics(match.id);
  }
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
