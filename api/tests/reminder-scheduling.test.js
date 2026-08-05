const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const service = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'services', 'reminder.service.ts'),
  'utf8',
);
const organization = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'organization.controller.ts'),
  'utf8',
);

test('regular training reminders support an explicit opt-out', () => {
  assert.match(service, /if \(team\.defaultReminderMinutes == null\) continue/);
  assert.doesNotMatch(service, /defaultReminderMinutes \?\? 60/);
});

test('due reminders re-check current relevance after attendance changes', () => {
  assert.match(service, /declinedPlayerIds/);
  assert.match(service, /currentRecipients/);
  assert.match(service, /ReminderJobStatus\.CANCELLED/);
});

test('team reminder lead time is validated, stored and serialized', () => {
  assert.match(organization, /defaultReminderMinutes < 1/);
  assert.match(organization, /defaultReminderMinutes > 10_080/);
  assert.match(organization, /defaultReminderMinutes: team\.defaultReminderMinutes/);
});
