const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const service = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'services', 'kit-laundry.service.ts'),
  'utf8',
);
const routes = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'routes', 'matches.routes.ts'),
  'utf8',
);
const cron = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'cron.controller.ts'),
  'utf8',
);
const schema = fs.readFileSync(
  path.join(__dirname, '..', 'prisma', 'schema.prisma'),
  'utf8',
);

test('kit laundry rotation only uses published nominated players and communicating guardians', () => {
  assert.match(service, /publishedAt: true/);
  assert.match(service, /where: \{ status: NominationStatus\.NOMINATED \}/);
  assert.match(service, /receivesCommunication: true/);
  assert.match(service, /parent: \{ status: AccountStatus\.APPROVED \}/);
  assert.match(service, /const key = guardianIds\.join\(':'\)/);
});

test('rotation is fair, supports manual selection and advances after decline', () => {
  assert.match(service, /leftStats\.count - rightStats\.count/);
  assert.match(service, /leftStats\.lastAt - rightStats\.lastAt/);
  assert.match(service, /KitLaundryAssignmentSource\.MANUAL/);
  assert.match(service, /declinedFamilyKeys/);
  assert.match(service, /await proposeNextFamily\(event\.id\)/);
  assert.match(routes, /\/:id\/kit-laundry/);
  assert.match(routes, /requirePermission\(Permission\.MANAGE_LINEUPS\)/);
});

test('one-hour reminder is idempotent and limited to nominated families', () => {
  assert.match(service, /55 \* 60_000/);
  assert.match(service, /65 \* 60_000/);
  assert.match(service, /reminderSentAt: null/);
  assert.match(service, /kit-laundry-hour:\$\{duty\.id\}/);
  assert.match(service, /eligibility\.families\.flatMap/);
  assert.match(cron, /processKitLaundryReminders\(\)/);
});

test('tournament fixtures resolve to one duty on their parent tournament', () => {
  assert.match(service, /if \(!event\?\.parentTournamentId\) return event/);
  assert.match(service, /where: \{ id: event\.parentTournamentId \}/);
  assert.match(schema, /eventId\s+String\s+@unique/);
});

test('confirmed family remains visible and authorized after later squad edits', () => {
  assert.match(service, /duty\.assignedFamilyKey &&\s*duty\.assignedPlayerId/);
  assert.match(
    service,
    /duty\.status !== KitLaundryDutyStatus\.OPEN/,
  );
  assert.match(service, /familyKeyIncludesGuardian/);
  assert.match(service, /assignedPlayerName\s*\?\s*`Familie/);
});
