const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const read = (relativePath) =>
  fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');

const schema = read('prisma/schema.prisma');
const migration = read(
  'prisma/migrations/20260807123000_carpool_needs/migration.sql',
);
const events = read('src/controllers/events.controller.ts');
const eventRoutes = read('src/routes/events.routes.ts');
const players = read('src/controllers/players.controller.ts');
const admin = read('src/controllers/admin.controller.ts');
const adminRoutes = read('src/routes/admin.routes.ts');

test('carpool needs support several own children and remain team scoped', () => {
  assert.match(schema, /model CarpoolNeed/);
  assert.match(schema, /@@unique\(\[eventId, playerId\]\)/);
  assert.match(migration, /CarpoolNeed_eventId_playerId_key/);
  assert.match(eventRoutes, /carpool-needs/);
  assert.match(events, /parseStringList\(req\.body\.playerIds\)/);
  assert.match(events, /const allowed = await ownPlayerIds\(user\)/);
  assert.match(events, /teamId: \{ in: targetTeamIds \}/);
});

test('clean sheets are counted only for eligible players in completed games', () => {
  assert.match(players, /MatchStatus\.FINISHED/);
  assert.match(players, /MatchStatus\.RECORDED/);
  assert.match(players, /conceded === 0/);
  assert.match(players, /statistic\.appeared/);
  assert.match(players, /cleanSheetEligible/);
  assert.match(players, /TW\|TORHÜTER\|TORWART\|IV\|LV\|RV/);
});

test('system admin can generate an audited expiring one-time reset link', () => {
  assert.match(adminRoutes, /password-reset-link/);
  assert.match(adminRoutes, /requireRoles\(\[Role\.SUPER_ADMIN\]\)/);
  assert.match(admin, /randomBytes\(32\)/);
  assert.match(admin, /60 \* 60 \* 1000/);
  assert.match(admin, /PASSWORD_RESET_LINK_CREATED_BY_ADMIN/);
  assert.match(admin, /passwordResetToken\.deleteMany/);
});
