const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('squad save keeps slow reminder maintenance off the request path', () => {
  const controller = source('src/controllers/matches.controller.ts');
  const updateSquad = controller.slice(
    controller.indexOf('export async function updateSquad'),
    controller.indexOf('export async function publishSquad'),
  );

  assert.match(updateSquad, /findMatchForSquadUpdate/);
  assert.match(updateSquad, /attendance\.createMany/);
  assert.doesNotMatch(updateSquad, /attendance\.upsert/);
  assert.match(updateSquad, /reminderSyncPendingAt/);
  assert.doesNotMatch(updateSquad, /syncScheduledRemindersForEvent/);
  assert.doesNotMatch(updateSquad, /settlePostCommitTasks/);
});

test('reminder rebuild uses bulk database operations', () => {
  const reminders = source('src/services/reminder.service.ts');
  const synchronization = reminders.slice(
    reminders.indexOf('export async function syncScheduledRemindersForEvent'),
    reminders.indexOf('export async function processPendingReminderSyncs'),
  );

  assert.match(synchronization, /scheduledReminder\.deleteMany/);
  assert.match(synchronization, /scheduledReminder\.createMany/);
  assert.doesNotMatch(synchronization, /scheduledReminder\.upsert/);
});
