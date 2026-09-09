const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { runtimeDeferredWork, deferWork, beforeResponseEnd } = require('../dist/src/middleware/runtime-deferred-work');

test('Cloud Run request drains registered work before ending the response', async () => {
  const app = express();
  let completed = false;
  let finalizerDone = false;
  let nestedDone = false;

  app.use(runtimeDeferredWork);
  app.get('/deferred', (_req, res) => {
    beforeResponseEnd(async () => { finalizerDone = true; });
    beforeResponseEnd(() => { throw Error('isolated finalizer failure'); });
    deferWork(async () => {
      await new Promise(resolve => setTimeout(resolve, 5));
      deferWork(async () => {
        await new Promise(resolve => setTimeout(resolve, 40));
        nestedDone = true;
      });
    });
    deferWork(
      new Promise((resolve) => {
        setTimeout(() => {
          completed = true;
          resolve();
        }, 25);
      }),
    );

    res.json({ ok: true });
  });

  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });

  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(`http://127.0.0.1:${address.port}/deferred`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
    assert.equal(finalizerDone, true);
    assert.equal(nestedDone, true);
    assert.equal(completed, true, 'deferred work must settle before the response ends');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
