const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { runtimeDeferredWork } = require('../dist/src/middleware/runtime-deferred-work');

test('Cloud Run request context drains waitUntil work before ending the response', async () => {
  const previousVercel = process.env.VERCEL;
  delete process.env.VERCEL;

  const app = express();
  let completed = false;

  app.use(runtimeDeferredWork);
  app.get('/deferred', (_req, res) => {
    const context = globalThis[Symbol.for('@vercel/request-context')]?.get?.();
    assert.ok(context, 'request context bridge should exist outside Vercel');

    context.waitUntil(
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
    assert.equal(completed, true, 'deferred work must settle before the response ends');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (previousVercel === undefined) delete process.env.VERCEL;
    else process.env.VERCEL = previousVercel;
  }
});
