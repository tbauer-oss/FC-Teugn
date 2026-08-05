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

test('manual attendance reminders use the push notification service', () => {
  assert.match(handler, /notifyUsers\(recipients/);
  assert.match(handler, /NotificationCategory\.EVENT_REMINDER/);
  assert.match(handler, /pushEnabled:\s*true/);
});

test('every manual reminder can create a fresh push delivery', () => {
  assert.doesNotMatch(handler, /existingRecipients|alreadySent|notification\.upsert/);
  assert.match(handler, /eventReminder\.createMany/);
});
