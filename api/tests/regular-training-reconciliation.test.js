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
      create: async () => assert.fail('existing occurrence must be reused'),
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
      create: async () => assert.fail('no event expected'),
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

test('an explicitly hidden occurrence remains a tombstone after editing', async () => {
  const now = new Date('2026-08-16T10:00:00.000Z');
  const activeTeam = team(['Dienstag 17:30–19:00 · Platz: Platz 1']);
  const expected = nextRegularTrainingOccurrence(activeTeam, now);
  const expectedId =
    `regular-training:team-e1:${expected.startAt.getTime()}`;
  const tx = {
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
      create: async () => assert.fail('tombstone ID must not be recreated'),
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
