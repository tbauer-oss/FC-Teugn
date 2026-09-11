const assert = require('node:assert/strict');

module.exports = async ({ prisma, club, team, coach, parent }) => {
  const events = require('../dist/src/controllers/events.controller');
  const { acceptAttendanceExclusivelyForDay } = require('../dist/src/services/daily-attendance-conflict.service');
  const call = async (fn, user, id, playerId, body = {}) => {
    let status = 200, result;
    const res = { status: n => { status = n; return res; }, json: v => { result = v; return res; } };
    try { await fn({ user, body: { playerId, ...body }, params: { id, playerId }, query: {} }, res); }
    catch (error) { if (!error.status) throw error; status = error.status; result = { message: error.message }; }
    return { status, result };
  };
  const player = await prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: 'Doppelspiel', lastName: 'Test' } });
  const unapprovedPlayer = await prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: 'Ohne Freigabe', lastName: 'Test' } });
  await prisma.parentPlayerLink.create({ data: { parentId: parent.id, playerId: player.id } });
  const make = (title, extra = {}) => prisma.event.create({ data: {
    teamId: team.id, title, type: 'MATCH', location: 'Test', startAt: new Date('2033-05-14T10:00Z'),
    ...extra,
  } });
  const first = await make('Erstes Spiel');
  const second = await make('Zweites Spiel', { startAt: new Date('2033-05-14T14:00Z') });
  const third = await make('Drittes Spiel');
  const training = await make('Training', { type: 'TRAINING' });
  const otherDay = await make('Anderer Tag', { startAt: new Date('2033-05-15T10:00Z') });
  const child = await make('Turnierpartie', { parentTournamentId: first.id });
  const yes = (id, extra = {}, user = coach, childId = player.id) => call(events.setAttendance, user, id, childId, { status: 'YES', ...extra });
  const status = async (eventId, playerId = player.id) => (await prisma.attendance.findUnique({ where: { eventId_playerId: { eventId, playerId } } }))?.status;
  assert.equal((await yes(first.id)).status, 200);
  assert.equal((await yes(second.id)).status, 200);
  assert.equal(await status(first.id), 'NO', 'Default remains last acceptance wins');
  assert.equal((await call(events.sameDayMatchOptions, parent, first.id, player.id)).status, 403);
  const options = await call(events.sameDayMatchOptions, coach, first.id, player.id);
  assert.deepEqual(options.result.map(o => o.id), [second.id]);
  assert.equal((await yes(first.id, { sameDayMatchId: second.id }, parent)).status, 403);
  assert.equal((await yes(first.id, { sameDayMatchId: second.id, responseMode: 'PERSONAL_GUARDIAN' }, coach)).status, 403);
  assert.equal((await yes(first.id, { sameDayMatchId: first.id })).status, 400);
  assert.equal((await yes(first.id, { sameDayMatchId: otherDay.id })).status, 400);
  assert.equal((await yes(first.id, { sameDayMatchId: training.id })).status, 400);
  assert.equal((await yes(child.id, { sameDayMatchId: second.id })).status, 409);
  assert.equal((await yes(first.id, { sameDayMatchId: child.id })).status, 400);
  assert.equal((await yes(first.id, { sameDayMatchId: third.id })).status, 409, 'Second match must actually have an acceptance');
  assert.equal(await prisma.sameDayMatchApproval.count({ where: { playerId: player.id } }), 0);

  // Existing roster/lineup in the protected match must not be deleted.
  const squad = await prisma.squad.create({ data: { eventId: second.id,
    members: { create: { playerId: player.id } },
    lineup: { create: { formation: '2-3-1', positions: { create: { playerId: player.id, positionCode: 'ST', x: .5, y: .2 } } } },
  } });
  assert.equal((await yes(first.id, { sameDayMatchId: second.id })).status, 200);
  assert.equal(await status(first.id), 'YES');
  assert.equal(await status(second.id), 'YES');
  assert.equal(await prisma.squadMember.count({ where: { squadId: squad.id, playerId: player.id } }), 1);
  assert.equal(await prisma.lineupPosition.count({ where: { lineup: { squadId: squad.id }, playerId: player.id } }), 1);
  assert.equal((await call(events.sameDayMatchOptions, coach, first.id, player.id)).result[0].approved, true);
  assert.equal(await prisma.auditLog.count({ where: { action: 'SAME_DAY_MATCH_APPROVED' } }), 1);
  assert.equal((await yes(second.id, { sameDayMatchId: first.id })).status, 200);
  assert.equal(await prisma.sameDayMatchApproval.count({ where: { playerId: player.id } }), 1, 'Reverse direction/retry is one canonical approval');
  await yes(first.id, {}, parent);
  await yes(second.id, {}, parent);
  assert.equal(await status(first.id), 'YES', 'Parent refresh/correction honours staff exception');
  assert.equal(await status(second.id), 'YES');

  await yes(first.id, {}, coach, unapprovedPlayer.id);
  await yes(second.id, {}, coach, unapprovedPlayer.id);
  assert.equal(await status(first.id, unapprovedPlayer.id), 'NO', 'Not a team-wide exemption');
  // An older automatic reconciliation must ignore the approved newer match.
  const result = await prisma.$transaction(tx => acceptAttendanceExclusivelyForDay(tx, {
    event: first, playerId: player.id, actorId: coach.id, respondedAt: new Date('2026-01-01'),
    responseSource: 'TRAINER_CORRECTION', honorLaterExistingAcceptance: true,
  }));
  assert.equal(result.accepted, true);
  await call(events.setAttendance, parent, first.id, player.id, { status: 'NO', reason: 'Bewusst abgesagt' });
  assert.equal(await status(first.id), 'NO', 'Explicit declines still work');
  assert.equal(await status(second.id), 'YES');
  await yes(first.id);
  await yes(third.id);
  assert.equal(await status(first.id), 'NO', 'No blanket permission for a third match');
  assert.equal(await status(second.id), 'NO');
  await call(events.setAttendance, coach, third.id, player.id, { status: 'NO' });
  await yes(second.id);
  await yes(first.id);
  assert.equal(await status(second.id), 'YES', 'Approval survives future attendance changes');
  // Moving both matches to another day must not carry the old approval forward.
  await prisma.event.updateMany({ where: { id: { in: [first.id, second.id] } }, data: { startAt: new Date('2033-05-16T10:00Z') } });
  await yes(first.id);
  assert.equal(await status(second.id), 'NO', 'Approval is tied to the confirmed Berlin date');

  const foreignAge = await prisma.ageGroup.create({ data: { seasonId: (await prisma.ageGroup.findUnique({ where: { id: team.ageGroupId } })).seasonId, name: 'Fremde Jugend', code: 'A' } });
  const foreignTeam = await prisma.team.create({ data: { ageGroupId: foreignAge.id, name: 'Fremd A1' } });
  const foreign = await make('Fremdes Spiel', { teamId: foreignTeam.id, startAt: new Date('2033-05-16T12:00Z') });
  await prisma.attendance.create({ data: { eventId: foreign.id, playerId: player.id, status: 'YES' } });
  assert.equal((await yes(first.id, { sameDayMatchId: foreign.id })).status, 403, 'Rights to both matches required');
  assert.ok(!(await call(events.sameDayMatchOptions, coach, first.id, player.id)).result.some(o => o.id === foreign.id));
  await prisma.event.delete({ where: { id: first.id } });
  assert.equal(await prisma.sameDayMatchApproval.count({ where: { playerId: player.id } }), 0, 'Deletion cascades without orphan approvals');
  const early = await make('Nach Mitternacht', { startAt: new Date('2033-05-17T22:30Z') });
  const late = await make('Später am selben Berliner Tag', { startAt: new Date('2033-05-18T21:30Z') });
  await yes(early.id);
  assert.equal((await yes(late.id, { sameDayMatchId: early.id })).status, 200, 'Different UTC dates may belong to the same Berlin calendar day');
  assert.equal(await status(early.id), 'YES');
  assert.equal(await status(late.id), 'YES');
  assert.equal((await prisma.sameDayMatchApproval.findFirst({ where: { playerId: player.id } })).day, '2033-05-18');
  const cancelled = await make('Abgesagt', { startAt: late.startAt, status: 'CANCELLED' });
  assert.equal((await yes(late.id, { sameDayMatchId: cancelled.id })).status, 400);
  console.log('PASS same-day approval: default conflicts, trainer-only, pair/day/player scope, preserved lineup, retries, parents, explicit decline, rescheduling and deletion');
};
