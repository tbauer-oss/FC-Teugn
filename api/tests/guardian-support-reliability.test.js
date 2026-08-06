const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('technical support metadata is reduced to a safe whitelist', () => {
  const { sanitizeTechnicalMetadata } = require('../dist/src/controllers/support.controller');
  const result = sanitizeTechnicalMetadata({
    appVersion: '1.5.41',
    platform: 'android',
    route: '/family',
    token: 'must-not-leak',
    password: 'must-not-leak',
    nested: { secret: true },
  });

  assert.deepEqual(result, {
    appVersion: '1.5.41',
    platform: 'android',
    route: '/family',
  });
});

test('support creation and replies honor the optional push selection', () => {
  const support = source('src/controllers/support.controller.ts');
  assert.match(support, /support-created:[\s\S]*pushEnabled:/);
  assert.match(support, /support-reply:[\s\S]*pushEnabled:/);
  assert.match(support, /internal/);
});

test('family response endpoint is role-independent and auditable', () => {
  const events = source('src/controllers/events.controller.ts');
  const routes = source('src/routes/events.routes.ts');
  assert.match(routes, /personal-responses\/list/);
  assert.match(events, /PERSONAL_GUARDIAN/);
  assert.match(events, /parentPlayerLink/);
  assert.match(events, /ATTENDANCE_RESPONSE_CHANGED/);
  assert.match(events, /responderRelationship/);
});

test('mandatory lifecycle notifications override disabled push preferences', () => {
  const notifications = source('src/services/notification.service.ts');
  const matches = source('src/controllers/matches.controller.ts');
  assert.match(notifications, /input\.forcePush\s*\|\|/);
  assert.match(matches, /MATCH_CANCELLED[\s\S]*forcePush:\s*true/);
  assert.match(matches, /MATCH_DELETED/);
});
