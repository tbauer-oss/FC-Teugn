const test = require('node:test');
const assert = require('node:assert/strict');

const {
  publishLiveTickerUpdate,
  waitForLiveTickerUpdate,
} = require('../dist/src/services/live-ticker-realtime.service');

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

test('one ticker update wakes at least 20 concurrent viewers immediately', async () => {
  const eventId = `load-${Date.now()}`;
  let sequence = 7;
  let reads = 0;
  const startedAt = Date.now();
  const viewers = Array.from({ length: 24 }, () =>
    waitForLiveTickerUpdate({
      eventId,
      after: 7,
      waitMs: 1000,
      pollIntervalMs: 500,
      readSequence: async () => {
        reads += 1;
        return sequence;
      },
    }),
  );

  await delay(25);
  sequence = 8;
  publishLiveTickerUpdate(eventId);

  assert.deepEqual(await Promise.all(viewers), Array(24).fill(true));
  assert.ok(Date.now() - startedAt < 400, 'viewers were not woken live');
  assert.ok(reads <= 30, 'same-instance wake-up performed excessive probes');
});

test('database probing catches cross-instance updates for 20+ viewers', async () => {
  let sequence = 3;
  const eventId = `cross-instance-${Date.now()}`;
  const viewers = Array.from({ length: 24 }, () =>
    waitForLiveTickerUpdate({
      eventId,
      after: 3,
      waitMs: 500,
      pollIntervalMs: 20,
      readSequence: async () => sequence,
    }),
  );

  await delay(45);
  sequence = 4;

  assert.deepEqual(await Promise.all(viewers), Array(24).fill(true));
});

test('ticker reset and quiet timeout both complete deterministically', async () => {
  let sequence = 12;
  const reset = waitForLiveTickerUpdate({
    eventId: `reset-${Date.now()}`,
    after: 12,
    waitMs: 500,
    pollIntervalMs: 20,
    readSequence: async () => sequence,
  });
  await delay(30);
  sequence = 0;
  assert.equal(await reset, true);

  const quiet = await waitForLiveTickerUpdate({
    eventId: `quiet-${Date.now()}`,
    after: 0,
    waitMs: 60,
    pollIntervalMs: 20,
    readSequence: async () => 0,
  });
  assert.equal(quiet, false);
});
