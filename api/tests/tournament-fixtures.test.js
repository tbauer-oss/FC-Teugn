const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const schema = fs.readFileSync(
  path.join(root, 'prisma/schema.prisma'),
  'utf8',
);
const eventController = fs.readFileSync(
  path.join(root, 'src/controllers/events.controller.ts'),
  'utf8',
);
const matchController = fs.readFileSync(
  path.join(root, 'src/controllers/matches.controller.ts'),
  'utf8',
);
const matchRoutes = fs.readFileSync(
  path.join(root, 'src/routes/matches.routes.ts'),
  'utf8',
);

test('a tournament owns independent playable fixtures', () => {
  assert.match(schema, /parentTournamentId\s+String\?/);
  assert.match(schema, /@relation\("TournamentFixtures"/);
  assert.match(schema, /tournamentFixtures\s+Event\[\]/);
  assert.match(
    matchRoutes,
    /'\/:id\/tournament-fixtures'[\s\S]*syncTournamentFixtures/,
  );
  assert.match(matchController, /export async function syncTournamentFixtures/);
  assert.match(matchController, /competition: 'Turnierspiel'/);
});

test('tournament containers do not require one opponent', () => {
  assert.match(
    eventController,
    /function isSingleMatchCategory[\s\S]*!isTournamentCategory/,
  );
  assert.match(
    eventController,
    /const singleMatch = isSingleMatchCategory\(parsed\.category\)/,
  );
  assert.match(
    eventController,
    /isTournamentCategory\(parsed\.category\)[\s\S]*matchDetails\.deleteMany/,
  );
});

test('nested fixtures stay out of calendar and family response lists', () => {
  const parentFilterOccurrences = (
    eventController.match(/parentTournamentId: null/g) ?? []
  ).length;
  assert.ok(
    parentFilterOccurrences >= 2,
    'event and personal-response queries must both filter tournament fixtures',
  );
  assert.match(
    eventController,
    /tournamentFixtures: event\.tournamentFixtures[\s\S]*familyReleasedAt/,
  );
});
