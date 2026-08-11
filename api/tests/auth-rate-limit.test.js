const assert = require('node:assert/strict');
const test = require('node:test');

const {
  authRateLimit,
} = require('../dist/src/middleware/rate-limit.js');

function loginAttempt({ email, ip }) {
  const headers = {};
  let statusCode = 200;
  let body = null;
  let continued = false;
  const response = {
    setHeader(name, value) {
      headers[name] = value;
    },
    status(value) {
      statusCode = value;
      return this;
    },
    json(value) {
      body = value;
      return this;
    },
  };
  authRateLimit(
    {
      method: 'POST',
      path: '/login',
      ip,
      body: { email },
    },
    response,
    () => {
      continued = true;
    },
  );
  return { headers, statusCode, body, continued };
}

test('shared mobile IP does not combine login attempts of different accounts', () => {
  const now = Date.now();
  const ip = `198.51.100.${now % 200}`;
  for (let index = 0; index < 25; index += 1) {
    const result = loginAttempt({
      email: `mobile-user-${index}-${now}@example.invalid`,
      ip,
    });
    assert.equal(result.continued, true);
    assert.equal(result.statusCode, 200);
  }
});

test('one credential remains protected across changing source addresses', () => {
  const email = `protected-${Date.now()}@example.invalid`;
  for (let index = 0; index < 20; index += 1) {
    assert.equal(
      loginAttempt({ email, ip: `203.0.113.${index + 1}` }).continued,
      true,
    );
  }
  const blocked = loginAttempt({ email, ip: '203.0.113.250' });
  assert.equal(blocked.continued, false);
  assert.equal(blocked.statusCode, 429);
  assert.equal(blocked.body.code, 'AUTH_RATE_LIMITED');
  assert.ok(blocked.body.retryAfterSeconds > 0);
});
