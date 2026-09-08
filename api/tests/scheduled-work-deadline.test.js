const test = require('node:test');
const assert = require('node:assert/strict');
const { nextScheduledWorkAt, nextTrainingReminderCheck } = require('../dist/src/services/scheduled-work-deadline.service');
const minute = 60_000;
const now = new Date('2026-09-08T14:00:37Z');
const timing = (overrides = {}) => ({ trainingTimes: ['Dienstag 17:30–19:00'],
  indoorTrainingTimes: [], defaultReminderMinutes: 60, secondaryReminderMinutes: null, ...overrides });

function rows(t, overrides = {}) {
  const db = {};
  for (const model of ['scheduledReminder', 'announcement', 'event', 'eventChange',
    'talentsNotice', 'notificationDelivery', 'familyContactAttachment', 'notification']) {
    db[model] = { findFirst: async args => overrides[model]?.(args) ?? null };
  }
  for (const model of ['bfvTeamSync', 'team']) {
    db[model] = { findMany: async args => overrides[model]?.(args) ?? [] };
  }
  return db;
}

test('regular training retains its exact five-minute delivery window despite cron jitter', () => {
  const due = Date.parse('2026-09-08T14:30:00Z');
  assert.equal(nextTrainingReminderCheck([timing()], now, now.getTime() + 60 * minute), due);
  assert.equal(nextTrainingReminderCheck([timing()], new Date('2026-09-08T14:29:59Z'), due + minute), due);
});

test('indoor, secondary, overnight and daylight-saving reminders remain due', () => {
  const before = new Date('2026-09-08T21:45:37Z');
  assert.equal(nextTrainingReminderCheck([timing({
    trainingTimes: [], indoorTrainingTimes: ['Mittwoch 00:30–02:00'],
    defaultReminderMinutes: null, secondaryReminderMinutes: 30,
  })], before, before.getTime() + 60 * minute), Date.parse('2026-09-08T22:00:00Z'));
  for (const [beforeText, dueText] of [
    ['2026-03-29T06:30:37Z', '2026-03-29T07:00:00Z'],
    ['2026-10-25T07:30:37Z', '2026-10-25T08:00:00Z'],
  ]) {
    const beforeDst = new Date(beforeText);
    assert.equal(nextTrainingReminderCheck([timing({ trainingTimes: ['Sonntag 10:00–11:00'] })],
      beforeDst, beforeDst.getTime() + 60 * minute), Date.parse(dueText));
  }
});

test('disabled or malformed training schedules introduce no false delivery deadline', () => {
  const until = now.getTime() + 60 * minute;
  assert.equal(nextTrainingReminderCheck([timing({ defaultReminderMinutes: null })], now, until), until);
  assert.equal(nextTrainingReminderCheck([timing({ trainingTimes: ['invalid'] })], now, until), until);
});

test('empty queues yield a real idle hour without recipient reads', async t => {
  assert.equal(await nextScheduledWorkAt(now, rows(t)), now.getTime() + 60 * minute);
});

for (const [name, data] of [
  ['scheduled reminder', { scheduledReminder: () => ({ dueAt: new Date(now.getTime() + 7 * minute) }) }],
  ['announcement', { announcement: () => ({ publishAt: new Date(now.getTime() + 7 * minute) }) }],
  ['family attachment expiry', { familyContactAttachment: () => ({ expiresAt: new Date(now.getTime() + 7 * minute) }) }],
  ['private message expiry', { notification: () => ({ expiresAt: new Date(now.getTime() + 7 * minute) }) }],
  ['laundry reminder', { event: args => args.where.type ? { startAt: new Date(now.getTime() + 72 * minute) } : null }],
  ['BFV calendar sync', { bfvTeamSync: () => [{ lastAttemptAt: new Date(now.getTime() - 53 * minute), syncIntervalMinutes: 60 }] }],
]) {
  test(`${name} wakes the database on time`, async t => {
    assert.equal(await nextScheduledWorkAt(now, rows(t, data)), now.getTime() + 7 * minute);
  });
}

for (const model of ['event', 'eventChange', 'talentsNotice', 'notificationDelivery']) {
  test(`pending ${model} work prevents idle suppression`, async t => {
    const db = rows(t, { [model]: args => model !== 'event' || args.where.reminderSyncPendingAt ? { id: 'pending' } : null });
    assert.equal(await nextScheduledWorkAt(now, db), now.getTime());
  });
}

test('Berlin date-dependent absence changes run at midnight', async t => {
  assert.equal(await nextScheduledWorkAt(new Date('2026-09-08T21:45:37Z'), rows(t)), Date.parse('2026-09-08T22:00:00Z'));
});
