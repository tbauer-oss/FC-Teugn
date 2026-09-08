import { randomUUID } from 'node:crypto';
import { Prisma, CarpoolNeed, CarpoolPassenger } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { AuthUser } from '../middleware/auth';
import { accessibleTeamIds, eventReadScope, matchParticipantPlayerScope, ownPlayerIds } from './team-access';
import { Permission } from '../security/permissions';
import { DomainError, permitted, stringIds } from './talents-domain';

export type RidePerson = { playerId: string | null; passengerUserId: string | null };
export const personKey = (person: RidePerson) => person.playerId ? `child:${person.playerId}` : `user:${person.passengerUserId}`;
export const samePerson = (a: RidePerson, b: RidePerson) => personKey(a) === personKey(b);
export const personWhere = (person: RidePerson) => person.playerId
  ? { playerId: person.playerId } : { passengerUserId: person.passengerUserId! };
export const isOwnRidePerson = (person: RidePerson, userId: string, ownIds: string[]) =>
  person.passengerUserId === userId || (person.playerId != null && ownIds.includes(person.playerId));
const eventRelations = { targetTeams: true, participants: { select: { playerId: true, responseRequired: true } } } as const;
type RideContext = {
  tx: Prisma.TransactionClient;
  event: Prisma.EventGetPayload<{ include: typeof eventRelations }>;
  ownIds: string[];
  staff: boolean;
  teamIds: string[];
};

/** Every mutation locks the event, so capacity checks and reservations are atomic
 * even when different families book different offers at the same time. */
export async function withCarpoolEvent<T>(user: AuthUser, eventId: string,
  operation: (context: RideContext) => Promise<T>, allowClosed = false): Promise<T> {
  if (user.role === 'READ_ONLY') throw new DomainError(403, 'Dieser Zugang kann Mitfahrten nur ansehen.');
  const [teamIds, ownIds] = await Promise.all([accessibleTeamIds(user), ownPlayerIds(user)]);
  const staffPermission = permitted(user, Permission.MANAGE_EVENTS);
  return prisma.$transaction(async tx => {
    await tx.$queryRaw`SELECT "id" FROM "Event" WHERE "id" = ${eventId} FOR UPDATE`;
    const event = await tx.event.findFirst({ where: {
      id: eventId,
      ...(staffPermission ? {} : { visibility: { not: 'STAFF_ONLY' as const } }),
      ...eventReadScope(teamIds, { userId: user.id, playerIds: ownIds }),
    }, include: eventRelations });
    if (!event) throw new DomainError(404, 'Termin nicht gefunden.');
    if (!allowClosed && event.status !== 'SCHEDULED') throw new DomainError(409, 'Für diesen Termin können keine Mitfahrten mehr gebucht werden.');
    const targets = event.targetTeams.length ? event.targetTeams.map(t => t.teamId) : [event.teamId];
    const staff = staffPermission && targets.every(id => teamIds.includes(id));
    return operation({ tx, event, ownIds, staff, teamIds });
  }, { timeout: 15000 });
}

export async function selectedRidePeople(context: RideContext, user: AuthUser, body: Record<string, unknown>) {
  const ids = stringIds(body.playerIds ?? (body.playerId ? [body.playerId] : []), 8);
  const includeSelf = body.includeSelf === true;
  if (!ids.length && !includeSelf) throw new DomainError(400, 'Bitte mindestens eine Person auswählen.');
  if (ids.length + Number(includeSelf) > 8) throw new DomainError(400, 'Höchstens acht Personen gleichzeitig auswählen.');
  if (!context.staff && ids.some(id => !context.ownIds.includes(id))) throw new DomainError(403, 'Du kannst Plätze nur für dich und deine eigenen Kinder buchen.');
  const targetTeamIds = context.event.targetTeams.length ? context.event.targetTeams.map(t => t.teamId) : [context.event.teamId];
  const players = await context.tx.player.findMany({ where: {
    id: { in: ids }, status: 'ACTIVE',
    eventParticipants: { none: { eventId: context.event.id, responseRequired: false } },
    OR: [{ teamId: { in: targetTeamIds } }, matchParticipantPlayerScope(context.event.id)],
  }, select: { id: true } });
  if (players.length !== ids.length) throw new DomainError(404, 'Ein Kind gehört nicht zu diesem Termin.');
  return [
    ...ids.map(playerId => ({ playerId, passengerUserId: null } as RidePerson)),
    ...(includeSelf ? [{ playerId: null, passengerUserId: user.id }] : []),
  ];
}

export async function saveRideNeed(tx: Prisma.TransactionClient, eventId: string, person: RidePerson,
  requestedById: string, status: 'OPEN' | 'MATCHED' | 'CANCELLED', note?: string | null, groupId?: string | null) {
  const where = person.playerId ? { eventId_playerId: { eventId, playerId: person.playerId } }
    : { eventId_passengerUserId: { eventId, passengerUserId: person.passengerUserId! } };
  return tx.carpoolNeed.upsert({ where, update: { status, requestedById, note, groupId },
    create: { playerId: person.playerId, passengerUserId: person.passengerUserId, eventId, requestedById, status, note, groupId } });
}

