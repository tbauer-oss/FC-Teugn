const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

module.exports = async ({ prisma, club, team, coach, parent }) => {
  const events = require('../dist/src/controllers/events.controller');
  const matches = require('../dist/src/controllers/matches.controller');
  const { processEventChanges } = require('../dist/src/services/event-change.service');
  const { acceptAttendanceExclusivelyForDay } = require('../dist/src/services/daily-attendance-conflict.service');
  const { reconcilePlayerAbsences } = require('../dist/src/services/absence.service');
  const call = async (fn, user, id, body = {}, query = {}) => {
    let status = 200, result;
    const res = { status: n => { status = n; return res; }, json: v => { result = v; return res; } };
    const key = randomUUID();
    try { await fn({ user, params: { id }, body, query, get: () => key, header: () => key }, res); }
    catch (error) { if (!error.status) throw error; status = error.status; result = { message: error.message }; }
    return { status, result };
  };
  const start = new Date(Date.now() + 7 * 86400000);
  const deadline = new Date(start.getTime() - 48 * 3600000);
  const child = await prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: 'Frist', lastName: 'Test' } });
  await prisma.parentPlayerLink.createMany({ data: [coach, parent].map(p => ({ parentId: p.id, playerId: child.id })) });
  const created = await call(events.createEvent, coach, undefined, {
    type: 'MATCH', category: 'FRIENDLY_MATCH', title: 'Frist Testspiel', startAt: start.toISOString(),
    location: 'Testplatz', homeAway: 'HOME', opponent: 'Testgegner', teamIds: [team.id],
    responseDeadline: deadline.toISOString(), participantPlayerIds: [child.id],
  });
  assert.equal(created.status, 201, JSON.stringify(created.result));
  const id = created.result.id;
  assert.ok(id);
  const match = await prisma.event.findUniqueOrThrow({ where: { id } });
  assert.equal(match.responseDeadline.toISOString(), deadline.toISOString());
  const released = await call(matches.releaseMatchToFamilies, coach, id, { audienceMode: 'FULL_TEAM' });
  assert.equal(released.status, 200, released.result?.message);
  assert.match(released.result.message, /Kader schließt am/);
  assert.match(released.result.message, /nur noch durch das Trainerteam/);
  const answer = (user, status, extra = {}) => call(events.setAttendance, user, id, { playerId: child.id, status, ...extra });
  assert.equal((await answer(parent, 'YES', { responseMode: 'PERSONAL_GUARDIAN' })).status, 200);
  assert.equal((await answer(parent, 'NO')).status, 200);
  assert.equal((await answer(parent, 'YES')).status, 200);
  const invalid = await call(events.updateEvent, coach, id, { responseDeadline: 'ungültig' });
  assert.equal(invalid.status, 400);
  assert.equal((await call(events.updateEvent, coach, id, { responseDeadline: start.toISOString() })).status, 400);
  const closed = new Date(Date.now() - 1000);
  assert.equal((await call(events.updateEvent, coach, id, { responseDeadline: closed.toISOString() })).status, 200);
  const before = await prisma.attendance.findUniqueOrThrow({ where: { eventId_playerId: { eventId: id, playerId: child.id } } });
  for (const status of ['YES', 'NO', 'UNKNOWN']) {
    const reply = await answer(parent, status);
    assert.equal(reply.status, 409);
    assert.match(reply.result.message, /Kader geschlossen/);
  }
  assert.equal((await answer(coach, 'NO', { responseMode: 'PERSONAL_GUARDIAN' })).status, 409, 'Trainer acting as parent cannot bypass cutoff');
  const unchanged = await prisma.attendance.findUniqueOrThrow({ where: { id: before.id } });
  assert.equal(unchanged.status, 'YES');
  assert.equal(unchanged.updatedAt.toISOString(), before.updatedAt.toISOString());
  const personal = await call(events.listPersonalResponses, parent, undefined);
  assert.equal(personal.result.find(x => x.eventId === id && x.playerId === child.id)?.canRespond, false);
  const info = await call(events.getEvent, parent, id);
  assert.equal(info.result.capabilities.canRespond, false);
  const other = await prisma.event.create({ data: { teamId: team.id, title: 'Anderer Termin', type: 'TRAINING',
    location: 'Test', startAt: start, participants: { create: { playerId: child.id } } } });
  assert.equal((await call(events.setAttendance, parent, other.id, { playerId: child.id, status: 'YES' })).status, 409,
    'Day automation must not remove a closed match acceptance');
  const replay = await prisma.$transaction(tx => acceptAttendanceExclusivelyForDay(tx, {
    event: other, playerId: child.id, actorId: parent.id, responseSource: 'GUARDIAN',
    respondedAt: new Date(), honorLaterExistingAcceptance: true,
  }));
  assert.equal(replay.accepted, false, 'Passive series reconciliation must not fail calendar reads or replace closed matches');
  assert.equal((await prisma.attendance.findUniqueOrThrow({ where: { id: before.id } })).status, 'YES');
  const day = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Berlin' }).format(start);
  const absence = await prisma.playerAbsence.create({ data: { playerId: child.id, createdById: parent.id,
    startsOn: day, endsOn: day, eventTypes: ['MATCH'], weekdays: [], teamIds: [], reason: 'Test' } });
  await prisma.$transaction(tx => reconcilePlayerAbsences(tx, [child.id]));
  assert.equal((await prisma.attendance.findUniqueOrThrow({ where: { id: before.id } })).status, 'YES',
    'Absence automation must preserve the closed roster');
  await prisma.playerAbsence.delete({ where: { id: absence.id } });
  assert.equal((await answer(coach, 'NO')).status, 200, 'Trainer may correct after cutoff');
  assert.equal((await answer(coach, 'YES')).status, 200);
  await processEventChanges(100);
  const changes = await prisma.notification.findMany({ where: { userId: parent.id, entityId: id, title: { startsWith: 'Termin geändert' } } });
  assert.ok(changes.some(n => n.body.includes('Kader geschlossen')), 'Already informed family receives updated deadline');
  assert.equal((await call(events.upsertMatchDetails, coach, id, { opponent: 'Testgegner', isHome: true,
    periodCount: 2, periodMinutes: 20, responseDeadline: null })).status, 200);
  assert.equal((await prisma.event.findUniqueOrThrow({ where: { id } })).responseDeadline, null);
  assert.equal((await answer(parent, 'NO')).status, 200, 'Removing deadline reopens family responses');
  assert.equal((await call(events.updateEvent, coach, id, { responseDeadline: deadline.toISOString() })).status, 200);
  const movedStart = new Date(start.getTime() + 86400000);
  assert.equal((await call(events.updateEvent, coach, id, { startAt: movedStart.toISOString() })).status, 200);
  assert.equal((await prisma.event.findUniqueOrThrow({ where: { id } })).responseDeadline.getTime(), movedStart.getTime() - 48 * 3600000);
  console.log('PASS response deadlines: create + edit + clear, family messages, all replies locked, personal trainer mode, trainer correction, daily conflict protection, preserved lead time');
};
