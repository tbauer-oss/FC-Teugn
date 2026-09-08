const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { ScheduledWorkCache, sharedRuntimeCacheAvailable, scheduledWorkCache } =
  require('../dist/src/services/scheduled-work-cache.service');
const { affectsScheduledWork, invalidateScheduledWork } =
  require('../dist/src/middleware/scheduled-work-invalidation');

const minute = 60_000;
const now = Date.parse('2026-09-08T12:00:00Z');
function memory() {
  const values = new Map();
  return { values, get: async key => values.get(key) ?? null,
    set: async (key, value) => { values.set(key, value); },
    delete: async key => { values.delete(key); }, expireTag: async () => {} };
}
async function idle(cache, at = now, due = at + 60 * minute) {
  const guard = new ScheduledWorkCache(cache);
  await guard.invalidate(at - 7 * minute);
  await guard.checkpoint(async () => due, at);
  return guard;
}

test('idle cron skips the database until its actual deadline, at the existing five-minute cadence', async () => {
  const guard = await idle(memory(), now, now + 35 * minute);
  for (let offset = 0; offset < 35; offset += 5) {
    assert.equal(await guard.shouldRun(now + offset * minute), false);
  }
  assert.equal(await guard.shouldRun(now + 35 * minute), true);
});

test('missing, evicted, malformed, unavailable and failing cache all run the worker', async () => {
  const cache = memory();
  const guard = await idle(cache);
  cache.values.delete('plan');
  assert.equal(await guard.shouldRun(now), true);
  cache.values.set('plan', { checkedAt: NaN, nextDueAt: Infinity });
  assert.equal(await guard.shouldRun(now), true);
  assert.equal(await new ScheduledWorkCache(null).shouldRun(now), true);
  assert.equal(await new ScheduledWorkCache(cache, () => false).shouldRun(now), true);
  cache.get = async () => { throw Error('temporary cache outage'); };
  assert.equal(await guard.shouldRun(now), true);
});

test('new mutations and writes still in flight invalidate an idle decision', async () => {
  const cache = memory();
  const guard = await idle(cache);
  await guard.invalidate(now);
  let scans = 0;
  await guard.checkpoint(async () => { scans++; return now + 60 * minute; }, now + minute);
  assert.equal(scans, 0, 'must not checkpoint an unfinished mutation');
  assert.equal(await guard.shouldRun(now + minute), true);
  await guard.checkpoint(async () => now + 60 * minute, now + 7 * minute);
  assert.equal(await guard.shouldRun(now + 8 * minute), false);
});

test('a concurrent mutation cannot be hidden by a checkpoint that finishes later', async () => {
  const cache = memory();
  const guard = await idle(cache);
  await guard.checkpoint(async () => {
    await guard.invalidate(now + 1);
    return now + 60 * minute;
  }, now);
  assert.equal(await guard.shouldRun(now + 5 * minute), true);
});

test('hourly fallback catches external writes even if a cached deadline is further away', async () => {
  const cache = memory();
  const guard = await idle(cache, now, now + 24 * 60 * minute);
  assert.equal(await guard.shouldRun(now + 59 * minute), false);
  assert.equal(await guard.shouldRun(now + 60 * minute), true);
  assert.equal(await guard.shouldRun(now - 1), true, 'clock reversal must not suppress work');
});

test('maintenance only records success and its deadline is not extended by intermediate scans', async () => {
  const guard = new ScheduledWorkCache(memory());
  let runs = 0;
  const run = async () => ++runs;
  await guard.maintenanceDue('regular-trainings', 60 * minute, run, now);
  await guard.maintenanceDue('regular-trainings', 60 * minute, run, now + 45 * minute);
  assert.equal(runs, 1);
  assert.equal(await guard.nextMaintenanceAt('regular-trainings', 60 * minute, now + 45 * minute), now + 60 * minute);
  await guard.maintenanceDue('regular-trainings', 60 * minute, run, now + 60 * minute);
  assert.equal(runs, 2);
  await assert.rejects(guard.maintenanceDue('failed', minute, async () => { throw Error('retry'); }, now));
  await guard.maintenanceDue('failed', minute, run, now + 1);
  assert.equal(runs, 3);
});

