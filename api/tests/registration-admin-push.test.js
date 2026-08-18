const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  pendingRegistrationNotification,
} = require('../dist/src/services/registration-notification.service');
const {
  externalPushPreview,
} = require('../dist/src/services/notification.service');

test('pending registration notification opens approvals without child data', () => {
  const notification = pendingRegistrationNotification({
    registrationRequestId: 'request-1',
    applicantName: 'Max Mustermann',
  });

  assert.equal(notification.category, 'REGISTRATION');
  assert.equal(notification.title, 'Neue Registrierung wartet auf Freigabe');
  assert.equal(
    notification.body,
    'Max Mustermann hat sich registriert und wartet auf deine Prüfung.',
  );
  assert.equal(notification.actionUrl, '/trainer/approvals');
  assert.equal(notification.entityType, 'RegistrationRequest');
  assert.equal(notification.entityId, 'request-1');
  assert.equal(notification.dedupeKey, 'registration-pending:request-1');
  assert.equal(notification.forcePush, true);
  assert.equal(notification.forceInApp, true);
  assert.doesNotMatch(notification.body, /Kind|child/i);
  assert.deepEqual(externalPushPreview(notification), {
    title: 'Neue Registrierung wartet auf Freigabe',
    body: 'Max Mustermann hat sich registriert und wartet auf deine Prüfung.',
  });
});

test('only approved system administrators receive new registration alerts', () => {
  const service = fs.readFileSync(
    path.join(
      __dirname,
      '../src/services/registration-notification.service.ts',
    ),
    'utf8',
  );
  const controller = fs.readFileSync(
    path.join(__dirname, '../src/controllers/auth.controller.ts'),
    'utf8',
  );

  assert.match(service, /role:\s*Role\.SUPER_ADMIN/);
  assert.match(service, /status:\s*AccountStatus\.APPROVED/);
  assert.match(controller, /user\.status === AccountStatus\.PENDING/);
  assert.match(controller, /notifyPendingRegistrationAdministrators/);
  assert.match(controller, /\.catch\(\(error\) =>/);
});
