const test = require('node:test');
const assert = require('node:assert/strict');

const {
  settlePostCommitTasks,
} = require('../dist/src/services/post-commit.service.js');

test('post-commit failures do not reject an already successful write', async () => {
  const errors = [];

  await assert.doesNotReject(() => settlePostCommitTasks([
    { name: 'audit', promise: Promise.resolve('ok') },
    { name: 'reminders', promise: Promise.reject(new Error('unavailable')) },
  ], (taskName, error) => errors.push({ taskName, error })));

  assert.equal(errors.length, 1);
  assert.equal(errors[0].taskName, 'reminders');
  assert.match(errors[0].error.message, /unavailable/);
});
