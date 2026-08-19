import {
  AccountStatus,
  EventStatus,
  KitLaundryAssignmentSource,
  KitLaundryDutyStatus,
  NominationStatus,
  NotificationCategory,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { notifyUsers } from './notification.service';

type LaundryFamily = {
  key: string;
  playerId: string;
  playerIds: string[];
  playerNames: string[];
  guardianIds: string[];
  guardianNames: string[];
};

function displayName(player: {
  firstName: string;
  lastName: string;
  preferredName: string | null;
}) {
  return player.preferredName?.trim() ||
    `${player.firstName} ${player.lastName}`.trim();
}

async function canonicalLaundryEvent(eventId: string) {
  const event = await prisma.event.findUnique({
    where: { id: eventId },
    select: {
      id: true,
      parentTournamentId: true,
      teamId: true,
      title: true,
      startAt: true,
      status: true,
    },
  });
  if (!event?.parentTournamentId) return event;
  return prisma.event.findUnique({
    where: { id: event.parentTournamentId },
    select: {
      id: true,
      parentTournamentId: true,
      teamId: true,
      title: true,
      startAt: true,
      status: true,
    },
  });
}

async function eligibleLaundryFamilies(eventId: string) {
  const squad = await prisma.squad.findUnique({
    where: { eventId },
    select: {
      publishedAt: true,
      members: {
        where: { status: NominationStatus.NOMINATED },
        orderBy: { createdAt: 'asc' },
        select: {
          playerId: true,
          player: {
            select: {
              firstName: true,
              lastName: true,
              preferredName: true,
              parentLinks: {
                where: {
                  receivesCommunication: true,
                  parent: { status: AccountStatus.APPROVED },
                },
                orderBy: { parentId: 'asc' },
                select: {
                  parentId: true,
                  parent: { select: { name: true } },
                },
              },
            },
          },
        },
      },
    },
  });
  if (!squad?.publishedAt) {
    return { published: false, families: [] as LaundryFamily[] };
  }
  const grouped = new Map<string, LaundryFamily>();
  for (const member of squad.members) {
    const guardianIds = member.player.parentLinks
      .map((link) => link.parentId)
      .sort();
    if (!guardianIds.length) continue;
    // Dieselbe Kombination aus Sorgeberechtigten bildet eine Familie. So
    // zählen Geschwister nur einmal in der fairen Rotation.
    const key = guardianIds.join(':');
    const existing = grouped.get(key);
    if (existing) {
      existing.playerIds.push(member.playerId);
      existing.playerNames.push(displayName(member.player));
      continue;
    }
    grouped.set(key, {
      key,
      playerId: member.playerId,
      playerIds: [member.playerId],
      playerNames: [displayName(member.player)],
      guardianIds,
      guardianNames: member.player.parentLinks.map((link) => link.parent.name),
    });
  }
  return { published: true, families: [...grouped.values()] };
}

async function rankedFamilies(
  eventId: string,
  teamId: string,
  families: LaundryFamily[],
  excluded: string[],
) {
  const keys = families.map((family) => family.key);
  if (!keys.length) return [];
  const history = await prisma.kitLaundryDuty.findMany({
    where: {
      eventId: { not: eventId },
      teamId,
      assignedFamilyKey: { in: keys },
      status: { in: [KitLaundryDutyStatus.CONFIRMED, KitLaundryDutyStatus.COMPLETED] },
    },
    select: {
      assignedFamilyKey: true,
      confirmedAt: true,
      completedAt: true,
    },
  });
  const stats = new Map<string, { count: number; lastAt: number }>();
  for (const item of history) {
    if (!item.assignedFamilyKey) continue;
    const current = stats.get(item.assignedFamilyKey) ?? { count: 0, lastAt: 0 };
    current.count += 1;
    current.lastAt = Math.max(
      current.lastAt,
      item.completedAt?.getTime() ?? item.confirmedAt?.getTime() ?? 0,
    );
    stats.set(item.assignedFamilyKey, current);
  }
  const excludedKeys = new Set(excluded);
  return families
    .filter((family) => !excludedKeys.has(family.key))
    .sort((left, right) => {
      const leftStats = stats.get(left.key) ?? { count: 0, lastAt: 0 };
      const rightStats = stats.get(right.key) ?? { count: 0, lastAt: 0 };
      return leftStats.count - rightStats.count ||
        leftStats.lastAt - rightStats.lastAt ||
        left.playerNames.join(' ').localeCompare(right.playerNames.join(' '), 'de');
    });
}

async function notifyProposal(
  event: { id: string; title: string },
  dutyId: string,
  family: LaundryFamily,
  version: Date,
) {
  return notifyUsers(family.guardianIds, {
    category: NotificationCategory.MATCH,
    title: `Trikotdienst · ${event.title}`,
    body: `${family.playerNames.join(' & ')}: Eure Familie ist mit dem Trikotwaschen an der Reihe. Bitte bestätigen oder ablehnen.`,
    actionUrl: `/matches/${event.id}`,
    entityType: 'KitLaundryDuty',
    entityId: dutyId,
    dedupeKey: `kit-laundry-proposal:${dutyId}:${version.getTime()}`,
    pushEnabled: true,
  });
}

async function proposeNextFamily(eventId: string) {
  const event = await canonicalLaundryEvent(eventId);
  if (!event || event.status === EventStatus.CANCELLED) return null;
  const eligibility = await eligibleLaundryFamilies(event.id);
  const duty = await prisma.kitLaundryDuty.upsert({
    where: { eventId: event.id },
    create: { eventId: event.id, teamId: event.teamId },
    update: {},
  });
  if (!eligibility.published || !eligibility.families.length) return duty;

  const existingFamily = eligibility.families.find(
    (family) => family.key === duty.assignedFamilyKey,
  );
  if (
    existingFamily &&
    duty.assignedPlayerId &&
    duty.status !== KitLaundryDutyStatus.OPEN
  ) {
    return duty;
  }
  if (duty.status === KitLaundryDutyStatus.COMPLETED) return duty;

  if (duty.assignedFamilyKey && !existingFamily) {
    await prisma.kitLaundryDuty.updateMany({
      where: { id: duty.id, assignedFamilyKey: duty.assignedFamilyKey },
      data: {
        status: KitLaundryDutyStatus.OPEN,
        assignedPlayerId: null,
        assignedFamilyKey: null,
        confirmedAt: null,
        confirmedById: null,
      },
    });
  }
  const current = await prisma.kitLaundryDuty.findUnique({ where: { id: duty.id } });
  if (!current || current.status === KitLaundryDutyStatus.COMPLETED) return current;
  const [next] = await rankedFamilies(
    event.id,
    event.teamId,
    eligibility.families,
    current.declinedFamilyKeys,
  );
  if (!next) return current;
  const proposedAt = new Date();
  const claimed = await prisma.kitLaundryDuty.updateMany({
    where: {
      id: current.id,
      status: KitLaundryDutyStatus.OPEN,
      assignedFamilyKey: null,
    },
    data: {
      assignedPlayerId: next.playerId,
      assignedFamilyKey: next.key,
      status: KitLaundryDutyStatus.PROPOSED,
      assignmentSource: KitLaundryAssignmentSource.AUTOMATIC,
      proposedAt,
      reminderSentAt: null,
    },
  });
  if (claimed.count) {
    await notifyProposal(event, current.id, next, proposedAt);
  }
  return prisma.kitLaundryDuty.findUnique({ where: { id: current.id } });
}

export async function reconcileKitLaundryDuty(eventId: string) {
  return proposeNextFamily(eventId);
}

export async function kitLaundryDutyView(
  eventId: string,
  viewerId: string,
  canManage: boolean,
) {
  const event = await canonicalLaundryEvent(eventId);
  if (!event) return null;
  await proposeNextFamily(event.id);
  const [duty, eligibility] = await Promise.all([
    prisma.kitLaundryDuty.findUnique({
      where: { eventId: event.id },
      include: {
        assignedPlayer: {
          select: { firstName: true, lastName: true, preferredName: true },
        },
        confirmedBy: { select: { name: true } },
      },
    }),
    eligibleLaundryFamilies(event.id),
  ]);
  const assignedFamily = eligibility.families.find(
    (family) => family.key === duty?.assignedFamilyKey,
  );
  const viewerFamily = eligibility.families.find(
    (family) => family.guardianIds.includes(viewerId),
  );
  const viewerAssigned = viewerFamily?.key === duty?.assignedFamilyKey;
  return {
    eventId: event.id,
    title: event.title,
    startAt: event.startAt,
    status: duty?.status ?? KitLaundryDutyStatus.OPEN,
    assignmentSource: duty?.assignmentSource ?? KitLaundryAssignmentSource.AUTOMATIC,
    assignedPlayerId: duty?.assignedPlayerId,
    assignedPlayerName: assignedFamily?.playerNames.join(' & ') ??
      (duty?.assignedPlayer ? displayName(duty.assignedPlayer) : null),
    assignedFamilyLabel: assignedFamily
      ? `Familie ${assignedFamily.playerNames.join(' & ')}`
      : null,
    confirmedByName: duty?.confirmedBy?.name ?? null,
    proposedAt: duty?.proposedAt,
    confirmedAt: duty?.confirmedAt,
    completedAt: duty?.completedAt,
    eligibleFamilyCount: eligibility.families.length,
    nominationPublished: eligibility.published,
    viewerEligible: Boolean(viewerFamily),
    viewerAssigned,
    canRespond: Boolean(viewerAssigned && duty?.status === KitLaundryDutyStatus.PROPOSED),
    canComplete: Boolean(
      (canManage || viewerAssigned) && duty?.status === KitLaundryDutyStatus.CONFIRMED,
    ),
    canManage,
    candidates: canManage
      ? eligibility.families.map((family) => ({
          familyKey: family.key,
          playerId: family.playerId,
          playerNames: family.playerNames,
          guardianNames: family.guardianNames,
          selected: family.key === duty?.assignedFamilyKey,
        }))
      : [],
  };
}

export async function assignKitLaundryDuty(
  eventId: string,
  playerId: string,
) {
  const event = await canonicalLaundryEvent(eventId);
  if (!event) return { ok: false as const, code: 'NOT_FOUND' };
  const eligibility = await eligibleLaundryFamilies(event.id);
  const family = eligibility.families.find(
    (candidate) => candidate.playerIds.includes(playerId),
  );
  if (!eligibility.published) return { ok: false as const, code: 'SQUAD_NOT_PUBLISHED' };
  if (!family) return { ok: false as const, code: 'NOT_ELIGIBLE' };
  const proposedAt = new Date();
  const duty = await prisma.kitLaundryDuty.upsert({
    where: { eventId: event.id },
    create: {
      eventId: event.id,
      teamId: event.teamId,
      assignedPlayerId: family.playerId,
      assignedFamilyKey: family.key,
      status: KitLaundryDutyStatus.PROPOSED,
      assignmentSource: KitLaundryAssignmentSource.MANUAL,
      proposedAt,
    },
    update: {
      assignedPlayerId: family.playerId,
      assignedFamilyKey: family.key,
      status: KitLaundryDutyStatus.PROPOSED,
      assignmentSource: KitLaundryAssignmentSource.MANUAL,
      proposedAt,
      confirmedAt: null,
      confirmedById: null,
      completedAt: null,
      reminderSentAt: null,
    },
  });
  await notifyProposal(event, duty.id, family, duty.updatedAt);
  return { ok: true as const, duty };
}

export async function respondToKitLaundryDuty(
  eventId: string,
  userId: string,
  accepted: boolean,
) {
  const event = await canonicalLaundryEvent(eventId);
  if (!event) return { ok: false as const, code: 'NOT_FOUND' };
  const [duty, eligibility] = await Promise.all([
    prisma.kitLaundryDuty.findUnique({ where: { eventId: event.id } }),
    eligibleLaundryFamilies(event.id),
  ]);
  if (!duty || duty.status !== KitLaundryDutyStatus.PROPOSED || !duty.assignedFamilyKey) {
    return { ok: false as const, code: 'NO_OPEN_PROPOSAL' };
  }
  const family = eligibility.families.find(
    (candidate) => candidate.key === duty.assignedFamilyKey &&
      candidate.guardianIds.includes(userId),
  );
  if (!family) return { ok: false as const, code: 'NOT_ASSIGNED' };
  if (accepted) {
    const confirmedAt = new Date();
    const updated = await prisma.kitLaundryDuty.updateMany({
      where: {
        id: duty.id,
        status: KitLaundryDutyStatus.PROPOSED,
        assignedFamilyKey: family.key,
      },
      data: {
        status: KitLaundryDutyStatus.CONFIRMED,
        confirmedAt,
        confirmedById: userId,
      },
    });
    return updated.count
      ? { ok: true as const, accepted: true as const }
      : { ok: false as const, code: 'ALREADY_CHANGED' };
  }
  const declinedFamilyKeys = [...new Set([...duty.declinedFamilyKeys, family.key])];
  const updated = await prisma.kitLaundryDuty.updateMany({
    where: {
      id: duty.id,
      status: KitLaundryDutyStatus.PROPOSED,
      assignedFamilyKey: family.key,
    },
    data: {
      status: KitLaundryDutyStatus.OPEN,
      assignedPlayerId: null,
      assignedFamilyKey: null,
      declinedFamilyKeys,
      proposedAt: null,
    },
  });
  if (!updated.count) return { ok: false as const, code: 'ALREADY_CHANGED' };
  await proposeNextFamily(event.id);
  return { ok: true as const, accepted: false as const };
}

export async function completeKitLaundryDuty(eventId: string, userId: string, canManage: boolean) {
  const event = await canonicalLaundryEvent(eventId);
  if (!event) return { ok: false as const, code: 'NOT_FOUND' };
  const [duty, eligibility] = await Promise.all([
    prisma.kitLaundryDuty.findUnique({ where: { eventId: event.id } }),
    eligibleLaundryFamilies(event.id),
  ]);
  if (!duty || duty.status !== KitLaundryDutyStatus.CONFIRMED) {
    return { ok: false as const, code: 'NOT_CONFIRMED' };
  }
  const assigned = eligibility.families.find(
    (family) => family.key === duty.assignedFamilyKey,
  );
  if (!canManage && !assigned?.guardianIds.includes(userId)) {
    return { ok: false as const, code: 'NOT_ASSIGNED' };
  }
  await prisma.kitLaundryDuty.update({
    where: { id: duty.id },
    data: { status: KitLaundryDutyStatus.COMPLETED, completedAt: new Date() },
  });
  return { ok: true as const };
}

export async function processKitLaundryReminders(now = new Date()) {
  const from = new Date(now.getTime() + 55 * 60_000);
  const to = new Date(now.getTime() + 65 * 60_000);
  const events = await prisma.event.findMany({
    where: {
      type: 'MATCH',
      status: EventStatus.SCHEDULED,
      parentTournamentId: null,
      startAt: { gte: from, lte: to },
      OR: [
        { kitLaundryDuty: null },
        {
          kitLaundryDuty: {
            is: {
              status: { in: [KitLaundryDutyStatus.OPEN, KitLaundryDutyStatus.PROPOSED] },
              reminderSentAt: null,
            },
          },
        },
      ],
    },
    select: { id: true, teamId: true, title: true },
    take: 100,
  });
  let reminded = 0;
  let trainerHints = 0;
  for (const event of events) {
    await proposeNextFamily(event.id);
    const [duty, eligibility] = await Promise.all([
      prisma.kitLaundryDuty.findUnique({ where: { eventId: event.id } }),
      eligibleLaundryFamilies(event.id),
    ]);
    if (!duty || duty.reminderSentAt ||
      duty.status === KitLaundryDutyStatus.CONFIRMED ||
      duty.status === KitLaundryDutyStatus.COMPLETED) {
      continue;
    }
    const claimed = await prisma.kitLaundryDuty.updateMany({
      where: { id: duty.id, reminderSentAt: null },
      data: { reminderSentAt: now },
    });
    if (!claimed.count) continue;
    const guardianIds = [...new Set(eligibility.families.flatMap((family) => family.guardianIds))];
    if (guardianIds.length) {
      await notifyUsers(guardianIds, {
        category: NotificationCategory.URGENT,
        title: `Trikotdienst noch offen · ${event.title}`,
        body: 'In einer Stunde ist Anpfiff. Für die nominierten Kinder wird noch eine Familie zum Trikotwaschen benötigt.',
        actionUrl: `/matches/${event.id}`,
        entityType: 'KitLaundryDuty',
        entityId: duty.id,
        dedupeKey: `kit-laundry-hour:${duty.id}`,
        pushEnabled: true,
      });
      reminded += 1;
      continue;
    }
    const staff = await prisma.user.findMany({
      where: {
        status: AccountStatus.APPROVED,
        memberships: {
          some: { teamId: event.teamId, status: AccountStatus.APPROVED },
        },
        role: { in: ['COACH', 'TRAINER', 'ASSISTANT_COACH', 'TEAM_MANAGER'] },
      },
      select: { id: true },
    });
    await notifyUsers(staff.map((user) => user.id), {
      category: NotificationCategory.MATCH,
      title: `Trikotdienst prüfen · ${event.title}`,
      body: 'Eine Stunde vor Anpfiff ist noch kein Trikotdienst bestätigt. Es gibt aktuell keinen veröffentlichten Kader mit erreichbaren Sorgeberechtigten.',
      actionUrl: `/matches/${event.id}`,
      entityType: 'KitLaundryDuty',
      entityId: duty.id,
      dedupeKey: `kit-laundry-staff-hour:${duty.id}`,
      pushEnabled: true,
    });
    trainerHints += 1;
  }
  return { candidates: events.length, reminded, trainerHints };
}
