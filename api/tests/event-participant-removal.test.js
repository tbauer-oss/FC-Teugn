const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const controllerSource = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'events.controller.ts'),
  'utf8',
);
const dashboardSource = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'dashboard.controller.ts'),
  'utf8',
);
const reminderSource = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'services', 'reminder.service.ts'),
  'utf8',
);
const routesSource = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'routes', 'events.routes.ts'),
  'utf8',
);

const start = controllerSource.indexOf(
  'export async function removeEventParticipant',
);
const end = controllerSource.indexOf(
  'export async function finalizeAttendance',
  start,
);
const handler = controllerSource.slice(start, end);

test('staff can remove one player from one event through a dedicated route', () => {
  assert.ok(start >= 0, 'removeEventParticipant handler is missing');
  assert.match(
    routesSource,
    /router\.delete\('\/:id\/attendance\/:playerId', removeEventParticipant\)/,
  );
  assert.match(handler, /canManageEvent\(user, event\)/);
  assert.match(handler, /attendanceFinalized/);
});

test('event removal persists a durable participant exclusion and audit trail', () => {
  assert.match(handler, /eventParticipant\.upsert/);
  assert.match(handler, /responseRequired: false/);
  assert.match(handler, /attendance\.deleteMany/);
  assert.match(handler, /EVENT_PARTICIPANT_REMOVED/);
  assert.match(handler, /syncScheduledRemindersForEvent\(event\.id\)/);
});

test('removed match players are also removed from squad and lineup planning', () => {
  assert.match(handler, /plannedSubstitution\.deleteMany/);
  assert.match(handler, /lineupPosition\.deleteMany/);
  assert.match(handler, /squadMember\.deleteMany/);
});

test('dashboard and reminder recipients exclude removed event participants', () => {
  assert.match(dashboardSource, /!participant\.responseRequired/);
  assert.match(dashboardSource, /!excludedIds\.has\(player\.id\)/);
  assert.match(reminderSource, /!participant\.responseRequired/);
  assert.match(reminderSource, /notIn: \[\.\.\.excludedPlayerIds\]/);
});
