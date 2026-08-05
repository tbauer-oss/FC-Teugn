const test = require('node:test');
const assert = require('node:assert/strict');

const {
  serverlessDatabaseUrl,
} = require('../dist/src/lib/prisma.js');

test('serverless Prisma instances use a bounded production connection pool', () => {
  const result = new URL(serverlessDatabaseUrl(
    'postgresql://user:secret@db.example.test:5432/fc_teugn',
    true,
  ));

  assert.equal(result.searchParams.get('connection_limit'), '1');
  assert.equal(result.searchParams.get('pool_timeout'), '10');
  assert.equal(result.searchParams.get('connect_timeout'), '10');
});

test('explicit database pool settings and local development URLs are preserved', () => {
  const configured =
    'postgresql://user:secret@db.example.test/fc_teugn?connection_limit=4&pool_timeout=20';
  const productionResult = new URL(serverlessDatabaseUrl(configured, true));

  assert.equal(productionResult.searchParams.get('connection_limit'), '4');
  assert.equal(productionResult.searchParams.get('pool_timeout'), '20');
  assert.equal(serverlessDatabaseUrl(configured, false), configured);
});
