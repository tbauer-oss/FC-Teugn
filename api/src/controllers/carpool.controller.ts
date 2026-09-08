import { Request, Response } from 'express';
import { DomainError, textValue, oneOf } from '../services/talents-domain';
import {
  withCarpoolEvent, selectedRidePeople, saveRideBooking, saveRideNeed,
  matchOpenRideNeeds, isOwnRidePerson, samePerson, personWhere, newRideGroup,
} from '../services/carpool.service';

export async function createCarpoolOffer(req: Request, res: Response) {
  const seatsTotal = Number(req.body.seatsTotal);
  if (!Number.isInteger(seatsTotal) || seatsTotal < 1 || seatsTotal > 8) throw new DomainError(400, 'Bitte ein bis acht freie Plätze angeben.');
  const departureLocation = textValue(req.body.departureLocation, 'Abfahrtsort', 160);
  const departureAt = new Date(String(req.body.departureAt ?? ''));
  if (!Number.isFinite(departureAt.getTime())) throw new DomainError(400, 'Bitte eine gültige Abfahrtszeit angeben.');
  const notes = req.body.notes ? textValue(req.body.notes, 'Hinweis', 500) : null;
  const offer = await withCarpoolEvent(req.user!, req.params.id, async ({ tx, event }) => {
    if (departureAt > event.startAt) throw new DomainError(400, 'Die Abfahrt muss vor dem Terminbeginn liegen.');
    const data = { eventId: event.id, driverId: req.user!.id, seatsTotal, departureLocation, departureAt, notes };
    // A retry after a lost response must not create a second identical car.
    const saved = await tx.carpoolOffer.findFirst({ where: data }) ?? await tx.carpoolOffer.create({ data });
    await matchOpenRideNeeds(tx, event.id);
    return saved;
  });
  return res.status(201).json(offer);
}

export async function createCarpoolNeeds(req: Request, res: Response) {
  const note = req.body.note ? textValue(req.body.note, 'Hinweis', 500) : null;
  const needs = await withCarpoolEvent(req.user!, req.params.id, async context => {
    const { tx, event } = context;
    const people = await selectedRidePeople(context, req.user!, req.body);
    const bookings = await tx.carpoolPassenger.findMany({ where: { offer: { eventId: event.id }, status: 'CONFIRMED' } });
    const alreadyBooked = people.filter(person => bookings.some(p => samePerson(p, person)));
    if (alreadyBooked.length > 0 && alreadyBooked.length < people.length) {
      throw new DomainError(409, 'Eine ausgewählte Person hat bereits eine Fahrt. Bitte diese zuerst stornieren, um gemeinsam zu buchen.');
    }
    const groupId = alreadyBooked.length ? undefined : newRideGroup();
    const ids = [];
    for (const person of people) {
      const booked = bookings.some(p => samePerson(p, person));
      ids.push((await saveRideNeed(tx, event.id, person, req.user!.id, booked ? 'MATCHED' : 'OPEN', note, groupId)).id);
    }
    await matchOpenRideNeeds(tx, event.id);
    return tx.carpoolNeed.findMany({ where: { id: { in: ids } } });
  });
  return res.status(201).json(needs);
}

export async function requestCarpoolSeat(req: Request, res: Response) {
  const passengers = await withCarpoolEvent(req.user!, req.params.id, async context => {
    const { tx, event } = context;
    const offer = await tx.carpoolOffer.findFirst({ where: { id: req.params.offerId, eventId: event.id }, include: { passengers: true } });
    if (!offer) throw new DomainError(404, 'Fahrangebot nicht gefunden.');
    const people = await selectedRidePeople(context, req.user!, req.body);
    if (people.some(p => p.passengerUserId === offer.driverId)) throw new DomainError(409, 'Du bist bereits als Fahrer eingetragen.');
    const bookings = await tx.carpoolPassenger.findMany({ where: { offer: { eventId: event.id }, status: 'CONFIRMED' } });
    if (people.some(person => bookings.some(p => samePerson(p, person) && p.offerId !== offer.id))) {
      throw new DomainError(409, 'Für eine ausgewählte Person ist bereits eine andere Fahrt gebucht. Bitte diese zuerst stornieren.');
    }
    const additional = people.filter(person => !bookings.some(p => samePerson(p, person))).length;
    const free = offer.seatsTotal - offer.passengers.filter(p => p.status === 'CONFIRMED').length;
    if (additional > free) throw new DomainError(409, `Inzwischen ${Math.max(0, free)} ${free === 1 ? 'Platz' : 'Plätze'} frei. Bitte Auswahl aktualisieren.`);
    // A repeated booking must also preserve the original family group.
    if (additional === 0) return bookings.filter(p => p.offerId === offer.id && people.some(person => samePerson(p, person)));
    const result = [];
    const groupId = newRideGroup();
    for (const person of people) {
      const saved = await saveRideBooking(tx, offer.id, person, req.user!.id);
      result.push(saved);
      await tx.carpoolPassenger.updateMany({ where: { offer: { eventId: event.id }, ...personWhere(person), status: 'REQUESTED', id: { not: saved.id } }, data: { status: 'CANCELLED' } });
      await saveRideNeed(tx, event.id, person, req.user!.id, 'MATCHED', undefined, groupId);
    }
    return result;
  });
  // Older APKs send a single playerId and ignore the response body.
  return res.status(201).json(req.body.playerId ? passengers[0] : { passengers });
}