export async function saveRideBooking(tx: Prisma.TransactionClient, offerId: string, person: RidePerson, requestedById: string) {
  const where = person.playerId ? { offerId_playerId: { offerId, playerId: person.playerId } }
    : { offerId_passengerUserId: { offerId, passengerUserId: person.passengerUserId! } };
  return tx.carpoolPassenger.upsert({ where, update: { status: 'CONFIRMED', requestedById },
    create: { playerId: person.playerId, passengerUserId: person.passengerUserId, offerId, requestedById, status: 'CONFIRMED' } });
}

/** Open requests reserve real seats, never merely subtract an aggregate number.
 * People selected together stay in one car. Previously declined offers are skipped. */
export async function matchOpenRideNeeds(tx: Prisma.TransactionClient, eventId: string) {
  const event = await tx.event.findUnique({ where: { id: eventId }, select: { status: true, teamId: true, targetTeams: true } });
  if (!event || event.status !== 'SCHEDULED') return;
  const targets = event.targetTeams.length ? event.targetTeams.map(t => t.teamId) : [event.teamId];
  const [needs, offers] = await Promise.all([
    tx.carpoolNeed.findMany({ where: { eventId, status: 'OPEN' }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      include: { player: { select: { teamId: true, status: true } }, passengerUser: { select: { status: true } } } }),
    tx.carpoolOffer.findMany({ where: { eventId }, include: { passengers: true }, orderBy: [{ departureAt: 'asc' }, { createdAt: 'asc' }, { id: 'asc' }] }),
  ]);
  const booked = new Set(offers.flatMap(o => o.passengers.filter(p => p.status === 'CONFIRMED').map(personKey)));
  const eligiblePlayers = new Set((await tx.player.findMany({ where: {
    id: { in: needs.flatMap(need => need.playerId ? [need.playerId] : []) },
    status: 'ACTIVE',
    eventParticipants: { none: { eventId, responseRequired: false } },
    OR: [{ teamId: { in: targets } }, matchParticipantPlayerScope(eventId)],
  }, select: { id: true } })).map(player => player.id));
  const groups = new Map<string, typeof needs>();
  for (const need of needs) {
    if (booked.has(personKey(need))) {
      await tx.carpoolNeed.update({ where: { id: need.id }, data: { status: 'MATCHED' } });
      continue;
    }
    if (need.playerId && !eligiblePlayers.has(need.playerId)) continue;
    if (need.passengerUserId && need.passengerUser?.status !== 'APPROVED') continue;
    const key = need.groupId ?? need.id;
    groups.set(key, [...(groups.get(key) ?? []), need]);
  }
  for (const group of groups.values()) {
    const offer = offers.find(o => o.seatsTotal - o.passengers.filter(p => p.status === 'CONFIRMED').length >= group.length &&
      group.every(n => n.passengerUserId !== o.driverId && n.requestedById !== o.driverId &&
        !o.passengers.some(p => samePerson(p, n) && p.status === 'DECLINED')));
    if (!offer) continue;
    for (const need of group) {
      const passenger = await saveRideBooking(tx, offer.id, need, need.requestedById);
      offer.passengers = [...offer.passengers.filter(p => p.id !== passenger.id), passenger];
      await tx.carpoolPassenger.updateMany({ where: { offer: { eventId }, ...personWhere(need), status: 'REQUESTED', id: { not: passenger.id } }, data: { status: 'CANCELLED' } });
      await tx.carpoolNeed.update({ where: { id: need.id }, data: { status: 'MATCHED' } });
    }
  }
}

export function carpoolSummary(offers: Array<{ seatsTotal: number; passengers: Array<Pick<CarpoolPassenger, 'status' | 'playerId' | 'passengerUserId'>> }>,
  needs: Array<Pick<CarpoolNeed, 'status' | 'playerId' | 'passengerUserId'>>) {
  const confirmed = new Set(offers.flatMap(o => o.passengers.filter(p => p.status === 'CONFIRMED').map(personKey)));
  const open = new Set(needs.filter(n => n.status === 'OPEN' && !confirmed.has(personKey(n))).map(personKey));
  for (const offer of offers) for (const p of offer.passengers) if (p.status === 'REQUESTED' && !confirmed.has(personKey(p))) open.add(personKey(p));
  return { freeSeats: offers.reduce((n, o) => n + Math.max(0, o.seatsTotal - o.passengers.filter(p => p.status === 'CONFIRMED').length), 0),
    openNeeds: open.size, bookedSeats: confirmed.size, offers: offers.length };
}

export const newRideGroup = () => randomUUID();
