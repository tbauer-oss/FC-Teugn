const assert = require('node:assert/strict');

module.exports = async ({ prisma, club, team, coach, parent, stranger }) => {
  const matches = require('../dist/src/controllers/matches.controller');
  const events = require('../dist/src/controllers/events.controller');
  const call = async (fn, user, body = {}, id) => {
    let status = 200, result;
    const res = { status: n => { status = n; return res; }, json: v => { result = v; return res; }, setHeader: () => res, set: () => res };
    await fn({ user, body, params: { id }, query: {} }, res);
    return { status, result };
  };
  const children = await Promise.all(['Eigene', 'Andere', 'Abgesagte'].map(firstName => prisma.player.create({
    data: { clubId: club.id, teamId: team.id, firstName, lastName: 'Turniertest' },
  })));
  await prisma.parentPlayerLink.create({ data: { parentId: parent.id, playerId: children[0].id } });
  const tournament = await prisma.event.create({ data: {
    teamId: team.id, title: 'Turnierkader-Test', type: 'MATCH', category: 'TOURNAMENT',
    location: 'Testplatz', startAt: new Date('2032-06-01T09:00Z'), endAt: new Date('2032-06-01T14:00Z'),
    squads: { create: { publishedAt: new Date(), members: { create: children.map(player => ({ playerId: player.id, note: 'Trainerintern' })) },
      lineup: { create: { formation: '2-3-1', tacticalNote: 'Nicht für Eltern', positions: { create: children.slice(0, 2).map((player, index) => ({ playerId: player.id, positionCode: 'ST', x: .3 + index * .3, y: .2 })) } } },
    } },
    attendance: { create: children.map((player, index) => ({ playerId: player.id, status: index === 2 ? 'NO' : 'YES', reason: 'Privater Grund' })) },
  } });
  const createFixture = () => prisma.event.create({ data: {
    teamId: team.id, title: 'Turnierpartie', type: 'MATCH', category: 'TOURNAMENT', parentTournamentId: tournament.id,
    location: 'Testplatz', startAt: new Date('2032-06-01T10:00Z'),
    matchDetails: { create: { opponent: 'Testgegner', periodCount: 1, periodMinutes: 10 } },
  } });
  const first = await createFixture();
  const second = await createFixture();
  const notificationsBefore = await prisma.notification.count();
  const hidden = await call(matches.getMatch, parent, {}, tournament.id);
  assert.equal(hidden.result.squads[0]?.lineup, null, 'Unreleased lineup remains private');
  await prisma.event.update({ where: { id: tournament.id }, data: { familyReleasedAt: new Date(), familyReleaseAudience: 'NOMINATED_SQUAD' } });
  const family = await call(matches.getMatch, parent, {}, tournament.id);
  assert.equal(family.result.squads[0].members.length, 2, 'All nominated, non-declined children visible, not only own child');
  assert.equal(family.result.squads[0].lineup.positions.length, 2, 'Complete tournament lineup is visible without child releases');
  assert.equal(family.result.squads[0].lineup.tacticalNote, null);
  assert.equal(family.result.squads[0].members[1].note, null);
  assert.equal(family.result.squads[0].members[1].lineupEligible, true);
  assert.equal(family.result.attendance.length, 1, 'Other children’s private attendance is not exposed');
  assert.equal(family.result.playerRatings, undefined);
  const card = await call(events.getEvent, parent, {}, tournament.id);
  assert.equal(card.result.tournamentFixtures.length, 2, 'Both child games visible through parent release');
  const fixture = await call(matches.getMatch, parent, {}, first.id);
  assert.equal(fixture.status, 200);
  assert.ok(fixture.result.familyReleasedAt);
  assert.equal(fixture.result.squads[0].members.length, 2);
  assert.equal(fixture.result.squads[0].lineup.positions.length, 2);
  assert.equal(fixture.result.capabilities.canReleaseFamily, false);
  const persisted = await prisma.event.findUnique({ where: { id: first.id } });
  assert.equal(persisted.familyReleasedAt, null, 'No separate fixture publication needed');
  const stamp = (await prisma.squad.findUnique({ where: { eventId: first.id } })).updatedAt;
  await call(matches.getMatch, coach, {}, first.id);
  assert.deepEqual((await prisma.squad.findUnique({ where: { eventId: first.id } })).updatedAt, stamp, 'Repeat opens do not rewrite unchanged squad');
  assert.equal(await prisma.notification.count(), notificationsBefore, 'Opening/copying never sends nominations or pushes');
  assert.equal((await call(matches.getMatch, stranger, {}, first.id)).status, 404, 'Unrelated families cannot read it');
  assert.equal((await call(matches.publishSquad, coach, {}, first.id)).status, 409, 'No second nomination at fixture level');
  const override = await call(matches.updateSquad, coach, { members: [{ playerId: children[0].id, status: 'NOMINATED' }] }, first.id);
  assert.equal(override.status, 200, JSON.stringify(override.result));
  assert.ok(override.result.publishedAt, 'Fixture adjustment retains tournament nomination');
  await call(matches.getMatch, coach, {}, first.id);
  assert.equal(await prisma.squadMember.count({ where: { squad: { eventId: first.id } } }), 1, 'Manual game squad remains independent');
  await call(matches.getMatch, coach, {}, second.id);
  await prisma.matchDetails.update({ where: { eventId: second.id }, data: { status: 'LIVE' } });
  await prisma.squadMember.deleteMany({ where: { squad: { eventId: tournament.id }, playerId: children[1].id } });
  await call(matches.getMatch, coach, {}, second.id);
  assert.equal(await prisma.squadMember.count({ where: { squad: { eventId: second.id } } }), 2, 'Running game squad is not overwritten');
  const later = await createFixture();
  assert.equal((await call(matches.getMatch, parent, {}, later.id)).result.squads[0].members.length, 1, 'New fixtures inherit latest tournament squad and release');
  console.log('PASS tournament defaults, manual overrides, live freeze, all-child family lineup, inherited release, privacy, no duplicate notifications');
};
