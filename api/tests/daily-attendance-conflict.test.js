const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  acceptAttendanceExclusivelyForDay,
  automaticDailyDeclineReason,
  berlinCalendarDayRange,
  isAutomaticDailyDeclineReason,
} = require('../dist/src/services/daily-attendance-conflict.service.js');

test('authorized staff corrections bypass finalized and expired response locks', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '../src/controllers/events.controller.ts'),
    'utf8',
  );
  const handler = source.slice(
    source.indexOf('export async function setAttendance'),
    source.indexOf('export async function removeEventParticipant'),
  );

  assert.match(
    handler,
    /canCorrectAttendance\s*=\s*!personalResponse\s*&&\s*canManageEventWithIds\(user, event, teamIds\)/,
  );
  assert.match(
    handler,
    /event\.attendanceFinalized\s*&&\s*!canCorrectAttendance/,
  );
  assert.match(
    handler,
    /!canCorrectAttendance\s*&&\s*event\.responseDeadline/,
  );
  assert.doesNotMatch(handler, /!isStaff\(user\.role\)/);
});

test('Berlin calendar-day ranges stay correct across summer and winter time', () => {
  const summer = berlinCalendarDayRange(new Date('2026-08-29T18:00:00.000Z'));
  assert.equal(summer.key, '2026-08-29');
  assert.equal(summer.startAt.toISOString(), '2026-08-28T22:00:00.000Z');
  assert.equal(summer.endAt.toISOString(), '2026-08-29T22:00:00.000Z');

  const winter = berlinCalendarDayRange(new Date('2026-12-01T18:00:00.000Z'));
  assert.equal(winter.key, '2026-12-01');
  assert.equal(winter.startAt.toISOString(), '2026-11-30T23:00:00.000Z');
  assert.equal(winter.endAt.toISOString(), '2026-12-01T23:00:00.000Z');
});

test('a new acceptance automatically declines every older acceptance that day', async () => {
  const calls = { locks: 0, updateMany: [], audits: [] };
  const conflicts = [
    {
      id: 'attendance-old-training',
      respondedAt: new Date('2026-08-29T12:00:00.000Z'),
      updatedAt: new Date('2026-08-29T12:00:00.000Z'),
      event: {
        id: 'old-training',
        title: 'Training E1',
        startAt: new Date('2026-08-29T14:00:00.000Z'),
        type: 'TRAINING',
        teamId: 'team-e1',
        targetTeams: [],
      },
    },
    {
      id: 'attendance-old-event',
      respondedAt: new Date('2026-08-29T13:00:00.000Z'),
      updatedAt: new Date('2026-08-29T13:00:00.000Z'),
      event: {
        id: 'old-team-event',
        title: 'Fototermin',
        startAt: new Date('2026-08-29T15:00:00.000Z'),
        type: 'EVENT',
        teamId: 'team-e1',
        targetTeams: [],
      },
    },
  ];
  const tx = {
    $executeRaw: async () => { calls.locks += 1; },
    attendance: {
      findMany: async () => conflicts,
      upsert: async (args) => ({ id: 'attendance-new', ...args.update }),
      updateMany: async (args) => { calls.updateMany.push(args); },
    },
    auditLog: {
      create: async (args) => { calls.audits.push(args); },
    },
  };

  const result = await acceptAttendanceExclusivelyForDay(tx, {
    event: {
      id: 'new-match',
      title: 'FC Teugn – FC Beispiel',
      startAt: new Date('2026-08-29T16:00:00.000Z'),
      teamId: 'team-e1',
    },
    playerId: 'player-1',
    actorId: 'parent-1',
    respondedAt: new Date('2026-08-29T19:00:00.000Z'),
    responseSource: 'GUARDIAN',
  });

  assert.equal(calls.locks, 1);
  assert.equal(result.accepted, true);
  assert.deepEqual(result.automaticallyDeclined, [
    'old-training',
    'old-team-event',
  ]);
  assert.deepEqual(calls.updateMany[0].where.id.in, [
    'attendance-old-training',
    'attendance-old-event',
  ]);
  assert.equal(calls.updateMany[0].data.status, 'NO');
  assert.equal(calls.updateMany[0].data.responseSource, 'SYSTEM_ADMINISTRATION');
  assert.match(calls.updateMany[0].data.reason, /FC Teugn – FC Beispiel/);
  assert.equal(calls.audits[0].data.action, 'ATTENDANCE_DAILY_CONFLICTS_AUTO_DECLINED');
});

test('an older series preference cannot replace a later explicit acceptance', async () => {
  let targetUpsert;
  let changedOlderAcceptance = false;
  const tx = {
    $executeRaw: async () => undefined,
    attendance: {
      findMany: async () => [{
        id: 'attendance-newer',
        respondedAt: new Date('2026-08-29T18:30:00.000Z'),
        updatedAt: new Date('2026-08-29T18:30:00.000Z'),
        event: {
          id: 'newer-match',
          title: 'Auswärtsspiel',
          startAt: new Date('2026-08-29T16:00:00.000Z'),
          type: 'MATCH',
          teamId: 'team-e1',
          targetTeams: [],
        },
      }],
      upsert: async (args) => {
        targetUpsert = args;
        return { id: 'attendance-training', ...args.update };
      },
      updateMany: async () => { changedOlderAcceptance = true; },
    },
    auditLog: { create: async () => undefined },
  };

  const result = await acceptAttendanceExclusivelyForDay(tx, {
    event: {
      id: 'regular-training',
      title: 'Training',
      startAt: new Date('2026-08-29T14:15:00.000Z'),
      teamId: 'team-e1',
    },
    playerId: 'player-1',
    actorId: 'parent-1',
    respondedAt: new Date('2026-08-20T09:00:00.000Z'),
    responseSource: 'GUARDIAN',
    honorLaterExistingAcceptance: true,
  });

  assert.equal(result.accepted, false);
  assert.equal(targetUpsert.update.status, 'NO');
  assert.match(targetUpsert.update.reason, /Auswärtsspiel/);
  assert.equal(changedOlderAcceptance, false);
  assert.equal(isAutomaticDailyDeclineReason(targetUpsert.update.reason), true);
  assert.match(
    automaticDailyDeclineReason({
      title: 'Training',
      startAt: new Date('2026-08-29T14:15:00.000Z'),
    }),
    /^Automatisch abgesagt:/,
  );
});
