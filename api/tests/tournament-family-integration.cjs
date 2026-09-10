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
  assert.equal(override.status, 409, 'Roster is managed only on the master');
  // Reproduce the old detached one-player squad with a stale child answer.
  const childSquad = await prisma.squad.update({ where: { eventId: first.id }, data: { inheritsTournamentSquad: false } });
  await prisma.squadMember.deleteMany({ where: { squadId: childSquad.id, playerId: children[1].id } });
  await prisma.attendance.update({ where: { eventId_playerId: { eventId: first.id, playerId: children[1].id } },
    data: { status: 'NO', respondedById: coach.id, respondedAt: new Date(), reason: 'Alter Einzelspielstand' } });
  const correctionTime = new Date();
  await prisma.attendance.updateMany({ where: { eventId: tournament.id, playerId: children[1].id },
    data: { respondedById: coach.id, respondedAt: correctionTime, responseSource: 'TRAINER_CORRECTION' } });
  await call(matches.getMatch, coach, {}, first.id);
  assert.equal(await prisma.squadMember.count({ where: { squad: { eventId: first.id } } }), 2, 'Legacy detached roster repaired from master');
  const corrected = await prisma.attendance.findUnique({ where: { eventId_playerId: { eventId: first.id, playerId: children[1].id } } });
  assert.equal(corrected.status, 'YES');
  assert.equal(corrected.respondedById, coach.id);
  assert.deepEqual(corrected.respondedAt, correctionTime);
  assert.equal((await call(events.setAttendance, coach, { playerId: children[1].id, status: 'NO' }, first.id)).status, 409,
    'Cannot create independent fixture replies');
  await call(matches.getMatch, coach, {}, second.id);
  await prisma.matchDetails.update({ where: { eventId: second.id }, data: { status: 'LIVE' } });
  await prisma.squadMember.deleteMany({ where: { squad: { eventId: tournament.id }, playerId: children[1].id } });
  await call(matches.getMatch, coach, {}, second.id);
  assert.equal(await prisma.squadMember.count({ where: { squad: { eventId: second.id } } }), 2, 'Running game squad is not overwritten');
  const later = await createFixture();
  assert.equal((await call(matches.getMatch, parent, {}, later.id)).result.squads[0].members.length, 1, 'New fixtures inherit latest tournament squad and release');
  // A new master acceptance must never auto-decline its own child fixtures.
  await call(events.setAttendance, coach, { playerId: children[0].id, status: 'YES' }, tournament.id);
  assert.equal((await prisma.attendance.findUnique({ where: { eventId_playerId: { eventId: first.id, playerId: children[0].id } } })).status, 'YES');
  const oldMasterCount = await prisma.squadMember.count({ where: { squad: { eventId: tournament.id } } });
  const allIds = [first.id, second.id, later.id];
  const opponentClub = await prisma.opponentClub.create({ data: { organizationClubId: club.id,
    name: 'Turniertest Gast', normalizedName: 'turniertest-gast', createdById: coach.id } });
  const opponent = await prisma.opponent.create({ data: { ageGroupId: team.ageGroupId,
    opponentClubId: opponentClub.id, clubName: opponentClub.name, teamDesignation: 'E1',
    normalizedKey: 'turniertest-gast-e1', createdById: coach.id } });
  const remainingInputs = [second.id, later.id].map(id => ({id, opponentId:opponent.id,
    startAt:'2032-06-01T10:00:00.000Z', periodCount:1, periodMinutes:10, isHome:true}));
  const individuallyDeleted = await call(matches.syncTournamentFixtures, coach,
    {fixtures:remainingInputs, removedFixtureIds:[first.id]}, tournament.id);
  assert.equal(individuallyDeleted.status,200, JSON.stringify(individuallyDeleted.result));
  assert.equal(await prisma.event.count({where:{parentTournamentId:tournament.id}}),2);
  assert.equal(await prisma.squad.count({where:{eventId:first.id}}),0,'Child lineup and squad cascade');
  // Stale clients may not accidentally delete an unconfirmed newer fixture.
  const unconfirmed = await createFixture();
  assert.equal((await call(matches.syncTournamentFixtures, coach,
    {fixtures:[],removedFixtureIds:[second.id,later.id]}, tournament.id)).status,409);
  assert.equal((await call(matches.syncTournamentFixtures, coach, { fixtures: [] }, tournament.id)).status, 409,
    'Deletion requires exact confirmed targets');
  assert.equal(await prisma.event.count({ where: { parentTournamentId: tournament.id } }), 3);
  const deleted = await call(matches.syncTournamentFixtures, coach,
    { fixtures: [], removedFixtureIds: [second.id, later.id, unconfirmed.id] }, tournament.id);
  assert.equal(deleted.status, 200, JSON.stringify(deleted.result));
  assert.equal(await prisma.event.count({ where: { parentTournamentId: tournament.id } }), 0);
  assert.equal(await prisma.squadMember.count({ where: { squad: { eventId: tournament.id } } }), oldMasterCount);
  assert.equal(await prisma.auditLog.count({ where: { entityId: { in: allIds }, action: 'MATCH_DELETED' } }), 3);
  console.log('PASS master roster/replies, trainer correction, legacy repair, live freeze, family privacy, confirmed bulk delete, no duplicate invitations');
};
