const assert = require('node:assert/strict');

module.exports = async ({ prisma, club, team, coach, parent }) => {
  const events = require('../dist/src/controllers/events.controller');
  const call = async (user, event, player, extra = {}) => {
    let status = 200, result;
    const res = { status: n => { status = n; return res; }, json: v => { result = v; return res; } };
    try {
      await events.setAttendance({ user, params: { id: event.id }, query: {},
        body: { playerId: player.id, status: 'YES', ...extra } }, res);
    } catch (error) {
      if (!error.status) throw error;
      status = error.status; result = { message: error.message };
    }
    return { status, result };
  };
  const siblingTeam = await prisma.team.findFirstOrThrow({ where: { ageGroupId: team.ageGroupId, teamNumber: 2 } });
  await prisma.teamMembership.upsert({ where: { userId_teamId: { userId: coach.id, teamId: siblingTeam.id } },
    create: { userId: coach.id, teamId: siblingTeam.id, role: 'COACH', status: 'APPROVED' }, update: { role: 'COACH', status: 'APPROVED' } });
  require('../dist/src/services/team-access').invalidateTeamAccessCache();
  const createPlayer = name => prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: name, lastName: 'Einladungstest' } });
  const child = await createPlayer('Trainerkind');
  const otherChild = await createPlayer('Weiteres Kind');
  const invited = await createPlayer('Bereits eingeladen');
  await prisma.parentPlayerLink.createMany({ data: [coach, parent].map(user => ({ parentId: user.id, playerId: child.id })) });
  const make = (title, extra = {}) => prisma.event.create({ data: {
    teamId: siblingTeam.id, title, type: 'MATCH', location: 'Testplatz',
    startAt: new Date('2034-05-14T08:00Z'), familyReleasedAt: new Date(),
    participants: { create: { playerId: invited.id, responseRequired: true } }, ...extra,
  } });
  const first = await make('E2 Spiel mit vorhandener Einladungsliste');
  const second = await make('E1 Turnier', { teamId: team.id, startAt: new Date('2034-05-14T12:30Z'),
    participants: { create: { playerId: child.id, responseRequired: true } } });
  await prisma.attendance.createMany({ data: [
    { eventId: first.id, playerId: child.id, status: 'NO', responseSource: 'SYSTEM_ADMINISTRATION', reason: 'Automatisch abgesagt: anderes Spiel' },
    { eventId: second.id, playerId: child.id, status: 'YES', responseSource: 'GUARDIAN', respondedById: coach.id },
  ] });
  const squad = await prisma.squad.create({ data: { eventId: second.id,
    members: { create: { playerId: child.id, status: 'NOMINATED' } },
    lineup: { create: { formation: '2-3-1', positions: { create: { playerId: child.id, positionCode: 'TW', x: .5, y: .9 } } } },
  } });
  const invitation = player => prisma.eventParticipant.findUnique({ where: { eventId_playerId: { eventId: first.id, playerId: player.id } } });
  assert.ok([403, 404].includes((await call(parent, first, child)).status), 'Family cannot add an uninvited child');
  assert.equal((await call(coach, first, child, { responseMode: 'PERSONAL_GUARDIAN' })).status, 403, 'Personal mode must not inherit trainer rights');
  assert.equal((await call(coach, first, child, { sameDayMatchId: 'missing-match' })).status, 403, 'Missing second match is rejected');
  assert.equal(await invitation(child), null, 'Failed approval must not change the invitation');
  const approved = await call(coach, first, child, { sameDayMatchId: second.id });
  assert.equal(approved.status, 200, approved.result?.message);
  assert.equal((await invitation(child)).responseRequired, true, 'Trainer correction adds the eligible child to the match invitation');
  assert.equal(approved.result.event.attendance.find(a => a.playerId === child.id).status, 'YES', 'Returned calendar snapshot includes the acceptance');
  assert.equal(await prisma.attendance.count({ where: { playerId: child.id, eventId: { in: [first.id, second.id] }, status: 'YES' } }), 2);
  assert.equal(await prisma.lineupPosition.count({ where: { lineup: { squadId: squad.id }, playerId: child.id } }), 1);
  assert.equal(await prisma.squadMember.count({ where: { squadId: squad.id, playerId: child.id } }), 1);
  assert.equal((await call(parent, first, child, { responseMode: 'PERSONAL_GUARDIAN' })).status, 200, 'Subsequent family responses use the saved invitation');
  assert.equal(await prisma.attendance.count({ where: { playerId: child.id, eventId: { in: [first.id, second.id] }, status: 'YES' } }), 2);
  assert.equal((await call(coach, first, otherChild)).status, 200, 'Same correction works for a child not linked to the trainer');
  assert.equal((await invitation(otherChild)).responseRequired, true);
  assert.equal(await prisma.sameDayMatchApproval.count({ where: { playerId: child.id } }), 1);
  await prisma.eventParticipant.update({ where: { eventId_playerId: { eventId: first.id, playerId: otherChild.id } }, data: { responseRequired: false } });
  assert.equal((await call(coach, first, otherChild)).status, 403, 'Explicit removal stays protected');
  assert.equal((await invitation(otherChild)).responseRequired, false);
  const training = await make('Training mit begrenztem Teilnehmerkreis', { type: 'TRAINING' });
  assert.equal((await call(coach, training, child)).status, 403, 'Do not expand training invitations');
  const foreignAge = await prisma.ageGroup.create({ data: { seasonId: (await prisma.ageGroup.findUnique({ where: { id: team.ageGroupId } })).seasonId, name: 'Fremde Jugend Einladungstest', code: 'B' } });
  const foreignTeam = await prisma.team.create({ data: { ageGroupId: foreignAge.id, name: 'B1 Einladungstest' } });
  const outsider = await prisma.player.create({ data: { clubId: club.id, teamId: foreignTeam.id, firstName: 'Fremd', lastName: 'Test' } });
  assert.equal((await call(coach, first, outsider)).status, 404, 'Uninvited players outside the eligible youth pool remain forbidden');
  assert.equal(await invitation(outsider), null);
  console.log('PASS trainer response: own child + other child, partial E2 invitation, protected double acceptance + lineup, family follow-up, explicit removal and eligibility boundaries');
};
