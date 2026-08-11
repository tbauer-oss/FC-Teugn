const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = (relativePath) =>
  fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');

const {
  explicitlyBlocksTeamPhoto,
  hasActiveConsent,
  medicalProfileForConsent,
} = require(
  '../dist/src/services/consent-policy',
);

function consent(type, selections, overrides = {}) {
  return {
    type,
    status: 'GRANTED',
    expiresAt: null,
    evidence: [{
      action: 'GRANTED',
      statement: { selections },
      createdAt: new Date(),
    }],
    ...overrides,
  };
}

test('photo use requires a current signed scope for the protected app', () => {
  assert.equal(hasActiveConsent([consent('PHOTO', ['APP_INTERNAL'])], 'PHOTO', 'APP_INTERNAL'), true);
  assert.equal(hasActiveConsent([consent('PHOTO', ['PRESS'])], 'PHOTO', 'APP_INTERNAL'), false);
  assert.equal(hasActiveConsent([consent('PHOTO', ['APP_INTERNAL'], { status: 'REVOKED' })], 'PHOTO', 'APP_INTERNAL'), false);
  assert.equal(hasActiveConsent([consent('PHOTO', ['APP_INTERNAL'], { expiresAt: new Date(0) })], 'PHOTO', 'APP_INTERNAL'), false);
});

test('team photo responses distinguish deletion from consent-based hiding', () => {
  const organization = read('src/controllers/organization.controller.ts');
  assert.match(organization, /photoStatus:\s*\{/);
  assert.match(organization, /stored:\s*Boolean\(team\.photoAsset\)/);
  assert.match(organization, /blockedByConsent/);
  assert.match(organization, /blockingConsentCount/);
  assert.match(organization, /photoUrl:\s*teamPhotoVisible/);
});

test('team photo is blocked only by a documented refusal or restriction', () => {
  assert.equal(explicitlyBlocksTeamPhoto([]), false);
  assert.equal(
    explicitlyBlocksTeamPhoto([
      { type: 'TEAM_PHOTO', status: 'PENDING', expiresAt: null, evidence: [] },
    ]),
    false,
  );
  assert.equal(
    explicitlyBlocksTeamPhoto([
      { type: 'TEAM_PHOTO', status: 'EXPIRED', expiresAt: new Date(0), evidence: [] },
    ]),
    false,
  );
  assert.equal(
    explicitlyBlocksTeamPhoto([
      { type: 'TEAM_PHOTO', status: 'REVOKED', expiresAt: null, evidence: [] },
    ]),
    true,
  );
  assert.equal(
    explicitlyBlocksTeamPhoto([consent('TEAM_PHOTO', ['PRESS'])]),
    true,
  );
  assert.equal(
    explicitlyBlocksTeamPhoto([consent('TEAM_PHOTO', ['APP_INTERNAL'])]),
    false,
  );
});

test('guardians can explicitly decline an open consent with evidence', () => {
  const routes = read('src/routes/players.routes.ts');
  const controller = read('src/controllers/player-consents.controller.ts');
  assert.match(routes, /consents\/:type\/decline/);
  assert.match(controller, /PLAYER_CONSENT_DECLINED/);
  assert.match(controller, /decision:\s*'DECLINED'/);
  assert.match(controller, /guardianAuthorityConfirmed/);
});

test('medical fields are reduced to the explicitly selected scope', () => {
  const profile = {
    allergies: 'Nüsse',
    medications: 'Spray',
    conditions: 'Asthma',
    physicianName: 'Arzt',
    physicianPhone: '123',
    emergencyNotes: 'Hinweis',
  };
  const result = medicalProfileForConsent(
    profile,
    [consent('MEDICAL_DATA', ['ALLERGIES', 'AUTHORIZED_STAFF'])],
    true,
  );
  assert.equal(result.allergies, 'Nüsse');
  assert.equal(result.medications, null);
  assert.equal(result.conditions, null);
  assert.equal(result.physicianPhone, null);
});

test('legacy status endpoint cannot create unsigned grants or undocumented revocations', () => {
  const players = read('src/controllers/players.controller.ts');
  assert.match(players, /DIGITAL_CONSENT_REQUIRED/);
  assert.match(players, /DOCUMENTED_REVOCATION_REQUIRED/);
  assert.match(players, /MEDICAL_CONSENT_REQUIRED/);
});

test('API hardening prevents storage and sensitive error dumps', () => {
  const headers = read('src/middleware/security-headers.ts');
  const errors = read('src/middleware/errorHandler.ts');
  const jwt = read('src/lib/jwt.ts');
  assert.match(headers, /private, no-store/);
  assert.match(headers, /Content-Security-Policy/);
  assert.match(errors, /requestId/);
  assert.doesNotMatch(errors, /console\.error\(err\)/);
  assert.doesNotMatch(jwt, /'access_secret'/);
  assert.doesNotMatch(jwt, /'refresh_secret'/);
  assert.match(jwt, /must be configured in production/);
});

test('registration separates notice, agreement and optional consent', () => {
  const schema = read('prisma/schema.prisma');
  const auth = read('src/controllers/auth.controller.ts');
  assert.match(schema, /enum ConsentRecordKind/);
  assert.match(auth, /ConsentRecordKind\.ACKNOWLEDGEMENT/);
  assert.match(auth, /ConsentRecordKind\.AGREEMENT/);
  assert.match(auth, /ConsentRecordKind\.CONSENT/);
});

test('all core data-subject rights are available as audited requests', () => {
  const schema = read('prisma/schema.prisma');
  const routes = read('src/routes/auth.routes.ts');
  for (const right of [
    'ACCESS',
    'PORTABILITY',
    'RECTIFICATION',
    'RESTRICTION',
    'OBJECTION',
    'CONSENT_WITHDRAWAL',
    'ERASURE',
  ]) {
    assert.match(schema, new RegExp(`\\b${right}\\b`));
  }
  assert.match(routes, /post\('\/privacy\/requests'/);
  assert.match(routes, /post\('\/privacy\/erasure-requests'/);
});

test('operational retention excludes domain and consent evidence', () => {
  const retention = read('src/services/privacy-retention.service.ts');
  assert.match(retention, /idempotencyRecord\.deleteMany/);
  assert.match(retention, /passwordResetToken\.deleteMany/);
  assert.match(retention, /refreshToken\.deleteMany/);
  assert.match(retention, /pushSubscription\.deleteMany/);
  assert.match(retention, /notification\.deleteMany/);
  assert.doesNotMatch(retention, /auditLog\.deleteMany/);
  assert.doesNotMatch(retention, /playerConsentEvidence\.deleteMany/);
});
