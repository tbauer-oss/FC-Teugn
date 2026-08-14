import {
  AccountStatus,
  NotificationCategory,
  NominationStatus,
  PlayerStatus,
  TickerEventType,
} from '@prisma/client';

import { prisma } from '../lib/prisma';
import { notifyUsers } from './notification.service';

export type LiveTickerNotificationEvent = {
  id: string;
  type: TickerEventType;
  ourGoals: number;
  theirGoals: number;
};

type LiveTickerNotificationMatch = {
  id: string;
  teamId: string;
  title: string;
  familyReleasedAt: Date | null;
  familyReleaseAudience: string | null;
  targetTeams: Array<{ teamId: string }>;
  matchDetails: { opponent: string; isHome: boolean } | null;
};

export function liveTickerNotificationCopy(input: {
  event: LiveTickerNotificationEvent;
  opponent: string;
  fcIsHome: boolean;
}) {
  const { event, opponent, fcIsHome } = input;
  const isOurGoal =
    (fcIsHome && event.type === TickerEventType.HOME_GOAL) ||
    (!fcIsHome && event.type === TickerEventType.AWAY_GOAL);
  const isTheirGoal =
    (fcIsHome && event.type === TickerEventType.AWAY_GOAL) ||
    (!fcIsHome && event.type === TickerEventType.HOME_GOAL);
  const score = `${event.ourGoals}:${event.theirGoals}`;
  if (event.type === TickerEventType.MATCH_START) {
    return {
      title: 'Anpfiff – FC Teugn live',
      body: `Das Spiel gegen ${opponent} läuft. Jetzt den Liveticker öffnen.`,
    };
  }
  if (isOurGoal) {
    return {
      title: `Tor für FC Teugn! ${score}`,
      body: `FC Teugn trifft gegen ${opponent}. Jetzt live mitfiebern.`,
    };
  }
  if (isTheirGoal) {
    return {
      title: `Gegentor · ${score}`,
      body: `${opponent} trifft. Der aktuelle Spielstand steht im Liveticker.`,
    };
  }
  if (event.type === TickerEventType.MATCH_END) {
    return {
      title: `Abpfiff · Endstand ${score}`,
      body: `Das Spiel von FC Teugn gegen ${opponent} ist beendet.`,
    };
  }
  return null;
}

export async function sendLiveTickerNotification(
  match: LiveTickerNotificationMatch,
  event: LiveTickerNotificationEvent,
) {
  const copy = liveTickerNotificationCopy({
    event,
    opponent: match.matchDetails?.opponent || 'den Gegner',
    fcIsHome: match.matchDetails?.isHome !== false,
  });
  if (!copy) return null;
  const recipientIds = await liveTickerNotificationAudience(match);
  if (!recipientIds.length) return null;
  return notifyUsers(recipientIds, {
    category: NotificationCategory.LIVE_TICKER,
    title: copy.title,
    body: copy.body,
    actionUrl: `/matches/${match.id}?tab=live`,
    entityType: 'LiveTickerEvent',
    entityId: event.id,
    dedupeKey: `live-ticker:${event.id}`,
    pushEnabled: true,
  });
}

async function liveTickerNotificationAudience(
  match: LiveTickerNotificationMatch,
) {
  const release = await effectiveFamilyRelease(match);
  if (!release) return [];
  const teamIds = match.targetTeams.length
    ? match.targetTeams.map((target) => target.teamId)
    : [match.teamId];
  const recipients = new Set<string>();
  // The ticker belongs to the whole team, not only to the match squad. Active
  // and injured players plus their guardians may therefore follow it even if
  // the child is ill, absent or not nominated.
  const teamPlayers = await prisma.player.findMany({
    where: {
      teamId: { in: teamIds },
      status: { in: [PlayerStatus.ACTIVE, PlayerStatus.INJURED] },
    },
    include: {
      parentLinks: {
        where: { receivesCommunication: true },
        select: { parentId: true },
      },
    },
  });
  teamPlayers.forEach((player) => {
    if (player.userId) recipients.add(player.userId);
    player.parentLinks.forEach((link) => recipients.add(link.parentId));
  });

  // A published squad may contain guests from another team. Their player
  // accounts and guardians get access to this exact match as well, without
  // receiving visibility into the rest of the host team's schedule.
  const squad = await prisma.squad.findFirst({
    where: { eventId: release.eventId, publishedAt: { not: null } },
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
  squad?.members.forEach((member) => {
    if (member.player.userId) recipients.add(member.player.userId);
    member.player.parentLinks.forEach((link) => recipients.add(link.parentId));
  });
  const staff = await prisma.teamMembership.findMany({
    where: {
      teamId: { in: teamIds },
      status: AccountStatus.APPROVED,
      user: { status: AccountStatus.APPROVED },
    },
    select: { userId: true },
  });
  staff.forEach((membership) => recipients.add(membership.userId));
  if (!recipients.size) return [];
  const approved = await prisma.user.findMany({
    where: { id: { in: [...recipients] }, status: AccountStatus.APPROVED },
    select: { id: true },
  });
  return approved.map((user) => user.id);
}

async function effectiveFamilyRelease(match: LiveTickerNotificationMatch) {
  if (!match.familyReleasedAt) return null;
  return {
    eventId: match.id,
  } as const;
}
