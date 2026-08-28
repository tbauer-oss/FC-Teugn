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
const pushActivationEmail = fs.readFileSync(
  path.join(root, 'src/services/push-activation-email.service.ts'),
  'utf8',
);

test('account deletion is restricted to system administrators', () => {
  assert.match(
    routes,
    /router\.delete\([\s\S]*?'\/members\/:id'[\s\S]*?requireRoles\(\[Role\.SUPER_ADMIN\]\)[\s\S]*?deleteMemberAccount/,
  );
});

test('guardian assignments can only be removed by system administrators', () => {
  assert.match(
    routes,
    /router\.delete\([\s\S]*?'\/parent-player-links\/:parentId\/:playerId'[\s\S]*?requireRoles\(\[Role\.SUPER_ADMIN\]\)[\s\S]*?removeParentPlayer/,
  );
  assert.match(controller, /parentPlayerLink\.findUnique/);
  assert.match(controller, /parentPlayerLink\.delete/);
  assert.match(controller, /GUARDIAN_ASSIGNMENT_REMOVED/);
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

test('approved members without a push device can receive activation instructions by email', () => {
  assert.match(
    routes,
    /router\.post\([\s\S]*?'\/members\/:id\/push-activation-reminder'[\s\S]*?sendMemberPushActivationReminder/,
  );
  assert.match(controller, /status !== AccountStatus\.APPROVED/);
  assert.match(controller, /pushSubscriptions:\s*\{\s*where:\s*\{\s*isActive:\s*true/);
  assert.match(controller, /sendPushActivationEmail/);
  assert.match(controller, /PUSH_ACTIVATION_EMAIL_SENT_BY_STAFF/);
  assert.match(pushActivationEmail, /RESEND_API_KEY/);
  assert.match(pushActivationEmail, /Android/);
  assert.match(pushActivationEmail, /iPhone/);
  assert.match(pushActivationEmail, /Web/);
});
