const assert = require('node:assert/strict');

module.exports = async function carpoolIntegration({ prisma, call, team, foreignTeam, club, coach, parent, secondParent, stranger, player }) {
  const controller = require('../dist/src/controllers/carpool.controller');
  const events = require('../dist/src/controllers/events.controller');
  const dashboard = require('../dist/src/controllers/dashboard.controller');
  const { carpoolSummary } = require('../dist/src/services/carpool.service');
  const sibling = await prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: 'Zweites', lastName: 'Kind' } });
  await prisma.parentPlayerLink.create({ data: { parentId: parent.id, playerId: sibling.id } });
  const event = await prisma.event.create({ data: { teamId: team.id, title: 'Mitfahr-Abnahme', type: 'MATCH', location: 'Testplatz', startAt: new Date('2030-09-17T10:00:00Z'), familyReleasedAt: new Date() } });
  const params = { id: event.id };
  const offerInput = (seats, where = 'Treffpunkt') => ({ seatsTotal: seats, departureLocation: where, departureAt: '2030-09-17T09:00:00Z' });
  const summary = async () => carpoolSummary(
    await prisma.carpoolOffer.findMany({ where: { eventId: event.id }, include: { passengers: true } }),
    await prisma.carpoolNeed.findMany({ where: { eventId: event.id } }),
  );
  const five = await call(controller.createCarpoolOffer, coach, offerInput(5), params);
  await call(controller.createCarpoolOffer, coach, offerInput(5), params);
  assert.equal(await prisma.carpoolOffer.count({ where: { eventId: event.id } }), 1, 'Lost offer response cannot create a duplicate car');
  await call(controller.requestCarpoolSeat, parent, { playerIds: [player.id] }, { ...params, offerId: five.id });
  assert.equal((await summary()).freeSeats, 4, '5 offered minus one directly booked child equals 4');
  await call(controller.requestCarpoolSeat, secondParent, { playerId: player.id }, { ...params, offerId: five.id });
  assert.equal((await summary()).freeSeats, 4, 'Second guardian or old APK retry cannot double book the child');
  await call(controller.requestCarpoolSeat, parent, { playerIds: [sibling.id], includeSelf: true }, { ...params, offerId: five.id });
  assert.equal((await summary()).freeSeats, 2, 'Adult and child occupy one seat each');
  const familyGroup = (await prisma.carpoolNeed.findFirst({ where: { eventId: event.id, playerId: sibling.id } })).groupId;
  await call(controller.requestCarpoolSeat, parent, { playerId: sibling.id }, { ...params, offerId: five.id });
  assert.equal((await prisma.carpoolNeed.findFirst({ where: { eventId: event.id, playerId: sibling.id } })).groupId, familyGroup, 'A single-seat retry preserves the family group');
  const parentEvent = await call(events.getEvent, parent, {}, params);
  assert.equal(parentEvent.carpoolOffers[0].passengers.find(p => p.passengerUserId === parent.id).playerId, '', 'Old APK can still decode adults without a null playerId');
  const childSeat = await prisma.carpoolPassenger.findFirst({ where: { offerId: five.id, playerId: player.id } });
  await call(controller.updateCarpoolPassenger, parent, { status: 'CANCELLED' }, { ...params, offerId: five.id, passengerId: childSeat.id });
  assert.equal((await summary()).freeSeats, 3, 'Linked guardian can cancel a booking created by the other guardian');
  assert.equal((await summary()).openNeeds, 0, 'Voluntary cancellation does not re-book the same passenger');
  await assert.rejects(call(controller.requestCarpoolSeat, stranger, { includeSelf: true }, { ...params, offerId: five.id }), e => e.status === 404);
  await assert.rejects(call(controller.requestCarpoolSeat, secondParent, { playerIds: [sibling.id] }, { ...params, offerId: five.id }), e => e.status === 403);
  await assert.rejects(call(controller.requestCarpoolSeat, coach, { includeSelf: true }, { ...params, offerId: five.id }), e => e.status === 409);
  const otherEvent = await prisma.event.create({ data: { teamId: foreignTeam.id, title: 'Fremd', type: 'MATCH', location: 'Fremd', startAt: new Date('2030-09-17T10:00:00Z'), familyReleasedAt: new Date() } });
  await assert.rejects(call(controller.createCarpoolNeeds, parent, { playerIds: [player.id] }, { id: otherEvent.id }), e => e.status === 404);

  // Removing an offer restores real needs; a later offer matches the family as one group.
  await call(controller.deleteCarpoolOffer, coach, {}, { ...params, offerId: five.id });
  assert.equal((await summary()).freeSeats, 0);
  assert.equal((await summary()).openNeeds, 2);
  const small = await call(controller.createCarpoolOffer, coach, offerInput(1, 'Kleines Auto'), params);
  assert.equal((await summary()).openNeeds, 2, 'A family group is not silently split between cars');
  const large = await call(controller.createCarpoolOffer, coach, offerInput(3, 'Großes Auto'), params);
  assert.equal((await summary()).openNeeds, 0);
  assert.equal((await summary()).freeSeats, 2);
  assert.equal(await prisma.carpoolPassenger.count({ where: { offerId: large.id, status: 'CONFIRMED' } }), 2);
  await assert.rejects(call(controller.requestCarpoolSeat, parent, { includeSelf: true }, { ...params, offerId: small.id }), e => e.status === 409, 'An adult cannot occupy two cars');

  // Automatic need matching covers the same 5 -> 4 behavior without a driver confirmation.
  await call(controller.createCarpoolNeeds, parent, { playerIds: [player.id], note: 'Privater Hinweis' }, params);
  assert.equal((await summary()).freeSeats, 1);
  assert.equal((await summary()).openNeeds, 0);
  const waitingUser = await prisma.user.create({ data: { name: 'Wartende Person', email: 'ride-waiting@example.invalid', password: 'synthetic', teamId: team.id, role: 'PARENT', status: 'APPROVED' } });
  await prisma.teamMembership.create({ data: { userId: waitingUser.id, teamId: team.id, role: 'PARENT', status: 'APPROVED' } });
  const readOnly = { ...waitingUser, role: 'READ_ONLY' };
  await assert.rejects(call(controller.createCarpoolNeeds, readOnly, { includeSelf: true }, params), e => e.status === 403);
  const results = await Promise.allSettled([
    call(controller.requestCarpoolSeat, secondParent, { includeSelf: true }, { ...params, offerId: large.id }),
    call(controller.requestCarpoolSeat, waitingUser, { includeSelf: true }, { ...params, offerId: large.id }),
  ]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1, 'Two requests for the last seat produce one booking');
  assert.equal(results.filter(r => r.status === 'rejected' && r.reason.status === 409).length, 1);
  assert.equal((await summary()).freeSeats, 0);
  const notBooked = results[0].status === 'fulfilled' ? waitingUser : secondParent;
  await call(controller.createCarpoolNeeds, notBooked, { includeSelf: true, note: 'Nur für mich sichtbar' }, params);
  assert.equal((await summary()).openNeeds, 1, 'No capacity means visible unmet need');
  const viewer = results[0].status === 'fulfilled' ? secondParent : waitingUser;
  const visible = await call(events.getEvent, viewer, {}, params);
  assert.equal(visible.carpoolSummary.openNeeds, 1);
  assert.equal(visible.carpoolNeeds.find(n => n.passengerUserId === notBooked.id).note, undefined, 'Other families see need, not its private note');
  const parentDash = await call(dashboard.parentDashboardSummary, viewer);
  assert.ok(parentDash.events.every(e => e.carpoolNeeds.every(n => n.passengerUserId === viewer.id || n.note == null)), 'Dashboard hides other people’s private notes');
  const waiting = await prisma.carpoolNeed.findFirst({ where: { eventId: event.id, passengerUserId: notBooked.id } });
  await call(controller.deleteCarpoolNeed, notBooked, {}, { ...params, needId: waiting.id });
  assert.equal((await summary()).openNeeds, 0);
  // A new voluntary request may book the same car again, but a driver rejection may not.
  const retryEvent = await prisma.event.create({ data: { teamId: team.id, title: 'Stornierungen', type: 'MATCH', location: 'Test', startAt: new Date('2030-09-17T10:00:00Z') } });
  const retryParams = { id: retryEvent.id };
  const retryOffer = await call(controller.createCarpoolOffer, coach, offerInput(1), retryParams);
  await call(controller.createCarpoolNeeds, parent, { includeSelf: true }, retryParams);
  const retrySeat = await prisma.carpoolPassenger.findFirst({ where: { offerId: retryOffer.id } });
  const seatParams = { ...retryParams, offerId: retryOffer.id, passengerId: retrySeat.id };
  await call(controller.updateCarpoolPassenger, parent, { status: 'CANCELLED' }, seatParams);
  await call(controller.createCarpoolNeeds, parent, { includeSelf: true }, retryParams);
  assert.equal((await prisma.carpoolPassenger.findUnique({ where: { id: retrySeat.id } })).status, 'CONFIRMED');
  await call(controller.updateCarpoolPassenger, coach, { status: 'CANCELLED' }, seatParams);
  await call(controller.createCarpoolNeeds, parent, { includeSelf: true }, retryParams);
  assert.equal((await prisma.carpoolPassenger.findUnique({ where: { id: retrySeat.id } })).status, 'DECLINED');
  await prisma.user.update({ where: { id: coach.id }, data: { phone: '+49000000000' } });
  const declinedView = await call(events.getEvent, parent, {}, retryParams);
  assert.equal(declinedView.carpoolOffers[0].driver.phone, undefined, 'Declined passenger cannot access driver phone');
  await prisma.event.update({ where: { id: retryEvent.id }, data: { visibility: 'STAFF_ONLY' } });
  await assert.rejects(call(controller.createCarpoolNeeds, parent, { includeSelf: true }, retryParams), e => e.status === 404);
  await prisma.event.update({ where: { id: event.id }, data: { status: 'CANCELLED' } });
  await assert.rejects(call(controller.createCarpoolNeeds, parent, { playerIds: [player.id] }, params), e => e.status === 409);
  console.log('PASS direct carpool booking, adult+children, atomic last seat, auto matching, cancellations, group allocation and visibility');
};
