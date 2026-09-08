const assert = require('node:assert/strict');

module.exports = async function crossTeamMatchIntegration({ prisma, club, team, coach }) {
  const events = require('../dist/src/controllers/events.controller');
  const matches = require('../dist/src/controllers/matches.controller');
  const dashboard = require('../dist/src/controllers/dashboard.controller');
  const rides = require('../dist/src/controllers/carpool.controller');
  const { invalidateTeamAccessCache } = require('../dist/src/services/team-access');
  const call = async (fn, user, body = {}, params = {}, query = {}) => {
    let status = 200, result;
    const res = { status: value => { status = value; return res; }, set: () => res, setHeader: () => res, json: value => { result = value; return value; } };
    await fn({ user, body, params, query }, res);
    return { status, result };
  };
  const guestAge = await prisma.ageGroup.create({ data: { seasonId: (await prisma.team.findUnique({ where: { id: team.id }, include: { ageGroup: true } })).ageGroup.seasonId, name: 'D-Jugend Gasttest', code: 'D' } });
  const guestTeam = await prisma.team.create({ data: { ageGroupId: guestAge.id, name: 'D1 Gasttest' } });
  const account = name => prisma.user.create({ data: { name, email: `${name}@example.invalid`, password: 'synthetic', teamId: guestTeam.id, role: 'PARENT', status: 'APPROVED' } });
  const [parent, otherParent, playerAccount, outsider] = await Promise.all(['guest-parent', 'guest-other-parent', 'guest-player', 'guest-outsider'].map(account));
  const guest = async (name, userId) => prisma.player.create({ data: { clubId: club.id, teamId: guestTeam.id, firstName: name, lastName: 'Gast', userId } });
  const [yes, no, pending, sibling] = await Promise.all([guest('Zusage', playerAccount.id), guest('Absage'), guest('Offen'), guest('Unbeteiligt')]);
  await prisma.parentPlayerLink.createMany({ data: [parent, otherParent].flatMap(p => [yes, no, pending, sibling].map(player => ({ parentId: p.id, playerId: player.id }))) });
  const home = await prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: 'Stamm', lastName: 'Spieler' } });
  const startAt = new Date(Date.now() + 2 * 86400000);
  const match = await prisma.event.create({ data: {
    teamId: team.id, type: 'MATCH', category: 'FRIENDLY_MATCH', title: 'Jugendübergreifendes Testspiel',
    location: 'Testplatz', startAt, familyReleasedAt: new Date(),
    targetTeams: { create: { teamId: team.id } },
    matchDetails: { create: { opponent: 'Testgegner' } },
    participants: { create: [home, yes, no, pending].map(p => ({ playerId: p.id, responseRequired: true })) },
    squads: { create: { publishedAt: new Date(), members: { create: [home, yes, no, pending].map(p => ({ playerId: p.id, status: 'NOMINATED' })) } } },
    attendance: { create: [home, yes, no, pending].map(p => ({ playerId: p.id, status: p === no ? 'NO' : p === pending ? 'UNKNOWN' : 'YES', respondedAt: p === pending ? null : new Date() })) },
    liveTicker: { create: { status: 'LIVE', ourGoals: 2, theirGoals: 1 } },
  } });
  const params = { id: match.id };
  await prisma.userContextPreference.upsert({ where: { userId: coach.id }, update: { ageGroupId: (await prisma.team.findUnique({ where: { id: team.id } })).ageGroupId, activeTeamId: null, includeAllTeams: true }, create: { userId: coach.id, ageGroupId: (await prisma.team.findUnique({ where: { id: team.id } })).ageGroupId, includeAllTeams: true } });
  invalidateTeamAccessCache();
  for (const viewer of [parent, otherParent, playerAccount]) {
    const detail = await call(matches.getMatch, viewer, {}, params);
    assert.equal(detail.status, 200);
    assert.equal(detail.result.id, match.id);
    assert.equal(detail.result.capabilities.canManageTicker, false);
    assert.equal(detail.result.capabilities.canNominateSquad, false);
    const ticker = await call(matches.getTicker, viewer, {}, params);
    assert.equal(ticker.result.ourGoals, 2);
    assert.ok((await call(matches.listMatches, viewer)).result.some(e => e.id === match.id));
    assert.ok((await call(events.listEvents, viewer)).result.some(e => e.id === match.id));
    assert.ok((await call(dashboard.parentDashboardSummary, viewer)).result.events.some(e => e.id === match.id));
  }
  assert.equal((await call(matches.getMatch, outsider, {}, params)).status, 404);
  assert.equal((await call(matches.getTicker, outsider, {}, params)).status, 404);
  const serialized = (await call(events.getEvent, parent, {}, params)).result;
  assert.ok(serialized.carpoolPlayerIds.includes(yes.id));
  assert.ok(!serialized.carpoolPlayerIds.includes(home.id));
  assert.ok(!serialized.carpoolPlayerIds.includes(sibling.id));
  const offerInput = { seatsTotal: 5, departureLocation: 'Testtreffpunkt', departureAt: new Date(startAt.getTime() - 3600000).toISOString() };
  const offer = (await call(rides.createCarpoolOffer, coach, offerInput, params)).result;
  await call(rides.requestCarpoolSeat, parent, { playerIds: [yes.id], includeSelf: true }, { ...params, offerId: offer.id });
  assert.equal((await call(events.getEvent, parent, {}, params)).result.carpoolSummary.freeSeats, 3);
  await call(rides.createCarpoolNeeds, otherParent, { playerIds: [pending.id] }, params);
  assert.equal((await call(events.getEvent, parent, {}, params)).result.carpoolSummary.freeSeats, 2);
  assert.equal((await call(events.getEvent, parent, {}, params)).result.carpoolSummary.openNeeds, 0);
  await assert.rejects(call(rides.requestCarpoolSeat, parent, { playerIds: [sibling.id] }, { ...params, offerId: offer.id }), e => e.status === 404);
  const parentOffer = await call(rides.createCarpoolOffer, otherParent, { ...offerInput, seatsTotal: 1 }, params);
  assert.ok(parentOffer.result.id, 'A nominated family may offer a ride for the host team');
  const summary = (await call(dashboard.trainerDashboardSummary, coach)).result.events.find(e => e.id === match.id);
  assert.deepEqual(summary.attendanceSummary, { yes: 2, no: 1, maybe: 0, unknown: 1, goalkeeperAvailable: 0 });
  assert.ok(summary.missingAttendance.some(p => p.id === pending.id));
  assert.equal((await call(events.getEvent, coach, {}, params)).result.attendanceSummary.no, 1);
  assert.equal((await call(events.listEvents, coach)).result.find(e => e.id === match.id).attendanceSummary.yes, 2);

  // Editing a published squad must not hide existing invitations or declined guests.
  assert.equal((await call(matches.updateSquad, coach, {
    members: [home, yes, no, pending].map(player => ({ playerId: player.id, status: 'NOMINATED' })),
  }, params)).status, 200, 'An existing guest stays eligible when the coach saves the squad');
  assert.equal((await prisma.squad.findUnique({ where: { eventId: match.id } })).publishedAt, null);
  const { liveTickerNotificationAudience } = require('../dist/src/services/live-ticker-notification.service');
  const audience = await liveTickerNotificationAudience({ ...match, targetTeams: [{ teamId: team.id }] });
  assert.ok([parent, otherParent, playerAccount].every(user => audience.includes(user.id)));
  assert.ok(!audience.includes(outsider.id));
  assert.equal((await call(matches.getMatch, parent, {}, params)).status, 200);
  assert.equal((await call(dashboard.trainerDashboardSummary, coach)).result.events.find(e => e.id === match.id).attendanceSummary.no, 1);
  await call(rides.requestCarpoolSeat, otherParent, { playerIds: [no.id] }, { ...params, offerId: offer.id });

  // A new draft does not grant access; the sent late invitation does.
  const late = await prisma.event.create({ data: {
    teamId: team.id, type: 'MATCH', title: 'Nachnominierung', location: 'Testplatz', startAt: new Date(startAt.getTime() + 86400000),
    familyReleasedAt: new Date(), squads: { create: { members: { create: { playerId: yes.id, status: 'NOMINATED' } } } },
  } });
  const lateParams = { id: late.id };
  assert.equal((await call(matches.getMatch, parent, {}, lateParams)).status, 404);
  await prisma.eventParticipant.create({ data: { eventId: late.id, playerId: yes.id, responseRequired: true } });
  assert.equal((await call(matches.getMatch, parent, {}, lateParams)).status, 200);
  assert.equal((await call(events.setAttendance, parent, { playerId: yes.id, status: 'YES' }, lateParams)).status, 200);
  assert.equal((await prisma.attendance.findUnique({ where: { eventId_playerId: { eventId: late.id, playerId: yes.id } } })).status, 'YES');
  await prisma.event.update({ where: { id: late.id }, data: { responseRevisionAt: new Date(Date.now() + 1000) } });
  const revised = (await call(dashboard.trainerDashboardSummary, coach)).result.events.find(e => e.id === late.id);
  assert.equal(revised.attendanceSummary.yes, 0);
  assert.equal(revised.attendanceSummary.unknown, 1);
  await prisma.event.update({ where: { id: late.id }, data: { visibility: 'STAFF_ONLY' } });
  assert.equal((await call(matches.getMatch, parent, {}, lateParams)).status, 404);
  assert.equal((await call(matches.getTicker, playerAccount, {}, lateParams)).status, 404);
  await assert.rejects(call(rides.createCarpoolOffer, { ...parent, role: 'COACH' }, offerInput, lateParams), e => e.status === 404);
  await prisma.event.update({ where: { id: late.id }, data: { visibility: 'TEAM' } });
  await prisma.eventParticipant.update({ where: { eventId_playerId: { eventId: late.id, playerId: yes.id } }, data: { responseRequired: false } });
  assert.equal((await call(matches.getMatch, parent, {}, lateParams)).status, 404);
  await assert.rejects(call(rides.createCarpoolOffer, parent, offerInput, lateParams), e => e.status === 404);
  const removed = (await call(dashboard.trainerDashboardSummary, coach)).result.events.find(e => e.id === late.id);
  assert.equal(removed.attendance.some(a => a.playerId === yes.id), false);
  console.log('PASS cross-youth invitations, both guardians + player, match/list/calendar/dashboard/ticker access, guest rides, auto allocation, complete response totals, draft continuity, late invitation and revocation');
};
