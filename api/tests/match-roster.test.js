const test = require('node:test');
const assert = require('node:assert/strict');

const {
  rosterTeamIdsForMatch,
} = require('../dist/src/services/match-roster.js');

test('uses every separate team from the selected youth player pool', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(['team-e1', 'team-e2', 'team-e3']),
    ['team-e1', 'team-e2', 'team-e3'],
  );
});

test('removes duplicate team access entries', () => {
  assert.deepEqual(
    rosterTeamIdsForMatch(['team-e', 'team-e']),
    ['team-e'],
  );
});
