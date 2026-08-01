const assert = require('node:assert/strict');
const test = require('node:test');

const {
  parseFirebaseServiceAccount,
} = require('../dist/src/lib/firebase-admin');
const {
  androidPushMessage,
} = require('../dist/src/services/notification.service');
const {
  validPushEndpoint,
} = require('../dist/src/controllers/notifications.controller');

test('Firebase service account JSON is parsed without losing the private-key lines', () => {
  const account = parseFirebaseServiceAccount(JSON.stringify({
    project_id: 'fc-teugn',
    client_email: 'push@fc-teugn.iam.gserviceaccount.com',
    private_key: '-----BEGIN PRIVATE KEY-----\\nsecret\\n-----END PRIVATE KEY-----\\n',
  }));
  assert.equal(account.projectId, 'fc-teugn');
  assert.equal(account.clientEmail, 'push@fc-teugn.iam.gserviceaccount.com');
  assert.match(account.privateKey, /\nsecret\n/);
});

test('incomplete Firebase service account configuration is rejected', () => {
  assert.throws(
    () => parseFirebaseServiceAccount('{"project_id":"fc-teugn"}'),
    /incomplete/,
  );
});

test('Android FCM tokens and Web Push URLs use platform-specific validation', () => {
  assert.equal(
    validPushEndpoint('ANDROID', 'fcm-token_1234567890:abcdefghi'),
    true,
  );
  assert.equal(validPushEndpoint('ANDROID', 'https://not-a-token.invalid/a'), false);
  assert.equal(validPushEndpoint('WEB', 'https://push.example.test/abc'), true);
  assert.equal(validPushEndpoint('WEB', 'http://push.example.test/abc'), false);
});

test('Android notification uses the app channel and retains navigation data', () => {
  const message = androidPushMessage('token', {
    id: 'notification-1',
    title: 'Training geändert',
    body: 'Beginn ist jetzt um 18:00 Uhr.',
    actionUrl: '/messages/announcement-1',
    entityType: 'ANNOUNCEMENT',
    entityId: 'announcement-1',
  });
  assert.equal(message.android.notification.channelId, 'fc_teugn_important');
  assert.equal(message.data.actionUrl, '/messages/announcement-1');
  assert.equal(message.data.notificationId, 'notification-1');
  assert.equal(message.android.priority, 'high');
});
