import {
  AttendanceStatus,
  CarpoolRequestStatus,
  EventVisibility,
  PlayerStatus,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hasEffectivePermission, Permission } from '../security/permissions';
import {
  contextualTeamIds,
  eventReadScope,
  ownPlayerIds,
} from '../services/team-access';
import { consentTemplates } from '../services/consent-templates';
import { routeEstimateFromTeugn } from '../services/route-estimate.service';

const dayMs = 86_400_000;

function requestedRange(req: Request) {
  const now = new Date();
  const parsedFrom = req.query.from ? new Date(String(req.query.from)) : null;
  const parsedTo = req.query.to ? new Date(String(req.query.to)) : null;
  const from = parsedFrom && !Number.isNaN(parsedFrom.getTime())
    ? parsedFrom
    : new Date(now.getTime() - dayMs);
  const maximumTo = new Date(from.getTime() + 62 * dayMs);
  const requestedTo = parsedTo && !Number.isNaN(parsedTo.getTime())
    ? parsedTo
    : new Date(now.getTime() + 8 * dayMs);
  return {
    from,
    to: requestedTo > maximumTo ? maximumTo : requestedTo,
  };
}

const playerSummarySelect = {
  id: true,
  teamId: true,
  firstName: true,
  lastName: true,
  preferredName: true,
  position: true,
  secondaryPosition: true,
  shirtNumber: true,
  status: true,
  photoUrl: true,
  team: {
    select: {
      name: true,
      teamNumber: true,
      ageGroup: { select: { code: true } },
    },
  },
} as const;

const eventSummaryScalars = {
  id: true,
  teamId: true,
  type: true,
  category: true,
  status: true,
  communicationStatus: true,
  visibility: true,
  title: true,
  startAt: true,
  endAt: true,
  meetingAt: true,
  meetingLocation: true,
  location: true,
  address: true,
  mapUrl: true,
  homeAway: true,
  opponent: true,
  venue: true,
  carpoolRequired: true,
  responseDeadline: true,
  reminderMinutes: true,
  reminderPushEnabled: true,
  isSeriesException: true,
  isHiddenRegularOccurrence: true,
  internalPublishedAt: true,
  familyReleasedAt: true,
  familyReleaseAudience: true,
  cancellationReason: true,
  attendanceFinalized: true,
  parentTournamentId: true,
} as const;

const targetTeamSummary = {
  select: {
    teamId: true,
    team: {
      select: {
        id: true,
        name: true,
        ageGroup: { select: { code: true } },
      },
    },
  },
} as const;

async function dashboardNotifications(userId: string) {
  const disabled = await prisma.notificationPreference.findMany({
    where: { userId, inApp: false },
    select: { category: true },
  });
  return prisma.notification.findMany({
    where: {
      userId,
      category: {
        notIn: disabled.map((item) => item.category),
        // Registrierungsanfragen have their own authoritative dashboard card.
        not: 'REGISTRATION',
      },
      readAt: null,
      AND: [{ OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] }],
    },
    orderBy: { createdAt: 'desc' },
    take: 30,
  });
}

