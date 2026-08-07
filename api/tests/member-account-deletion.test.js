const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const controller = fs.readFileSync(
  path.join(root, 'src/controllers/admin.controller.ts'),
  'utf8',
);
const routes = fs.readFileSync(
  path.join(root, 'src/routes/admin.routes.ts'),
  'utf8',
);
const schema = fs.readFileSync(path.join(root, 'prisma/schema.prisma'), 'utf8');

test('account deletion is restricted to system administrators', () => {
  assert.match(
    routes,
    /router\.delete\([\s\S]*?'\/members\/:id'[\s\S]*?requireRoles\(\[Role\.SUPER_ADMIN\]\)[\s\S]*?deleteMemberAccount/,
  );
});

test('account deletion protects the acting and final system admin accounts', () => {
  assert.match(controller, /target\.id === actor\.id/);
  assert.match(controller, /remainingSuperAdmins === 0/);
  assert.match(controller, /letzte aktive Systemadministrationskonto/);
});

test('account deletion revokes access, removes assignments and anonymizes the record', () => {
  assert.match(schema, /accountDeletedAt\s+DateTime\?/);
  assert.match(controller, /refreshToken\.deleteMany/);
  assert.match(controller, /pushSubscription\.deleteMany/);
  assert.match(controller, /teamMembership\.deleteMany/);
  assert.match(controller, /parentPlayerLink\.deleteMany/);
  assert.match(controller, /eventParticipant\.deleteMany/);
  assert.match(controller, /scheduledReminder\.deleteMany/);
  assert.match(controller, /carpoolOffer\.deleteMany/);
  assert.match(controller, /player\.updateMany/);
  assert.match(controller, /name: 'Gelöschtes Konto'/);
  assert.match(controller, /status: AccountStatus\.ARCHIVED/);
  assert.match(controller, /action: 'USER_ACCOUNT_DELETED'/);
  assert.match(controller, /accountDeletedAt: null/);
});
