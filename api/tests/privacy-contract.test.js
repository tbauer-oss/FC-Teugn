const test = require('node:test');
const assert = require('node:assert/strict');

const openapi = require('../openapi.json');
const {
  anonymizedUserData,
} = require('../dist/src/controllers/privacy.controller');

test('OpenAPI contract exposes security-critical production flows', () => {
  assert.equal(openapi.openapi, '3.1.0');
  for (const path of [
    '/auth/register',
    '/auth/login',
    '/auth/privacy/export',
    '/auth/privacy/erasure-requests',
    '/organization/context',
    '/organization/teams/{id}',
    '/organization/teams/{id}/default-lineup',
    '/players/{id}',
    '/players/consent-templates',
    '/players/consent-templates/{type}/pdf',
    '/players/{id}/consents/{type}/sign',
    '/players/{id}/consents/{type}/revoke',
    '/players/{id}/consents/{type}/evidence/{evidenceId}/pdf',
    '/events/{id}/attendance',
    '/events/{id}/emergency-access',
    '/matches/{id}/lineup',
    '/matches/{id}/ticker/events',
    '/matches/{id}/ticker/reset',
    '/admin/privacy-requests/{id}/complete-erasure',
  ]) {
    assert.ok(openapi.paths[path], `${path} fehlt im API-Vertrag`);
  }
  assert.deepEqual(
    openapi.components.securitySchemes.bearerAuth,
    { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
  );
});

test('account anonymization removes identifying fields and archives access', () => {
  const data = anonymizedUserData('user-123', 'irreversible-password-hash');
  assert.equal(data.email, 'deleted+user-123@anonymized.invalid');
  assert.equal(data.name, 'Gelöschtes Konto');
  assert.equal(data.firstName, null);
  assert.equal(data.lastName, null);
  assert.equal(data.phone, null);
  assert.equal(data.calendarToken, null);
  assert.equal(data.status, 'ARCHIVED');
  assert.equal(data.password, 'irreversible-password-hash');
});
