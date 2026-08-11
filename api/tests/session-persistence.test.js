const assert = require('node:assert/strict');
const test = require('node:test');

const {
  isRecentRefreshRotation,
  refreshRotationGraceMs,
} = require('../dist/src/lib/session-refresh.js');

test('near-simultaneous refresh rotation is treated as a recoverable race', () => {
  const now = new Date('2026-08-11T10:00:00.000Z');
  assert.equal(
    isRecentRefreshRotation(new Date(now.getTime() - 500), now),
    true,
  );
  assert.equal(
    isRecentRefreshRotation(
      new Date(now.getTime() - refreshRotationGraceMs - 1),
      now,
    ),
    false,
  );
  assert.equal(isRecentRefreshRotation(null, now), false);
});
