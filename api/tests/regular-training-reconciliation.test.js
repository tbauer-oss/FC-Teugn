const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  nextRegularTrainingOccurrence,
  reconcileNextRegularTrainingOccurrence,
} = require('../dist/src/services/regular-training-occurrence.service');

function team(trainingTimes) {
  return {
    id: 'team-e1',
    name: 'E1-Jugend',
    trainingLocation: 'Teugn Sportplatz',
    trainingTimes,
    seasonStartDate: new Date('2026-08-01T00:00:00.000Z'),
    seasonEndDate: new Date('2027-06-30T00:00:00.000Z'),
    indoorSeasonStartDate: null,
    indoorSeasonEndDate: null,
    indoorTrainingLocation: null,
    indoorTrainingTimes: [],
    ageGroup: {
      season: {
        name: '2026/27',
        startDate: new Date('2026-08-01T00:00:00.000Z'),
        endDate: new Date('2027-06-30T00:00:00.000Z'),
      },
    },
  };
}

test('schedule edits move the response-bearing occurrence and hide duplicates', async () => {
  const now = new Date('2026-08-16T10:00:00.000Z');
  const changedTeam = team(['Freitag 18:00–19:30 · Platz: Platz 2']);
  const expected = nextRegularTrainingOccurrence(changedTeam, now);
  const calls = { updates: [], updateMany: [] };
  const tx = {
    event: {
      findMany: async () => [
        {
          id: 'regular-training:team-e1:old-with-replies',
          startAt: new Date('2026-08-18T15:30:00.000Z'),
          isHiddenRegularOccurrence: false,
          _count: { attendance: 4, participants: 1 },
        },
        {
          id: 'regular-training:team-e1:stale-duplicate',
          startAt: new Date('2026-08-18T16:30:00.000Z'),
          isHiddenRegularOccurrence: false,
          _count: { attendance: 0, participants: 0 },
        },
      ],
      update: async (args) => calls.updates.push(args),
      upsert: async () => assert.fail('existing occurrence must be reused'),
      updateMany: async (args) => calls.updateMany.push(args),
    },
  };

  const ids = await reconcileNextRegularTrainingOccurrence(
    tx,
    changedTeam,
    now,
  );

  assert.deepEqual(ids, [
    'regular-training:team-e1:old-with-replies',
    'regular-training:team-e1:stale-duplicate',
  ]);
  assert.equal(calls.updates.length, 1);
  assert.equal(
    calls.updates[0].where.id,
    'regular-training:team-e1:old-with-replies',
  );
  assert.equal(
    calls.updates[0].data.startAt.toISOString(),
    expected.startAt.toISOString(),
  );
  assert.deepEqual(calls.updateMany[0].where.id.in, [
    'regular-training:team-e1:stale-duplicate',
  ]);
  assert.equal(calls.updateMany[0].data.isHiddenRegularOccurrence, true);
});

test('removing a regular schedule hides its future materialization', async () => {
  const hidden = [];
  const tx = {
    event: {
      findMany: async () => [
        {
          id: 'regular-training:team-e1:future',
          startAt: new Date('2026-08-18T15:30:00.000Z'),
          isHiddenRegularOccurrence: false,
          _count: { attendance: 0, participants: 0 },
        },
      ],
      update: async () => assert.fail('no canonical event expected'),
      upsert: async () => assert.fail('no event expected'),
      updateMany: async (args) => hidden.push(args),
    },
  };

  const ids = await reconcileNextRegularTrainingOccurrence(
    tx,
    team([]),
    new Date('2026-08-16T10:00:00.000Z'),
  );

  assert.deepEqual(ids, ['regular-training:team-e1:future']);
  assert.deepEqual(hidden[0].where.id.in, [
    'regular-training:team-e1:future',
  ]);
});

test('hidden stale occurrences cannot recreate reminder jobs', () => {
  const reminders = fs.readFileSync(
    path.join(__dirname, '../src/services/reminder.service.ts'),
    'utf8',
  );
  assert.match(
    reminders,
    /!event\.isHiddenRegularOccurrence && desiredJobs\.length > 0/,
  );
});

