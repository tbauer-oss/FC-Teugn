const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('biometric login uses a separate hashed and expiring device credential', () => {
  const schema = source('prisma/schema.prisma');
  const migration = source(
    'prisma/migrations/20260814170000_biometric_login/migration.sql',
  );
  const controller = source('src/controllers/auth.controller.ts');
  const biometricModel = schema.slice(
    schema.indexOf('model BiometricCredential'),
    schema.indexOf('model PasswordResetToken'),
  );

  assert.match(biometricModel, /tokenHash\s+String\s+@unique/);
  assert.match(biometricModel, /expiresAt\s+DateTime/);
  assert.doesNotMatch(biometricModel, /password/i);
  assert.match(migration, /BiometricCredential_tokenHash_key/);
  assert.match(controller, /randomBytes\(32\)\.toString\('base64url'\)/);
  assert.match(controller, /tokenHash: tokenHash\(credential\)/);
  assert.match(controller, /biometricCredentialLifetimeMs/);
});

test('biometric login issues a normal session and remains rate limited', () => {
  const controller = source('src/controllers/auth.controller.ts');
  const routes = source('src/routes/auth.routes.ts');
  const rateLimit = source('src/middleware/rate-limit.ts');

  assert.match(controller, /export async function biometricLogin/);
  assert.match(controller, /const tokens = await issueSession\(user, req\)/);
  assert.match(controller, /AccountStatus\.BLOCKED/);
  assert.match(routes, /router\.post\('\/biometric\/login', biometricLogin\)/);
  assert.match(
    routes,
    /'\/biometric\/enroll',[\s\S]*requireAuth,[\s\S]*requireApproved,[\s\S]*sensitiveActionRateLimit/,
  );
  assert.match(rateLimit, /'\/biometric\/login'/);
  assert.match(rateLimit, /req\.body\?\.credential/);
});

test('password reset, password change and logout-all revoke biometric access', () => {
  const controller = source('src/controllers/auth.controller.ts');
  const revocations = controller.match(/biometricCredential\.updateMany/g) ?? [];

  assert.ok(revocations.length >= 3);
  assert.match(controller, /PASSWORD_RESET_COMPLETED/);
  assert.match(controller, /PASSWORD_CHANGED_BY_USER/);
  assert.match(controller, /export async function logoutAll/);
});
