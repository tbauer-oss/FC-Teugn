const test = require('node:test');
const assert = require('node:assert/strict');

const {
  rosterTeamIdsForMatch,
} = require('../dist/src/services/match-roster.js');

test('uses the teams assigned to the match when they have a roster', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(
      ['team-e'],
      ['team-e', 'team-d'],
      10,
    ),
    ['team-e'],
  );
});

test('falls back to accessible teams when the assigned team has no players', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(
      ['team-e'],
      ['team-e', 'team-d'],
      0,
    ),
    ['team-e', 'team-d'],
  );
});

test('never includes inaccessible teams', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(
      ['foreign-team'],
      ['team-e'],
      0,
    ),
    ['team-e'],
  );
});
