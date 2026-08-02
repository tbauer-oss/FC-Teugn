const assert = require('node:assert/strict');
const test = require('node:test');

const {
  parseFirebaseServiceAccount,
} = require('../dist/src/lib/firebase-admin');
const {
  androidPushMessage,
  summarizePushDeliveries,
} = require('../dist/src/services/notification.service');
const {
  pushDeviceHealth,
  pushDeviceMayAutoReactivate,
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
  assert.equal(message.android.notification.icon, 'ic_stat_fc_teugn');
  assert.match(message.android.notification.imageUrl, /fc_teugn_logo\.png$/);
  assert.equal(message.data.actionUrl, '/messages/announcement-1');
  assert.equal(message.data.notificationId, 'notification-1');
  assert.equal(message.android.priority, 'high');
});

test('admin push test summary exposes delivery and platform diagnostics', () => {
  const result = summarizePushDeliveries([
    {
      status: 'SENT',
      errorCode: null,
      subscription: { platform: 'WEB' },
    },
    {
      status: 'FAILED',
      errorCode: 'HTTP_403',
      subscription: { platform: 'WEB' },
    },
    {
      status: 'SENT',
      errorCode: null,
      subscription: { platform: 'ANDROID' },
    },
  ]);
  assert.equal(result.subscriptions, 3);
  assert.equal(result.sent, 2);
  assert.equal(result.failed, 1);
  assert.equal(result.byPlatform.WEB.total, 2);
  assert.equal(result.byPlatform.ANDROID.sent, 1);
  assert.deepEqual(result.errors, [{ code: 'HTTP_403', count: 1 }]);
});

test('global push test route remains restricted to the system administrator', () => {
  const routes = require('node:fs').readFileSync(
    require('node:path').join(__dirname, '../src/routes/notifications.routes.ts'),
    'utf8',
  );
  assert.match(
    routes,
    /router\.post\('\/admin\/test-push', requireRoles\(\[Role\.SUPER_ADMIN\]\)/,
  );
});

test('administratively disabled devices cannot reactivate on app startup', () => {
  assert.equal(pushDeviceMayAutoReactivate(null), true);
  assert.equal(pushDeviceMayAutoReactivate(new Date('2026-08-01T10:00:00Z')), false);
});

test('device health highlights stale and disabled registrations', () => {
  const now = new Date('2026-08-02T10:00:00Z');
  assert.equal(
    pushDeviceHealth(true, new Date('2026-08-01T10:00:00Z'), now),
    'ACTIVE',
  );
  assert.equal(
    pushDeviceHealth(true, new Date('2026-05-01T10:00:00Z'), now),
    'STALE',
  );
  assert.equal(
    pushDeviceHealth(false, new Date('2026-08-01T10:00:00Z'), now),
    'DISABLED',
  );
});

test('system-wide device management remains restricted to the system administrator', () => {
  const routes = require('node:fs').readFileSync(
    require('node:path').join(__dirname, '../src/routes/notifications.routes.ts'),
    'utf8',
  );
  assert.match(
    routes,
    /router\.get\('\/admin\/devices', requireRoles\(\[Role\.SUPER_ADMIN\]\)/,
  );
  assert.match(
    routes,
    /'\/admin\/devices\/:id',[\s\S]*requireRoles\(\[Role\.SUPER_ADMIN\]\),[\s\S]*setAdminPushDeviceState/,
  );
  assert.match(
    routes,
    /'\/admin\/devices\/:id',[\s\S]*requireRoles\(\[Role\.SUPER_ADMIN\]\),[\s\S]*deleteAdminPushDevice/,
  );
});