test('series confirmations are persisted and preserve explicit absences', () => {
  const schema = fs.readFileSync(
    path.join(__dirname, '../prisma/schema.prisma'),
    'utf8',
  );
  const controller = fs.readFileSync(
    path.join(__dirname, '../src/controllers/events.controller.ts'),
    'utf8',
  );
  const reconciliation = fs.readFileSync(
    path.join(
      __dirname,
      '../src/services/regular-training-occurrence.service.ts',
    ),
    'utf8',
  );

  assert.match(schema, /model RegularTrainingAttendancePreference/);
  assert.match(controller, /setRegularTrainingAttendancePreference/);
  assert.match(controller, /validUntil/);
  assert.match(
    reconciliation,
    /existingByPlayer\.get\(preference\.playerId\) === AttendanceStatus\.NO/,
  );
  assert.match(
    reconciliation,
    /regularTrainingAttendancePreference\.findMany/,
  );
});

test('an explicitly deleted occurrence remains a tombstone after editing', async () => {
  const now = new Date('2026-08-16T10:00:00.000Z');
  const activeTeam = team(['Dienstag 17:30–19:00 · Platz: Platz 1']);
  const expected = nextRegularTrainingOccurrence(activeTeam, now);
  const expectedId =
    `regular-training:team-e1:${expected.startAt.getTime()}`;
  const tx = {
    auditLog: {
      findFirst: async () => ({ id: 'audit-explicit-deletion' }),
    },
    event: {
      findMany: async () => [
        {
          id: expectedId,
          startAt: expected.startAt,
          isHiddenRegularOccurrence: true,
          _count: { attendance: 0, participants: 0 },
        },
      ],
      update: async () => assert.fail('tombstone must not be reactivated'),
      upsert: async () => assert.fail('tombstone ID must not be recreated'),
      updateMany: async () => assert.fail('tombstone is already hidden'),
    },
  };

  const ids = await reconcileNextRegularTrainingOccurrence(
    tx,
    activeTeam,
    now,
  );

  assert.deepEqual(ids, [expectedId]);
});

test('a deleted legacy occurrence remains a tombstone despite a different id', async () => {
  const now = new Date('2026-08-16T10:00:00.000Z');
  const activeTeam = team(['Dienstag 17:30–19:00 · Platz: Platz 1']);
  const expected = nextRegularTrainingOccurrence(activeTeam, now);
  const legacyId = 'legacy-regular-training-occurrence';
  const tx = {
    auditLog: {
      findFirst: async (args) => {
        assert.equal(args.where.entityId, legacyId);
        assert.deepEqual(args.where.action.in, [
          'CANCELLED_TRAINING_OCCURRENCE_DELETED',
          'REGULAR_TRAINING_OCCURRENCE_DELETED',
        ]);
        return { id: 'audit-explicit-deletion' };
      },
    },
    event: {
      findMany: async () => [
        {
          id: legacyId,
          startAt: new Date(expected.startAt.getTime() + 30_000),
          isHiddenRegularOccurrence: true,
          _count: { attendance: 0, participants: 0 },
        },
      ],
      update: async () => assert.fail('tombstone must not be reactivated'),
      upsert: async () => assert.fail('tombstone must not be recreated'),
      updateMany: async () => assert.fail('tombstone is already hidden'),
    },
  };

  const ids = await reconcileNextRegularTrainingOccurrence(
    tx,
    activeTeam,
    now,
  );

  assert.deepEqual(ids, [legacyId]);
});

test('single regular-training deletion is silent and cancellation push is optional', () => {
  const routes = fs.readFileSync(
    path.join(__dirname, '../src/routes/events.routes.ts'),
    'utf8',
  );
  const controller = fs.readFileSync(
    path.join(__dirname, '../src/controllers/events.controller.ts'),
    'utf8',
  );

  assert.match(routes, /regular-training-occurrences\/delete/);
  assert.match(controller, /REGULAR_TRAINING_OCCURRENCE_DELETED/);
  assert.match(controller, /silent:\s*true/);
  assert.match(controller, /notifyParticipants\s*=\s*req\.body(?:\?)?\.notifyParticipants\s*!==\s*false/);
});