export async function deleteCarpoolNeed(req: Request, res: Response) {
  await withCarpoolEvent(req.user!, req.params.id, async ({ tx, event, ownIds, staff }) => {
    const need = await tx.carpoolNeed.findFirst({ where: { id: req.params.needId, eventId: event.id } });
    if (!need) return;
    if (!staff && need.requestedById !== req.user!.id && !isOwnRidePerson(need, req.user!.id, ownIds)) throw new DomainError(403, 'Keine Berechtigung für diesen Mitfahrbedarf.');
    await tx.carpoolPassenger.updateMany({ where: { offer: { eventId: event.id }, ...personWhere(need), status: { in: ['CONFIRMED', 'REQUESTED'] } }, data: { status: 'CANCELLED' } });
    await tx.carpoolNeed.delete({ where: { id: need.id } });
    await matchOpenRideNeeds(tx, event.id);
  }, true);
  return res.status(204).send();
}

export async function deleteCarpoolOffer(req: Request, res: Response) {
  await withCarpoolEvent(req.user!, req.params.id, async ({ tx, event, staff }) => {
    const offer = await tx.carpoolOffer.findFirst({ where: { id: req.params.offerId, eventId: event.id }, include: { passengers: true } });
    if (!offer) return;
    if (!staff && offer.driverId !== req.user!.id) throw new DomainError(403, 'Keine Berechtigung für dieses Fahrangebot.');
    for (const passenger of offer.passengers.filter(p => ['CONFIRMED', 'REQUESTED'].includes(p.status))) {
      await saveRideNeed(tx, event.id, passenger, passenger.requestedById, 'OPEN');
    }
    await tx.carpoolOffer.delete({ where: { id: offer.id } });
    await matchOpenRideNeeds(tx, event.id);
  }, true);
  return res.status(204).send();
}

export async function updateCarpoolPassenger(req: Request, res: Response) {
  const status = oneOf(req.body.status, ['CONFIRMED', 'DECLINED', 'CANCELLED'] as const);
  const passenger = await withCarpoolEvent(req.user!, req.params.id, async ({ tx, event, staff, ownIds }) => {
    const passenger = await tx.carpoolPassenger.findFirst({ where: { id: req.params.passengerId, offerId: req.params.offerId, offer: { eventId: event.id } }, include: { offer: true } });
    if (!passenger) throw new DomainError(404, 'Buchung nicht gefunden.');
    const driverOrStaff = staff || passenger.offer.driverId === req.user!.id;
    const own = passenger.requestedById === req.user!.id || isOwnRidePerson(passenger, req.user!.id, ownIds);
    if (!driverOrStaff && (!own || status !== 'CANCELLED')) throw new DomainError(403, 'Keine Berechtigung für diese Buchung.');
    if (status === 'CONFIRMED' && passenger.status !== 'CONFIRMED') {
      if (event.status !== 'SCHEDULED') throw new DomainError(409, 'Dieser Termin ist geschlossen.');
      const elsewhere = await tx.carpoolPassenger.count({ where: { offer: { eventId: event.id }, ...personWhere(passenger), status: 'CONFIRMED', id: { not: passenger.id } } });
      if (elsewhere) throw new DomainError(409, 'Diese Person hat bereits einen Platz.');
      const occupied = await tx.carpoolPassenger.count({ where: { offerId: passenger.offerId, status: 'CONFIRMED' } });
      if (occupied >= passenger.offer.seatsTotal) throw new DomainError(409, 'Alle Plätze sind bereits belegt.');
    }
    // Driver cancellation is a declined ride, so automatic matching skips that car.
    const nextStatus = status === 'CANCELLED' && !own ? 'DECLINED' : status;
    if (passenger.status === nextStatus) return passenger;
    const updated = await tx.carpoolPassenger.update({ where: { id: passenger.id }, data: { status: nextStatus } });
    const needStatus = status === 'CONFIRMED' ? 'MATCHED' : own && status === 'CANCELLED' ? 'CANCELLED' : 'OPEN';
    await saveRideNeed(tx, event.id, passenger, passenger.requestedById, needStatus);
    await matchOpenRideNeeds(tx, event.id);
    return updated;
  }, true);
  return res.json(passenger);
}
