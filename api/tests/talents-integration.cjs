const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

async function main() {
  const { PGlite } = require('../test-support/node_modules/@electric-sql/pglite');
  const { PGLiteSocketServer } = require('../test-support/node_modules/@electric-sql/pglite-socket');
  const db = await PGlite.create();
  const server = new PGLiteSocketServer({ db, port: 55439, host: '127.0.0.1', maxConnections: 4 });
  let prisma;
  try {
    const migrations = path.join(__dirname, '../prisma/migrations');
    const dirs = fs.readdirSync(migrations).filter(d => fs.existsSync(path.join(migrations, d, 'migration.sql'))).sort();
    const newMigration = '20260907120000_talents_family_development';
    for (const dir of dirs.filter(d => d < newMigration)) {
      try { await db.exec(fs.readFileSync(path.join(migrations, dir, 'migration.sql'), 'utf8')); }
      catch (error) { throw new Error(`Migration ${dir}: ${error.message}`); }
    }
    await server.start();
    process.env.DATABASE_URL = 'postgresql://postgres:postgres@127.0.0.1:55439/postgres?connection_limit=1';
    process.env.APP_ENVIRONMENT = 'test';
    process.env.NODE_ENV = 'test';
    ({ prisma } = require('../dist/src/lib/prisma'));
    const club = await prisma.club.create({ data: { name: 'Testverein', shortName: 'TEST' } });
    const season = await prisma.season.create({ data: { clubId: club.id, name: 'Test 2030', startDate: new Date('2030-01-01'), endDate: new Date('2030-12-31') } });
    const age = await prisma.ageGroup.create({ data: { seasonId: season.id, name: 'E-Jugend', code: 'E' } });
    const team = await prisma.team.create({ data: { ageGroupId: age.id, name: 'E1 Test' } });
    const foreignTeam = await prisma.team.create({ data: { ageGroupId: age.id, name: 'E2 Test', teamNumber: 2 } });
    const user = async (name, role = 'PARENT', teamId = team.id) => prisma.user.create({ data: { name, email: `${name}@example.invalid`, password: 'not-a-real-password', teamId, role, status: 'APPROVED' } });
    const coach = await user('coach', 'COACH');
    const parent = await user('parent');
    const secondParent = await user('secondParent');
    const stranger = await user('stranger', 'PARENT', foreignTeam.id);
    const player = await prisma.player.create({ data: { clubId: club.id, teamId: team.id, firstName: 'Kind', lastName: 'Test' } });
    await prisma.parentPlayerLink.createMany({ data: [parent, secondParent].map(p => ({ parentId: p.id, playerId: player.id })) });
    await prisma.teamMembership.createMany({ data: [coach, parent, secondParent].map(p => ({ userId: p.id, teamId: team.id, status: 'APPROVED', role: p.role })) });
    const event = await prisma.event.create({ data: { teamId: team.id, title: 'Testspiel', type: 'MATCH', location: 'Teugn', startAt: new Date('2030-09-14T10:00:00Z'), familyReleasedAt: new Date() }, select: { id: true } });
    await prisma.attendance.create({ data: { eventId: event.id, playerId: player.id, status: 'YES', reason: 'Ursprüngliche Zusage', respondedAt: new Date('2026-01-01') }, select: { id: true } });
    await db.exec(fs.readFileSync(path.join(migrations, newMigration, 'migration.sql'), 'utf8'));
    let upgradedRide;
    for (const dir of dirs.filter(d => d > newMigration)) {
      if (dir === '20260908150000_direct_carpool_booking') {
        upgradedRide = await prisma.carpoolOffer.create({ data: { eventId: event.id, driverId: coach.id, seatsTotal: 5, departureLocation: 'Test', departureAt: new Date('2030-09-14T09:00:00Z') }, select: { id: true } });
        await prisma.carpoolNeed.create({ data: { eventId: event.id, playerId: player.id, requestedById: parent.id }, select: { id: true } });
      }
      await db.exec(fs.readFileSync(path.join(migrations, dir, 'migration.sql'), 'utf8'));
    }
    assert.equal(await prisma.carpoolPassenger.count({ where: { offerId: upgradedRide.id, status: 'CONFIRMED' } }), 1, 'Existing open need automatically reserves one of five seats on upgrade');
    assert.equal((await prisma.carpoolNeed.findFirst({ where: { eventId: event.id } })).status, 'MATCHED');
    assert.equal((await prisma.attendance.findFirst({ where: { eventId: event.id } })).reason, 'Ursprüngliche Zusage');
    assert.equal((await db.query("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE '%Cash%' ")).rows.length, 0);
    console.log('PASS all migrations + populated upgrade + no cash tables');
    const call = async (fn, user, body = {}, params = {}, key = randomUUID()) => {
      let result;
      const req = { user, body, params, query: {}, method: 'POST', originalUrl: `/test/${fn.name}/${params.id ?? ''}`, get: () => key };
      const res = { json: v => { result = v; return v; }, status: () => res, set: () => res, send: () => undefined };
      await fn(req, res); return result;
    };
    await require('./carpool-integration.cjs')({ prisma, call, team, foreignTeam, club, coach, parent, secondParent, stranger, player });
    await require('./match-format-contact-integration.cjs')({ prisma, team, coach, parent, stranger });
    await require('./cross-team-match-integration.cjs')({ prisma, club, team, coach });
    const absences = require('../dist/src/controllers/absences.controller');
    const absenceInput = { playerId: player.id, startsOn: '2030-09-01', endsOn: '2030-09-30', weekdays: [], teamIds: [], eventTypes: ['MATCH'], reason: 'Urlaub' };
    const key = randomUUID();
    const absence = await call(absences.saveAbsence, parent, absenceInput, {}, key);
    assert.equal((await call(absences.saveAbsence, parent, absenceInput, {}, key)).id, absence.id);
    assert.equal(await prisma.playerAbsence.count(), 1);
    assert.equal((await prisma.attendance.findFirst({ where: { eventId: event.id } })).status, 'NO');
    await assert.rejects(call(absences.saveAbsence, stranger, absenceInput), e => e.status === 403);
    const future = await prisma.event.create({ data: { teamId: team.id, title: 'Nachträglich', type: 'MATCH', location: 'Teugn', startAt: new Date('2030-09-21T10:00:00Z') } });
    const { reconcileAbsencesForEvents } = require('../dist/src/services/absence.service');
    await prisma.$transaction(tx => reconcileAbsencesForEvents(tx, [future.id]));
    assert.equal((await prisma.attendance.findFirst({ where: { eventId: future.id } })).status, 'NO');
    await call(absences.endAbsence, parent, {}, { id: absence.id });
    assert.equal((await prisma.attendance.findFirst({ where: { eventId: event.id } })).status, 'YES');
    console.log('PASS absence scope, idempotent retry, late events, restored answer');
    const polls = require('../dist/src/controllers/polls.controller');
    const poll = await call(polls.createPoll, coach, { teamIds: [team.id], question: 'Termin?', options: ['Samstag', 'Sonntag'], unitType: 'FAMILY', resultsVisibility: 'AFTER_CLOSE', endsAt: new Date(Date.now() + 86400000).toISOString() });
    const parentPoll = (await call(polls.listPolls, parent))[0];
    const otherPoll = (await call(polls.listPolls, secondParent))[0];
    assert.equal(parentPoll.myUnits[0].id, otherPoll.myUnits[0].id);
    assert.equal(parentPoll.results, null);
    await call(polls.votePoll, parent, { unitId: parentPoll.myUnits[0].id, choices: [1] }, { id: poll.id });
    await assert.rejects(call(polls.votePoll, stranger, { unitId: parentPoll.myUnits[0].id, choices: [0] }, { id: poll.id }), e => e.status === 403);
    await call(polls.managePoll, coach, { action: 'CLOSE' }, { id: poll.id });
    await assert.rejects(call(polls.votePoll, secondParent, { unitId: parentPoll.myUnits[0].id, choices: [0] }, { id: poll.id }), e => e.status === 409);
    assert.deepEqual((await call(polls.listPolls, parent))[0].results, [0, 1]);
    console.log('PASS shared family vote, privacy, foreign voter, closed deadline');
    const goals = require('../dist/src/controllers/goals.controller');
    const goalInput = { playerId: player.id, title: 'Ballkontrolle', description: 'Drei kontrollierte Kontakte', startsOn: '2030-09-01', endsOn: '2030-10-01', responsibleUserId: coach.id, visibility: 'STAFF_ONLY' };
    for (let i = 0; i < 3; i++) await call(goals.saveGoal, coach, goalInput);
    await assert.rejects(call(goals.saveGoal, coach, goalInput), e => e.status === 409);
    assert.equal((await call(goals.listGoals, parent)).length, 0);
    const firstGoal = await prisma.learningGoal.findFirst();
    await call(goals.saveGoal, coach, { ...goalInput, visibility: 'FAMILY' }, { id: firstGoal.id });
    assert.equal((await call(goals.listGoals, parent)).length, 1);
    console.log('PASS three-goal limit and family visibility');
    const sharedNote = await prisma.playerDevelopmentNote.create({ data: {
      playerId: player.id, authorId: coach.id, title: 'Ballkontrolle im Training', notes: 'Kontrollierte Annahme verbessert',
      visibility: 'GUARDIANS_AND_STAFF', observedAt: new Date('2030-09-04T10:00:00Z') } });
    const privateNote = await prisma.playerDevelopmentNote.create({ data: {
      playerId: player.id, authorId: coach.id, title: 'Nur intern', notes: 'Private Trainernotiz',
      observedAt: new Date('2030-09-05T10:00:00Z') } });
    await prisma.playerDevelopmentNote.create({ data: {
      playerId: player.id, authorId: coach.id, title: 'Außerhalb des Zielzeitraums', notes: 'Alte Notiz',
      visibility: 'GUARDIANS_AND_STAFF', observedAt: new Date('2030-08-31T21:59:00Z') } });
    await call(goals.observeGoal, coach, { note: 'Erstes Zielgespräch', progress: 40 }, { id: firstGoal.id });
    const recorded = await prisma.event.create({ data: { teamId: team.id, title: 'Abgeschlossenes Spiel', type: 'MATCH',
      location: 'Testplatz', startAt: new Date('2030-09-10T10:00:00Z'), familyReleasedAt: new Date(),
      matchDetails: { create: { opponent: 'Testgegner', status: 'FINISHED' } },
      playerMatchStats: { create: { playerId: player.id, appeared: true, minutesPlayed: 25, goals: 1 } } } });
    await prisma.event.create({ data: { teamId: team.id, title: 'Unveröffentlicht', type: 'MATCH', location: 'Testplatz',
      startAt: new Date('2030-09-11T10:00:00Z'), matchDetails: { create: { opponent: 'Testgegner', status: 'FINISHED' } },
      playerMatchStats: { create: { playerId: player.id, appeared: true, minutesPlayed: 20 } } } });
    await prisma.event.create({ data: { teamId: team.id, title: 'Nur geplant', type: 'MATCH', location: 'Testplatz',
      startAt: new Date('2030-09-12T10:00:00Z'), familyReleasedAt: new Date(),
      matchDetails: { create: { opponent: 'Testgegner', status: 'PLANNED' } },
      playerMatchStats: { create: { playerId: player.id, appeared: true, minutesPlayed: 99 } } } });
    await prisma.event.create({ data: { teamId: team.id, title: 'Training am letzten Zieltag', type: 'TRAINING', location: 'Testplatz',
      startAt: new Date('2030-10-01T21:30:00Z'), familyReleasedAt: new Date(),
      attendance: { create: { playerId: player.id, status: 'YES', actualAttendance: 'NO' } } } });
    const familyDevelopment = await call(goals.getGoalDevelopment, parent, {}, { id: firstGoal.id });
    assert.equal(familyDevelopment.statistics.minutes, 25);
    assert.equal(familyDevelopment.statistics.recordedTrainings, 1);
    assert.equal(familyDevelopment.statistics.attendedTrainings, 0);
    assert.equal(familyDevelopment.timeline.some(t => t.id === sharedNote.id), true);
    assert.equal(familyDevelopment.timeline.some(t => t.id === privateNote.id), false);
    assert.equal(familyDevelopment.timeline.some(t => t.kind === 'GOAL' && t.progress === 40), true);
    assert.doesNotMatch(JSON.stringify(familyDevelopment), /Nur intern|Außerhalb|Nur geplant|Unveröffentlicht/);
    const coachDevelopment = await call(goals.getGoalDevelopment, coach, {}, { id: firstGoal.id });
    assert.equal(coachDevelopment.statistics.minutes, 45);
    assert.equal(coachDevelopment.timeline.some(t => t.id === privateNote.id), true);
    await assert.rejects(call(goals.getGoalDevelopment, stranger, {}, { id: firstGoal.id }), e => e.status === 404);
    await assert.rejects(call(goals.getGoalDevelopment, parent, {}, { id: 'missing' }), e => e.status === 404);
    const hiddenGoal = await prisma.learningGoal.findFirst({ where: { visibility: 'STAFF_ONLY' } });
    await assert.rejects(call(goals.getGoalDevelopment, parent, {}, { id: hiddenGoal.id }), e => e.status === 404);
    await prisma.event.update({ where: { id: recorded.id }, data: { status: 'CANCELLED' } });
    assert.equal((await call(goals.getGoalDevelopment, parent, {}, { id: firstGoal.id })).statistics.minutes, 0);
    const iosSubscription = await prisma.pushSubscription.create({ data: { userId: parent.id, platform: 'IOS', endpoint: 'ios-fixture-token_1234567890:abcdefghij' } });
    assert.equal(iosSubscription.platform, 'IOS');
    console.log('PASS development timeline: ownership, note privacy, period boundaries, actual vs planned, publication; IOS migration');
    const invitations = require('../dist/src/controllers/invitations.controller');
    const admin = await user('admin', 'CLUB_ADMIN');
    const invitation = await call(invitations.createInvitation, admin, { teamId: team.id, role: 'PARENT', days: 7 });
    const token = new URL(invitation.url.replace('/#/', '/')).searchParams.get('token');
    const claimed = await call(invitations.claimInvitation, stranger, { token });
    assert.equal(claimed.status, 'PENDING');
    const pending = await prisma.teamMembership.findUnique({ where: { userId_teamId: { userId: stranger.id, teamId: team.id } } });
    await call(invitations.reviewInvitationClaim, admin, { status: 'APPROVED' }, { id: pending.id });
    await assert.rejects(call(invitations.reviewInvitationClaim, admin, { status: 'REJECTED' }, { id: pending.id }), e => e.status === 409);
    await call(invitations.revokeInvitation, admin, {}, { id: invitation.id });
    await assert.rejects(call(invitations.claimInvitation, parent, { token }), e => e.status === 410);
    const staffInvitation = await call(invitations.createInvitation, admin, { teamId: foreignTeam.id, role: 'COACH', days: 7 });
    const staffToken = new URL(staffInvitation.url.replace('/#/', '/')).searchParams.get('token');
    await call(invitations.claimInvitation, parent, { token: staffToken });
    const staffPending = await prisma.teamMembership.findUnique({ where: { userId_teamId: { userId: parent.id, teamId: foreignTeam.id } } });
    await assert.rejects(call(invitations.reviewInvitationClaim, admin, { status: 'APPROVED' }, { id: staffPending.id }), e => e.status === 409 && e.message.includes('Familienrolle'));
    await call(invitations.reviewInvitationClaim, admin, { status: 'REJECTED' }, { id: staffPending.id });
    console.log('PASS invitation review, existing account, revocation and replay protection');
    const { writeCompetitionMatch } = require('../dist/src/services/competition-import-write.service');
    const imported = { externalId: 'ical-test', title: 'Test gegen Gast', startAt: '2030-10-05T10:00:00Z', endAt: null,
      location: 'Sportplatz A', address: null, opponent: 'Gast Test', opponentId: null, opponentClubName: 'Gast Test', opponentTeamDesignation: null,
      isHome: false, competition: 'Testliga', division: null, matchDay: null, status: 'SCHEDULED', ourGoals: null, theirGoals: null,
      periodCount: null, periodMinutes: null, sourceUrl: null };
    const importedId = await prisma.$transaction(tx => writeCompetitionMatch(tx, team.id, 'ICS', imported));
    await prisma.event.update({ where: { id: importedId }, data: { meetingLocation: 'Vereinsheim', location: 'Lokal B' } });
    const movedMatch = { ...imported, startAt: '2030-10-06T10:00:00Z' };
    await prisma.$transaction(tx => writeCompetitionMatch(tx, team.id, 'ICS', movedMatch));
    const movedEvent = await prisma.event.findUnique({ where: { id: importedId } });
    assert.equal(movedEvent.meetingLocation, 'Vereinsheim'); assert.equal(movedEvent.location, 'Lokal B'); assert.ok(movedEvent.responseRevisionAt);
    const changes = await prisma.eventChange.count();
    await prisma.$transaction(tx => writeCompetitionMatch(tx, team.id, 'ICS', movedMatch));
    assert.equal(await prisma.eventChange.count(), changes);
    await assert.rejects(prisma.$transaction(tx => writeCompetitionMatch(tx, team.id, 'ICS', { ...movedMatch, location: 'Quelle C' })), e => e.status === 409);
    await prisma.$transaction(tx => writeCompetitionMatch(tx, team.id, 'ICS', { ...movedMatch, location: 'Quelle C' }, null, false, { location: 'LOCAL' }));
    assert.equal((await prisma.event.findUnique({ where: { id: importedId } })).location, 'Lokal B');
    console.log('PASS real import relocation, local meeting place, field conflicts and duplicate suppression');
    const matchday = require('../dist/src/controllers/talents-matchday.controller');
    const checklist = await call(matchday.createMatchdayChecklist, coach, {}, { id: importedId });
    assert.equal((await call(matchday.createMatchdayChecklist, coach, {}, { id: importedId })).id, checklist.id);
    assert.equal(await prisma.checklistRun.count({ where: { eventId: importedId } }), 1);
    assert.ok((await call(matchday.matchdayReadiness, coach, {}, { id: importedId })).briefing.includes('Vereinsheim'));
    const { carryTalentsSeason } = require('../dist/src/services/talents-season');
    const nextTeam = await prisma.team.create({ data: { ageGroupId: age.id, name: 'Neue Saison', teamNumber: 3 } });
    await prisma.player.update({ where: { id: player.id }, data: { teamId: nextTeam.id } });
    const result = await prisma.$transaction(tx => carryTalentsSeason(tx, { [team.id]: nextTeam.id }, { goals: true, absences: true }, '2030-09-01', coach.id));
    assert.equal(result.carriedGoals, 3);
    assert.equal(await prisma.learningGoal.count({ where: { teamId: team.id, status: 'ARCHIVED' } }), 3);
    assert.equal(await prisma.parentPlayerLink.count({ where: { playerId: player.id } }), 2);
    assert.equal((await prisma.$transaction(tx => carryTalentsSeason(tx, { [team.id]: nextTeam.id }, { goals: true, absences: true }, '2030-09-01', coach.id))).carriedGoals, 0);
    console.log('PASS reusable checklist, season goal history, parent links and no repeated goal carry');
    if (process.argv.includes('--serve')) {
      process.env.PUBLIC_APP_URL = 'http://127.0.0.1:8080';
      process.env.CORS_ORIGINS = 'http://127.0.0.1:8080,http://localhost:8080';
      process.env.ACCESS_TOKEN_SECRET = 'local-test-access-secret-only-2030';
      process.env.REFRESH_TOKEN_SECRET = 'local-test-refresh-secret-only-2030';
      const { hashPassword } = require('../dist/src/lib/password');
      await prisma.user.updateMany({ data: { password: await hashPassword('Teugn-Test-2030!') } });
      // Restore the child to the initial team for the interactive smoke check.
      await prisma.player.update({ where: { id: player.id }, data: { teamId: team.id } });
      const app = require('../dist/src/server').default;
      const apiServer = app.listen(4000, '127.0.0.1');
      console.log('LOCAL TEST API ready on 127.0.0.1:4000; fake accounts only');
      await new Promise(resolve => { process.once('SIGINT', resolve); process.once('SIGTERM', resolve); });
      await new Promise(resolve => apiServer.close(resolve));
    }
  } finally {
    if (prisma) await prisma.$disconnect();
    await server.stop();
    await new Promise(resolve => setTimeout(resolve, 100));
    await db.close();
  }
}
main().catch(e => { console.error(e.name + ': ' + e.message); process.exitCode = 1; });
