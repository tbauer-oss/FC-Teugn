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
    /where:\s*\{\s*id:\s*req\.params\.id,\s*userId:\s*req\.user!\.id\s*\}/,
  );
  assert.match(controller, /action:\s*'NOTIFICATION_DELETED'/);
});
