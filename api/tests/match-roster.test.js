const test = require('node:test');
const assert = require('node:assert/strict');

const {
  rosterTeamIdsForMatch,
} = require('../dist/src/services/match-roster.js');

test('uses every team that is accessible to the trainer', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(['team-e', 'team-d']),
    ['team-e', 'team-d'],
  );
});

test('removes duplicate team access entries', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(['team-e', 'team-e']),
    ['team-e'],
  );
});
