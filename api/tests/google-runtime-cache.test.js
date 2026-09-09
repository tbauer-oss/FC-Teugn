const test = require('node:test');
const assert = require('node:assert/strict');
const { GoogleRuntimeCache } = require('../dist/src/services/google-runtime-cache');
const firebase = require('../dist/src/lib/firebase-admin');

function fixture(t) {
  t.mock.method(firebase, 'firebaseAdminApp', () => ({}));
  const objects = new Map();
  let serial = 0;
  const error = code => Object.assign(new Error('storage'), { code });
  const storage = () => ({ bucket: () => ({ file: name => ({
    metadata: {},
    async getMetadata() {
      if (!objects.has(name)) throw error(404);
      const item = objects.get(name);
      return [{ generation: item.generation, metadata: { ...item.metadata } }];
    },
    async download() {
      if (!objects.has(name)) throw error(404);
      return [Buffer.from(objects.get(name).data)];
    },
    async save(data, options) {
      const previous = objects.get(name);
      const expected = options.preconditionOpts?.ifGenerationMatch;
      if (expected !== undefined && String(expected) !== String(previous?.generation ?? 0)) throw error(412);
      const item = { data, generation: String(++serial), metadata: options.metadata?.metadata };
      objects.set(name, item);
      this.metadata = { generation: item.generation };
    },
    async delete(options) {
      if (options.ifGenerationMatch && objects.get(name)?.generation !== options.ifGenerationMatch) throw error(412);
      objects.delete(name);
    },
  }) }) });
  return { objects, cache: () => new GoogleRuntimeCache('test', 'test', storage) };
}

test('shared cache observes values across instances and expires stale records', async t => {
  const { cache } = fixture(t);
  const writer = cache(), reader = cache();
  assert.equal(await reader.get('plan'), null);
  await writer.set('plan', { nextDueAt: 42 }, { ttl: 60 });
  assert.deepEqual(await reader.get('plan'), { nextDueAt: 42 });
  await writer.set('plan', 'expired', { ttl: -1 });
  assert.equal(await reader.get('plan'), null);
});

test('concurrent scheduler instances cannot acquire the same generation lease', async t => {
  const { cache } = fixture(t);
  const releases = await Promise.all([cache().acquireLease('worker', 60000), cache().acquireLease('worker', 60000)]);
  assert.equal(releases.filter(Boolean).length, 1);
  await releases.find(Boolean)();
  assert.equal(typeof await cache().acquireLease('worker', 60000), 'function');
});

test('a delayed owner cannot release the lease of its successor', async t => {
  const { cache, objects } = fixture(t);
  const first = await cache().acquireLease('worker', 60000);
  objects.values().next().value.metadata.leaseExpiresAt = '0';
  const second = await cache().acquireLease('worker', 60000);
  assert.equal(typeof second, 'function');
  await first();
  assert.equal(await cache().acquireLease('worker', 60000), null);
  await second();
  assert.equal(objects.size, 0);
});