export async function parentDashboardSummary(req: Request, res: Response) {
  const user = req.user!;
  const { from, to } = requestedRange(req);
  const [playerIds, teamIds] = await Promise.all([
    ownPlayerIds(user),
    contextualTeamIds(user),
  ]);
  const [players, events, notifications] = await Promise.all([
    prisma.player.findMany({
      where: { id: { in: playerIds } },
      select: playerSummarySelect,
      orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
    }),
    prisma.event.findMany({
      where: {
        parentTournamentId: null,
        isHiddenRegularOccurrence: false,
        visibility: { not: EventVisibility.STAFF_ONLY },
        startAt: { gte: from, lte: to },
        ...eventReadScope(teamIds, { userId: user.id, playerIds }),
      },
      select: {
        ...eventSummaryScalars,
        targetTeams: targetTeamSummary,
        carpoolOffers: {
          orderBy: { departureAt: 'asc' },
          select: {
            id: true,
            driverId: true,
            seatsTotal: true,
            departureLocation: true,
            departureAt: true,
            driver: { select: { name: true } },
            passengers: {
              where: { status: { not: CarpoolRequestStatus.CANCELLED } },
              select: { status: true },
            },
          },
        },
        carpoolNeeds: {
          where: {
            OR: [
              { playerId: { in: playerIds } },
              { status: 'OPEN' },
            ],
          },
          select: {
            id: true,
            playerId: true,
            status: true,
            note: true,
            player: {
              select: {
                firstName: true,
                lastName: true,
                preferredName: true,
              },
            },
          },
        },
      },
      orderBy: { startAt: 'asc' },
      take: 80,
    }),
    dashboardNotifications(user.id),
  ]);

  return res.json({
    range: { from, to },
    players,
    events: events.map((event) => ({
      ...event,
      targetTeams: event.targetTeams,
      attachments: [],
      attendance: [],
      attendanceSummary: {},
      missingAttendance: [],
      participants: [],
      tournamentFixtures: [],
      carpoolOffers: event.carpoolOffers.map((offer) => ({
        ...offer,
        freeSeats: Math.max(
          0,
          offer.seatsTotal - offer.passengers.filter(
            (passenger) => passenger.status === CarpoolRequestStatus.CONFIRMED,
          ).length,
        ),
        passengers: [],
        canManage: offer.driverId === user.id,
      })),
      carpoolNeeds: event.carpoolNeeds.map((need) => ({
        ...need,
        canCancel: playerIds.includes(need.playerId),
      })),
      capabilities: {},
    })),
    notifications,
  });
}

export async function parentConsentAttention(req: Request, res: Response) {
  const links = await prisma.parentPlayerLink.findMany({
    where: { parentId: req.user!.id, isLegalGuardian: true },
    select: { playerId: true },
  });
  const playerIds = links.map((link) => link.playerId);
  if (!playerIds.length) return res.json([]);
  const players = await prisma.player.findMany({
    where: { id: { in: playerIds } },
    select: {
      id: true,
      firstName: true,
      lastName: true,
      preferredName: true,
      consents: {
        select: { type: true, status: true, templateVersion: true },
      },
    },
    orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
  });
  const templates = Object.values(consentTemplates);
  return res.json(players.flatMap((player) => {
    const openCount = templates.filter((template) => {
      const decision = player.consents.find((item) => item.type === template.type);
      return !decision ||
        decision.templateVersion !== template.version ||
        !['GRANTED', 'REVOKED'].includes(decision.status);
    }).length;
    return openCount
      ? [{
          playerId: player.id,
          playerName: player.preferredName ||
            `${player.firstName} ${player.lastName}`.trim(),
          openCount,
        }]
      : [];
  }));
}

