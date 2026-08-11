const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const read = (relativePath) =>
  fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');

const events = read('src/controllers/events.controller.ts');
const reminders = read('src/services/reminder.service.ts');
const auth = read('src/controllers/auth.controller.ts');
const authRoutes = read('src/routes/auth.routes.ts');
const schema = read('prisma/schema.prisma');

test('all newly created matches default to a 24 hour server reminder', () => {
  assert.match(events, /type === EventType\.MATCH\s*\? \[1440\]/);
  assert.match(events, /reminderPushEnabled: body\.reminderPushEnabled !== false/);
  assert.match(reminders, /job\.event\.type === EventType\.MATCH/);
  assert.match(reminders, /`\/matches\/\$\{job\.eventId\}`/);
});

test('editing a match reschedules or removes its reminder immediately', () => {
  assert.match(events, /reminderMinutes == null/);
  assert.match(events, /await syncScheduledRemindersForEvent\(event\.id\)/);
});

test('password reset uses hashed expiring one-time tokens and push delivery', () => {
  assert.match(schema, /model PasswordResetToken/);
  assert.match(schema, /tokenHash\s+String\s+@unique/);
  assert.match(schema, /expiresAt\s+DateTime/);
  assert.match(authRoutes, /password-reset\/request/);
  assert.match(authRoutes, /password-reset\/exchange/);
  assert.match(authRoutes, /password-reset\/confirm/);
  assert.match(auth, /randomBytes\(32\)/);
  assert.match(auth, /tokenHash: tokenHash\(token\)/);
  assert.match(auth, /forcePush: true/);
  assert.match(auth, /reset-password\?requestId=/);
  assert.doesNotMatch(auth, /reset-password\?token=/);
  assert.match(auth, /claimedBySubscriptionId/);
  assert.match(auth, /deviceEndpoint/);
  assert.match(auth, /expiresAt: \{ gt: now \}/);
  assert.match(auth, /refreshToken\.updateMany/);
});

test('reset request does not disclose whether an account exists', () => {
  assert.match(auth, /passwordResetResponse/);
  assert.match(auth, /return res\.status\(202\)\.json\(passwordResetResponse\)/);
});