test('SDK in-memory fallback cannot suppress work across Vercel instances', t => {
  const key = Symbol.for('@vercel/request-context');
  const previous = globalThis[key];
  const previousVercel = process.env.VERCEL;
  const previousDisable = process.env.NEON_IDLE_GUARD_DISABLED;
  const transportVariables = ['RUNTIME_CACHE_ENDPOINT', 'RUNTIME_CACHE_HEADERS', 'RUNTIME_CACHE_DISABLE_BUILD_CACHE'];
  const transportValues = transportVariables.map(key => process.env[key]);
  t.after(() => {
    if (previous === undefined) delete globalThis[key]; else globalThis[key] = previous;
    if (previousVercel === undefined) delete process.env.VERCEL; else process.env.VERCEL = previousVercel;
    if (previousDisable === undefined) delete process.env.NEON_IDLE_GUARD_DISABLED; else process.env.NEON_IDLE_GUARD_DISABLED = previousDisable;
    transportVariables.forEach((key, index) => {
      if (transportValues[index] === undefined) delete process.env[key]; else process.env[key] = transportValues[index];
    });
  });
  process.env.VERCEL = '1';
  delete process.env.NEON_IDLE_GUARD_DISABLED;
  transportVariables.forEach(key => delete process.env[key]);
  delete globalThis[key];
  assert.equal(sharedRuntimeCacheAvailable(), false);
  process.env.RUNTIME_CACHE_ENDPOINT = 'https://cache.example.invalid/';
  process.env.RUNTIME_CACHE_HEADERS = '{}';
  assert.equal(sharedRuntimeCacheAvailable(), true);
  process.env.RUNTIME_CACHE_DISABLE_BUILD_CACHE = 'true';
  assert.equal(sharedRuntimeCacheAvailable(), false);
  delete process.env.RUNTIME_CACHE_DISABLE_BUILD_CACHE;
  process.env.RUNTIME_CACHE_HEADERS = 'invalid';
  assert.equal(sharedRuntimeCacheAvailable(), false);
  globalThis[key] = { get: () => ({ cache: memory() }) };
  assert.equal(sharedRuntimeCacheAvailable(), true);
  process.env.NEON_IDLE_GUARD_DISABLED = 'true';
  assert.equal(sharedRuntimeCacheAvailable(), false);
});

test('daily housekeeping never extends an expired idempotency response', async t => {
  const prismaModule = require('../dist/src/lib/prisma');
  const { idempotencyMiddleware } = require('../dist/src/middleware/idempotency');
  const original = prismaModule.prisma;
  t.after(() => { prismaModule.prisma = original; });
  let deleted = 0;
  let proceeded = 0;
  prismaModule.prisma = { idempotencyRecord: {
    findUnique: async () => ({ id: 'expired', expiresAt: new Date(0), requestHash: 'old response' }),
    deleteMany: async () => { deleted++; return { count: 1 }; },
  } };
  await idempotencyMiddleware({ method: 'POST', originalUrl: '/events', user: { id: 'user' },
    header: () => 'retry-key', body: {} }, { json: () => assert.fail('expired response replayed') },
  () => { proceeded++; });
  assert.equal(deleted, 1);
  assert.equal(proceeded, 1);
});

test('normal reads and session renewal do not add cache latency; scheduling and subscription writes invalidate', () => {
  for (const [method, path] of [['GET', '/matches/m1/ticker'], ['GET', '/events'],
    ['POST', '/auth/refresh'], ['POST', '/notifications/n1/read'], ['POST', '/notifications/read-all']]) {
    assert.equal(affectsScheduledWork(method, path), false, path);
  }
  for (const [method, path] of [['POST', '/events'], ['PATCH', '/organization/teams/1'],
    ['DELETE', '/events/1'], ['POST', '/notifications/settings/subscriptions']]) {
    assert.equal(affectsScheduledWork(method, path), true, path);
  }
});

test('middleware invalidates both before a write and after its response, including partial failures', async t => {
  const calls = [];
  t.mock.method(scheduledWorkCache, 'invalidate', async () => { calls.push('invalidate'); });
  const res = new EventEmitter();
  await invalidateScheduledWork({ method: 'PATCH', path: '/events/1' }, res, () => calls.push('write'));
  assert.deepEqual(calls, ['invalidate', 'write']);
  res.emit('finish');
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['invalidate', 'write', 'invalidate']);
});

test('slow cache invalidation cannot delay a save or a live goal', async t => {
  const releases = [];
  t.mock.method(scheduledWorkCache, 'invalidate', () => new Promise(resolve => releases.push(resolve)));
  let nextCalled = false;
  const res = new EventEmitter();
  invalidateScheduledWork({ method: 'POST', path: '/matches/1/ticker/events' }, res, () => { nextCalled = true; });
  assert.equal(nextCalled, true, 'goal processing must begin without waiting for the cache');
  res.emit('finish');
  releases.forEach(resolve => resolve());
  await new Promise(resolve => setImmediate(resolve));
});

test('an idle scheduled HTTP request checks its secret but does not invoke any database worker', async t => {
  const { processScheduledJobs } = require('../dist/src/controllers/cron.controller');
  const before = process.env.CRON_SECRET;
  process.env.CRON_SECRET = 'isolated-test-secret';
  t.after(() => { if (before === undefined) delete process.env.CRON_SECRET; else process.env.CRON_SECRET = before; });
  const shouldRun = t.mock.method(scheduledWorkCache, 'shouldRun', async () => false);
  t.mock.method(scheduledWorkCache, 'maintenanceDue', async () => assert.fail('idle path touched a DB worker'));
  const response = { code: 200, status(code) { this.code = code; return this; }, json(value) { this.body = value; return this; } };
  await processScheduledJobs({ headers: {} }, response);
  assert.equal(response.code, 401);
  assert.equal(shouldRun.mock.calls.length, 0);
  response.code = 200;
  await processScheduledJobs({ headers: { authorization: 'Bearer isolated-test-secret' } }, response);
  assert.deepEqual(response.body, { status: 'idle', databaseScan: false });
});
