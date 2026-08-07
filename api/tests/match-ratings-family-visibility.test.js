const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const read = (relativePath) =>
  fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');

const schema = read('prisma/schema.prisma');
const matches = read('src/controllers/matches.controller.ts');
const routes = read('src/routes/matches.routes.ts');

test('match ratings are unique, constrained and staff protected', () => {
  assert.match(schema, /model PlayerMatchRating/);
  assert.match(schema, /@@unique\(\[eventId, playerId\]\)/);
  assert.match(
    read('prisma/migrations/20260807110000_match_player_ratings/migration.sql'),
    /CHECK \("score" BETWEEN 1 AND 10\)/,
  );
  assert.match(routes, /requirePermission\(Permission\.MANAGE_STATISTICS\)/);
  assert.match(matches, /Spielerbewertungen sind erst nach Spielende möglich/);
  assert.match(matches, /Bewertet werden dürfen nur nominierte Spieler/);
});

test('ratings never leave the API for family viewers', () => {
  assert.match(matches, /playerRatings: canRatePlayers \? match\.playerRatings : undefined/);
  assert.match(matches, /canRatePlayers:\s*true|canRatePlayers,/);
});

test('released parents receive full squad, lineup and goal attribution', () => {
  assert.match(matches, /familyTeamViewer && match\.familyReleasedAt !== null/);
  assert.match(matches, /canSeePublishedSquad = staff \|\| tickerEditable \|\| familyDetailsVisible/);
  assert.match(matches, /scorer: tickerEditable \|\| familyDetailsVisible/);
  assert.match(matches, /familyAttributionVisible/);
});
