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
const events = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'events.controller.ts'),
  'utf8',
);

test('regular training reminders support an explicit opt-out', () => {
  assert.match(service, /if \(reminderMinutes\.length === 0\) continue/);
  assert.match(service, /secondaryReminderMinutes/);
  assert.doesNotMatch(service, /defaultReminderMinutes \?\? 60/);
});

test('due reminders re-check current relevance after attendance changes', () => {
  assert.match(service, /declinedPlayerIds/);
  assert.match(service, /currentRecipients/);
  assert.match(service, /ReminderJobStatus\.CANCELLED/);
});

test('trainer-only participants keep the full team reminder audience', () => {
  assert.match(service, /explicitlyRequestedPlayers/);
  assert.match(service, /if \(explicitlyRequestedPlayers\.length\)/);
  assert.doesNotMatch(service, /if \(event\.participants\.length\)/);
});

test('due jobs are reconciled before automatic reminders are delivered', () => {
  assert.match(service, /dueEventCandidates/);
  assert.match(
    service,
    /dueEventCandidates\.map\(\(\{ eventId \}\) => syncScheduledRemindersForEvent\(eventId\)\)/,
  );
});

test('team reminder lead time is validated, stored and serialized', () => {
  assert.match(organization, /defaultReminderMinutes < 1/);
  assert.match(organization, /defaultReminderMinutes > 10_080/);
  assert.match(organization, /defaultReminderMinutes: team\.defaultReminderMinutes/);
});

test('24-hour reminders clearly identify tomorrow without relabeling longer lead times', () => {
  assert.match(service, /minutesBefore >= 23 \* 60/);
  assert.match(service, /minutesBefore <= 25 \* 60/);
  assert.match(service, /Training morgen/);
  assert.match(service, /isDayBefore \? 'Morgen'/);
  assert.match(service, /reguläres Training von/);
});

test('calendar downloads are scoped to the selected youth and include regular training series', () => {
  assert.match(events, /selectedContextTeamIds\(req\.user!\)/);
  assert.match(events, /\?ageGroupId=/);
  assert.match(events, /RRULE:FREQ=WEEKLY/);
  assert.match(events, /Content-Disposition', 'attachment/);
});
