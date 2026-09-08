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
  assert.equal(reads, 1, 'all viewers must share the immediate probe');
});

test('100 quiet viewers share probes and stop querying after their final timeout', async () => {
  let reads = 0;
  const eventId = `quiet-fanout-${Date.now()}`;
  const viewers = Array.from({ length: 100 }, () => waitForLiveTickerUpdate({
    eventId, after: 1, waitMs: 180, pollIntervalMs: 25,
    readSequence: async () => { reads++; return 1; },
  }));
  assert.deepEqual(await Promise.all(viewers), Array(100).fill(false));
  assert.ok(reads >= 1 && reads <= 8, `expected shared probes, got ${reads}`);
  const finishedReads = reads;
  await delay(60);
  assert.equal(reads, finishedReads, 'idle matches must not keep a timer or DB probe alive');
});

test('a publish during a running database read triggers an immediate second read', async () => {
  let finishRead;
  let reads = 0;
  const eventId = `inflight-${Date.now()}`;
  const waiting = waitForLiveTickerUpdate({
    eventId, after: 1, waitMs: 1000, pollIntervalMs: 500,
    readSequence: async () => {
      reads++;
      if (reads === 1) return new Promise(resolve => { finishRead = resolve; });
      return 2;
    },
  });
  publishLiveTickerUpdate(eventId);
  publishLiveTickerUpdate(eventId);
  finishRead(1);
  assert.equal(await waiting, true);
  assert.equal(reads, 2);
});

test('mixed viewer sequences and match isolation do not leak or swallow updates', async () => {
  const eventId = `mixed-${Date.now()}`;
  const old = waitForLiveTickerUpdate({ eventId, after: 1, waitMs: 200, readSequence: async () => 2 });
  const current = waitForLiveTickerUpdate({ eventId, after: 2, waitMs: 60, readSequence: async () => 2 });
  const other = waitForLiveTickerUpdate({ eventId: `${eventId}-other`, after: 1, waitMs: 60,
    readSequence: async () => assert.fail('another match was probed by this publish') });
  publishLiveTickerUpdate(eventId);
  assert.deepEqual(await Promise.all([old, current, other]), [true, false, false]);
});

test('probe failures release every viewer and permit a clean retry', async () => {
  const eventId = `failure-${Date.now()}`;
  const readers = Array.from({ length: 30 }, () => waitForLiveTickerUpdate({
    eventId, after: 1, waitMs: 500, readSequence: async () => { throw Error('temporary'); },
  }));
  const outcomes = Promise.allSettled(readers);
  publishLiveTickerUpdate(eventId);
  assert.ok((await outcomes).every(result => result.status === 'rejected'));
  const retry = waitForLiveTickerUpdate({ eventId, after: 1, waitMs: 500, readSequence: async () => 2 });
  publishLiveTickerUpdate(eventId);
  assert.equal(await retry, true);
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