test('an automatically hidden expected occurrence is reactivated after a schedule edit', async () => {
  const now = new Date('2026-08-16T10:00:00.000Z');
  const activeTeam = team(['Dienstag 17:15–18:45 · Platz: Platz 1']);
  const expected = nextRegularTrainingOccurrence(activeTeam, now);
  const expectedId =
    `regular-training:team-e1:${expected.startAt.getTime()}`;
  const calls = { updates: [], updateMany: [] };
  const tx = {
    auditLog: {
      findFirst: async () => null,
    },
    event: {
      findMany: async () => [
        {
          id: expectedId,
          startAt: expected.startAt,
          endAt: expected.endAt,
          location: expected.location,
          status: 'SCHEDULED',
          isHiddenRegularOccurrence: true,
          _count: { attendance: 0, participants: 0 },
        },
        {
          id: 'regular-training:team-e1:old-1730',
          startAt: new Date('2026-08-18T15:30:00.000Z'),
          status: 'SCHEDULED',
          isHiddenRegularOccurrence: false,
          _count: { attendance: 0, participants: 0 },
        },
      ],
      update: async (args) => calls.updates.push(args),
      upsert: async () => assert.fail('hidden occurrence must be reused'),
      updateMany: async (args) => calls.updateMany.push(args),
    },
  };

  const ids = await reconcileNextRegularTrainingOccurrence(
    tx,
    activeTeam,
    now,
  );

  assert.deepEqual(ids, [expectedId, 'regular-training:team-e1:old-1730']);
  assert.equal(calls.updates[0].where.id, expectedId);
  assert.equal(calls.updates[0].data.isHiddenRegularOccurrence, false);
  assert.deepEqual(calls.updateMany[0].where.id.in, [
    'regular-training:team-e1:old-1730',
  ]);
});

test('a cancelled old time is hidden and never moved to the new schedule', async () => {
  const now = new Date('2026-08-16T10:00:00.000Z');
  const changedTeam = team(['Freitag 18:00–19:30 · Platz: Platz 2']);
  const calls = { updates: [], updateMany: [] };
  const tx = {
    event: {
      findMany: async () => [
        {
          id: 'regular-training:team-e1:cancelled-old-time',
          startAt: new Date('2026-08-18T15:30:00.000Z'),
          status: 'CANCELLED',
          isHiddenRegularOccurrence: false,
          _count: { attendance: 4, participants: 0 },
        },
        {
          id: 'regular-training:team-e1:scheduled-old-time',
          startAt: new Date('2026-08-18T16:30:00.000Z'),
          status: 'SCHEDULED',
          isHiddenRegularOccurrence: false,
          _count: { attendance: 0, participants: 0 },
        },
      ],
      update: async (args) => calls.updates.push(args),
      upsert: async () => assert.fail('scheduled occurrence can be reused'),
      updateMany: async (args) => calls.updateMany.push(args),
    },
  };

  await reconcileNextRegularTrainingOccurrence(tx, changedTeam, now);

  assert.equal(
    calls.updates[0].where.id,
    'regular-training:team-e1:scheduled-old-time',
  );
  assert.deepEqual(calls.updateMany[0].where.id.in, [
    'regular-training:team-e1:cancelled-old-time',
  ]);
});

test('legacy regular occurrences are included in automatic cleanup', async () => {
  let query;
  const tx = {
    event: {
      findMany: async (args) => {
        query = args.where;
        return [];
      },
      update: async () => assert.fail('no existing event'),
      upsert: async () => undefined,
      updateMany: async () => undefined,
    },
  };

  await reconcileNextRegularTrainingOccurrence(
    tx,
    team(['Dienstag 17:30–19:00 · Platz: Platz 1']),
    new Date('2026-08-16T10:00:00.000Z'),
  );

  assert.equal(query.category, 'TRAINING');
  assert.equal(query.OR[0].id.startsWith, 'regular-training:team-e1:');
  assert.match(
    query.OR[1].description.startsWith,
    /^Reguläre Trainingszeit laut Belegungsplan/,
  );
});

test('mobile actions persist a team-specific tombstone for every regular-training id', () => {
  const calendarPage = fs.readFileSync(
    path.join(
      __dirname,
      '../../fc_teugn_app/lib/features/calendar/calendar_page.dart',
    ),
    'utf8',
  );
  const controller = fs.readFileSync(
    path.join(__dirname, '../src/controllers/events.controller.ts'),
    'utf8',
  );

  assert.match(
    calendarPage,
    /final confirmed = _isRegularTraining[\s\S]*cancelRegularTrainingOccurrence\([\s\S]*teamId: event\.teamId/,
  );
  assert.match(
    calendarPage,
    /if \(_isRegularTraining\)[\s\S]*deleteRegularTrainingOccurrence\([\s\S]*teamId: event\.teamId/,
  );
  assert.match(
    controller,
    /regular-training:\$\{teamId\}:\$\{startAt\.getTime\(\)\}/,
  );
});
