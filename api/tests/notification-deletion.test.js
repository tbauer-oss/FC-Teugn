const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('staff notification deletion is role protected and user scoped', () => {
  const routes = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'routes', 'notifications.routes.ts'),
    'utf8',
  );
  const controller = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'controllers', 'notifications.controller.ts'),
    'utf8',
  );

  assert.match(
    routes,
    /router\.delete\([\s\S]*?'\/:id'[\s\S]*?Role\.SUPER_ADMIN[\s\S]*?Role\.COACH[\s\S]*?Role\.TRAINER[\s\S]*?deleteNotification/,
  );
  assert.match(
    controller,
    /deleteNotification[\s\S]*?id:\s*req\.params\.id[\s\S]*?userId:\s*req\.user!\.id[\s\S]*?standardNotificationScope/,
  );
  assert.match(controller, /action:\s*'NOTIFICATION_DELETED'/);
});

test('bulk deletion removes only read notifications of the current user', () => {
  const routes = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'routes', 'notifications.routes.ts'),
    'utf8',
  );
  const controller = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'controllers', 'notifications.controller.ts'),
    'utf8',
  );

  assert.match(routes, /router\.delete\('\/read',\s*deleteReadNotifications\)/);
  assert.ok(
    routes.indexOf("router.delete('/read'") < routes.indexOf("'/:id'"),
    'the static bulk route must be registered before the dynamic id route',
  );
  assert.match(
    controller,
    /deleteReadNotifications[\s\S]*?userId:\s*req\.user!\.id[\s\S]*?readAt:\s*\{\s*not:\s*null\s*\}/,
  );
  assert.match(controller, /action:\s*'READ_NOTIFICATIONS_BULK_DELETED'/);
});

test('direct contacts are isolated from notification list, read and delete operations', () => {
  const controller = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'controllers', 'notifications.controller.ts'),
    'utf8',
  );
  const scope = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'services', 'notification-scope.service.ts'),
    'utf8',
  );
  const communications = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'controllers', 'communications.controller.ts'),
    'utf8',
  );

  assert.match(scope, /familyContactEntityPrefix\s*=\s*'FamilyContact:';/);
  assert.match(scope, /entityType:\s*null/);
  assert.match(scope, /not:\s*\{\s*startsWith:\s*familyContactEntityPrefix/);
  assert.equal(
    (controller.match(/standardNotificationScope/g) ?? []).length,
    6,
    'import plus list, single read, read-all, bulk delete and single delete stay protected',
  );
  assert.match(communications, /entityType:\s*\{\s*startsWith:\s*familyContactEntityPrefix/);
});
