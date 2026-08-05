const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const { asyncRouter } = require('../dist/src/middleware/async-handler.js');

test('async router forwards rejected promises without waiting for a client timeout', async (t) => {
  const app = express();
  const router = asyncRouter();
  router.get('/database', async () => {
    throw new Error('database unavailable');
  });
  app.use(router);
  app.use((error, _request, response, _next) => {
    response.status(503).json({ message: error.message });
  });

  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => server.close());
  const address = server.address();
  assert.notEqual(address, null);
  assert.equal(typeof address, 'object');

  const response = await fetch(
    `http://127.0.0.1:${address.port}/database`,
  );
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    message: 'database unavailable',
  });
});