export async function trainerDashboardSummary(req: Request, res: Response) {
  const user = req.user!;
  if (!hasEffectivePermission(user.role, Permission.MANAGE_EVENTS, user.permissions)) {
    return res.status(403).json({ message: 'Trainer-Dashboard nicht verfügbar.' });
  }
  const { from, to } = requestedRange(req);
  const teamIds = await contextualTeamIds(user);
  const [players, events, notifications] = await Promise.all([
    prisma.player.findMany({
      where: { teamId: { in: teamIds }, status: { not: PlayerStatus.LEFT } },
      select: playerSummarySelect,
      orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
    }),
    prisma.event.findMany({
      where: {
        parentTournamentId: null,
        startAt: { gte: from, lte: to },
        OR: [
          { teamId: { in: teamIds } },
          { targetTeams: { some: { teamId: { in: teamIds } } } },
        ],
      },
      select: {
        ...eventSummaryScalars,
        targetTeams: targetTeamSummary,
        participants: {
          where: { playerId: { not: null } },
          select: { playerId: true, responseRequired: true },
        },
        attendance: {
          select: {
            id: true,
            playerId: true,
            status: true,
            reason: true,
            goalkeeperAvailable: true,
            respondedAt: true,
            player: {
              select: {
                id: true,
                teamId: true,
                firstName: true,
                lastName: true,
                preferredName: true,
                position: true,
                photoUrl: true,
              },
            },
          },
        },
      },
      orderBy: { startAt: 'asc' },
      take: 100,
    }),
    dashboardNotifications(user.id),
  ]);

  const activeRoster = players.filter((player) => player.status === PlayerStatus.ACTIVE);
  return res.json({
    range: { from, to },
    players,
    events: events.map((event) => {
      const eventTeamIds = event.targetTeams.length
        ? event.targetTeams.map((target) => target.teamId)
        : [event.teamId];
      const explicitIds = event.participants
        .filter((participant) => participant.responseRequired)
        .map((participant) => participant.playerId)
        .filter((id): id is string => Boolean(id));
      const excludedIds = new Set(
        event.participants
          .filter((participant) => !participant.responseRequired)
          .map((participant) => participant.playerId)
          .filter((id): id is string => Boolean(id)),
      );
      const roster = activeRoster.filter((player) =>
        player.teamId !== null &&
        eventTeamIds.includes(player.teamId) &&
        (!explicitIds.length || explicitIds.includes(player.id)) &&
        !excludedIds.has(player.id),
      );
      const rosterIds = new Set(roster.map((player) => player.id));
      const visibleAttendance = event.attendance.filter((attendance) =>
        rosterIds.has(attendance.playerId) &&
        attendance.player.teamId !== null &&
        eventTeamIds.includes(attendance.player.teamId),
      );
      const responseByPlayer = new Map(
        visibleAttendance.map((attendance) => [attendance.playerId, attendance]),
      );
      const missing = roster.filter((player) => {
        const status = responseByPlayer.get(player.id)?.status;
        return !status ||
          status === AttendanceStatus.UNKNOWN ||
          status === AttendanceStatus.MAYBE;
      });
      return {
        ...event,
        attachments: [],
        tournamentFixtures: [],
        carpoolOffers: [],
        carpoolNeeds: [],
        attendance: visibleAttendance,
        attendanceSummary: {
          yes: visibleAttendance.filter((item) => item.status === AttendanceStatus.YES).length,
          no: visibleAttendance.filter((item) => item.status === AttendanceStatus.NO).length,
          maybe: 0,
          unknown: missing.length,
          goalkeeperAvailable: visibleAttendance.filter(
            (item) => item.status === AttendanceStatus.YES &&
              (item.goalkeeperAvailable === true ||
                item.player.position?.toLowerCase().includes('tor')),
          ).length,
        },
        missingAttendance: missing,
        capabilities: { canManage: true },
      };
    }),
    notifications,
  });
}

export async function eventRouteEstimate(req: Request, res: Response) {
  const user = req.user!;
  const canManageEvents = hasEffectivePermission(
    user.role,
    Permission.MANAGE_EVENTS,
    user.permissions,
  );
  const [teamIds, playerIds] = await Promise.all([
    contextualTeamIds(user),
    ownPlayerIds(user),
  ]);
  const event = await prisma.event.findFirst({
    where: {
      id: req.params.eventId,
      ...(canManageEvents
        ? {}
        : { visibility: { not: EventVisibility.STAFF_ONLY } }),
      ...eventReadScope(teamIds, { userId: user.id, playerIds }),
    },
    select: {
      address: true,
      location: true,
      homeAway: true,
      type: true,
      matchDetails: { select: { isHome: true } },
      routeEstimateAddress: true,
      routeDistanceKm: true,
      routeDurationMinutes: true,
    },
  });
  if (!event) return res.status(404).json({ message: 'Termin nicht gefunden.' });
  const isAway = event.matchDetails?.isHome === false || event.homeAway === 'AWAY';
  if (event.type !== 'MATCH' || !isAway) {
    return res.json({ available: false });
  }
  // Route estimates deliberately require the persisted postal address. A
  // venue-only value such as "Waldstadion" is too ambiguous for dependable
  // navigation and must never replace a previously resolved full address.
  const destination = event.address?.trim();
  if (!destination) return res.json({ available: false });
  if (
    event.routeEstimateAddress === destination &&
    event.routeDistanceKm !== null &&
    event.routeDurationMinutes !== null
  ) {
    return res.json({
      available: true,
      distanceKm: event.routeDistanceKm,
      durationMinutes: event.routeDurationMinutes,
      attribution: '© OpenStreetMap-Mitwirkende',
    });
  }
  const estimate = await routeEstimateFromTeugn(destination);
  if (estimate) {
    await prisma.event.update({
      where: { id: req.params.eventId },
      data: {
        routeEstimateAddress: destination,
        routeDistanceKm: estimate.distanceKm,
        routeDurationMinutes: estimate.durationMinutes,
        routeEstimatedAt: new Date(),
      },
    });
  }
  return res.json(estimate ?? { available: false });
}
