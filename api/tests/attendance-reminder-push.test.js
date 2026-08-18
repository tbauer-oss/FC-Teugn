const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'events.controller.ts'),
  'utf8',
);
const start = source.indexOf('export async function sendAttendanceReminders');
const end = source.indexOf('export async function createCarpoolOffer', start);
const handler = source.slice(start, end);
const routes = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'routes', 'events.routes.ts'),
  'utf8',
);

test('manual attendance reminders honor the optional push selection', () => {
  assert.match(handler, /queueUserNotifications\(recipients/);
  assert.match(handler, /NotificationCategory\.EVENT_REMINDER/);
  assert.match(handler, /req\.body\.pushEnabled !== false/);
  assert.match(handler, /pushEnabled,/);
});

test('manual training reminders can target either open or all players', () => {
  assert.match(handler, /req\.body\.audience/);
  assert.match(handler, /audience === 'ALL'/);
  assert.match(handler, /audience === 'OPEN' \? \{ notIn: \[\.\.\.replied\] \} : \{\}/);
  assert.match(handler, /title: audience === 'ALL'/);
  assert.match(handler, /'Trainingserinnerung'/);
  assert.match(handler, /targetedPlayers: players\.length/);
});

test('trainer-only participants do not suppress reminders for the team roster', () => {
  assert.match(handler, /explicitlyRequested\.length \? \{ in: explicitlyRequested \} : \{\}/);
  assert.doesNotMatch(handler, /event\.participants\.length \? \{ in: explicitlyRequested \}/);
});

test('one manual reminder request cannot create duplicate push deliveries', () => {
  assert.match(handler, /req\.header\('x-idempotency-key'\)/);
  assert.match(handler, /dedupeKey: requestIdempotencyKey/);
  assert.match(handler, /attendance-reminder:\$\{user\.id\}:\$\{event\.id\}/);
  assert.doesNotMatch(handler, /existingRecipients|alreadySent|notification\.upsert/);
  assert.match(handler, /eventReminder\.createMany/);
});

test('manual reminders acknowledge a durable queue before external push delivery finishes', () => {
  assert.match(handler, /await queueUserNotifications\(recipients/);
  assert.match(handler, /waitUntil\(settlePostCommitTasks/);
  assert.match(handler, /promise: deliverQueuedPushes\(queuedResult\.deliveryIds\)/);
  assert.match(handler, /return res\.status\(202\)\.json/);
  assert.match(handler, /accepted: true/);
  assert.match(handler, /deliveryStatus: 'QUEUED'/);
  assert.match(handler, /queuedPushDeliveries: queuedResult\.deliveries/);
  assert.match(handler, /pushDeliveries: 0/);
  assert.doesNotMatch(handler, /await notifyUsers\(recipients/);
});

test('manual reminder status resolves an ambiguous response without resending', () => {
  assert.match(routes, /\/:id\/attendance\/reminders\/status/);
  assert.match(routes, /attendanceReminderStatus/);
  assert.match(handler, /export async function attendanceReminderStatus/);
  assert.match(handler, /idempotencyRecord\.findUnique/);
  assert.match(handler, /dedupeKey: \{ startsWith: dedupePrefix \}/);
  assert.match(handler, /sentPushRecipients/);
  assert.match(handler, /pendingPushRecipients/);
  assert.match(handler, /recipientsWithoutActivePush/);
  assert.match(handler, /deliveryComplete: pendingPushDevices === 0/);
});
