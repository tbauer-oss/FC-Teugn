const test = require('node:test');
const assert = require('node:assert/strict');
const prismaModule = require('../dist/src/lib/prisma');
const { objectStorage } = require('../dist/src/services/object-storage');
const { retryFileDeletions } = require('../dist/src/services/file-deletion.service');

test('failed physical deletion keeps a durable tombstone and succeeds on retry', async t => {
  let marked = false;
  const original = prismaModule.prisma;
  prismaModule.prisma = { fileAsset: { findMany: async () => [], updateMany: async () => ({ count: 1 }) } };
  const prisma = prismaModule.prisma;
  t.after(() => { prismaModule.prisma = original; });
  t.mock.method(prisma.fileAsset, 'findMany', async args => {
    assert.deepEqual(args.where, { deletedAt: { not: null }, storageDeletedAt: null });
    return marked ? [] : [{ id: 'deleted', pathname: 'private-test' }];
  });
  t.mock.method(prisma.fileAsset, 'updateMany', async () => { marked = true; return { count: 1 }; });
  let attempts = 0;
  t.mock.method(objectStorage, 'delete', async () => {
    if (++attempts === 1) throw Error('temporary failure');
  });
  assert.deepEqual(await retryFileDeletions(), { removed: 0, pending: 1 });
  assert.equal(marked, false);
  assert.deepEqual(await retryFileDeletions(), { removed: 1, pending: 0 });
  assert.deepEqual(await retryFileDeletions(), { removed: 0, pending: 0 });
  assert.equal(attempts, 2);
});
