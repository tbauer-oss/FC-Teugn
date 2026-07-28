const test = require('node:test');
const assert = require('node:assert/strict');

const { Permission, hasPermission } = require('../dist/src/security/permissions');
const { Role } = require('../dist/src/types/enums');
const {
  generateOccurrences,
  icsEscape,
  icsDate,
} = require('../dist/src/controllers/events.controller');
const { RecurrenceFrequency } = require('@prisma/client');

test('club administrators can manage the organization', () => {
  assert.equal(
    hasPermission(Role.CLUB_ADMIN, Permission.MANAGE_ORGANIZATION),
    true,
  );
});

test('coaches can manage players and events but not the organization', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_PLAYERS), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_EVENTS), true);
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_DEVELOPMENT),
    true,
  );
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_SENSITIVE_PLAYER),
    true,
  );
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_ORGANIZATION),
    false,
  );
});

test('parents can respond to attendance without changing team data', () => {
  assert.equal(
    hasPermission(Role.PARENT, Permission.RESPOND_ATTENDANCE),
    true,
  );
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_PLAYERS), false);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_EVENTS), false);
  assert.equal(
    hasPermission(Role.PARENT, Permission.VIEW_SENSITIVE_PLAYER),
    false,
  );
});

test('read-only members cannot mutate data', () => {
  assert.equal(hasPermission(Role.READ_ONLY, Permission.VIEW_TEAM), true);
  assert.equal(hasPermission(Role.READ_ONLY, Permission.MANAGE_TEAM), false);
  assert.equal(
    hasPermission(Role.READ_ONLY, Permission.VIEW_SENSITIVE_PLAYER),
    false,
  );
});

test('assistant coaches can document development but not edit medical data', () => {
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_DEVELOPMENT),
    true,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_SENSITIVE_PLAYER),
    false,
  );
});

test('matchday operations are restricted to assigned staff roles', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_LINEUPS),
    true,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_LIVE_TICKER),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.MANAGE_LINEUPS),
    false,
  );
  assert.equal(
    hasPermission(Role.PLAYER, Permission.MANAGE_LIVE_TICKER),
    false,
  );
});

test('weekly and biweekly calendar series include the boundary occurrence', () => {
  const start = new Date('2026-08-03T16:00:00.000Z');
  const weekly = generateOccurrences(
    start,
    new Date('2026-08-24T16:00:00.000Z'),
    RecurrenceFrequency.WEEKLY,
    1,
    [],
  );
  const biweekly = generateOccurrences(
    start,
    new Date('2026-08-31T16:00:00.000Z'),
    RecurrenceFrequency.BIWEEKLY,
    1,
    [],
  );
  assert.deepEqual(
    weekly.map((value) => value.toISOString()),
    [
      '2026-08-03T16:00:00.000Z',
      '2026-08-10T16:00:00.000Z',
      '2026-08-17T16:00:00.000Z',
      '2026-08-24T16:00:00.000Z',
    ],
  );
  assert.equal(biweekly.length, 3);
});

test('custom calendar series supports selected weekdays and an interval', () => {
  const dates = generateOccurrences(
    new Date('2026-08-03T16:00:00.000Z'),
    new Date('2026-08-16T16:00:00.000Z'),
    RecurrenceFrequency.CUSTOM,
    1,
    [1, 3],
  );
  assert.deepEqual(
    dates.map((value) => value.toISOString().slice(0, 10)),
    ['2026-08-03', '2026-08-05', '2026-08-10', '2026-08-12'],
  );
});

test('calendar generation is bounded and ICS values are escaped safely', () => {
  const dates = generateOccurrences(
    new Date('2026-01-01T10:00:00.000Z'),
    new Date('2030-01-01T10:00:00.000Z'),
    RecurrenceFrequency.CUSTOM,
    1,
    [1, 2, 3, 4, 5, 6, 7],
  );
  assert.equal(dates.length, 120);
  assert.equal(icsEscape('FC, Teugn; A\\B\nTraining'), 'FC\\, Teugn\\; A\\\\B\\nTraining');
  assert.equal(
    icsDate(new Date('2026-08-03T16:00:00.123Z')),
    '20260803T160000Z',
  );
});
