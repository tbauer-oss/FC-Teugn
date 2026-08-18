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

test('manual attendance reminders honor the optional push selection', () => {
  assert.match(handler, /notifyUsers\(recipients/);
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
