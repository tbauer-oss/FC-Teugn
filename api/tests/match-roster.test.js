const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

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

test('declined players are excluded from squad and lineup writes', () => {
  const matchesController = fs.readFileSync(
    path.join(__dirname, '../src/controllers/matches.controller.ts'),
    'utf8',
  );
  const eventsController = fs.readFileSync(
    path.join(__dirname, '../src/controllers/events.controller.ts'),
    'utf8',
  );

  assert.match(
    matchesController,
    /status:\s*AttendanceStatus\.NO[\s\S]*declinedIds[\s\S]*requestedMembers\.filter/,
  );
  assert.match(
    matchesController,
    /updateLineup[\s\S]*declinedPlayerIds[\s\S]*!declinedPlayerIds\.has\(member\.playerId\)/,
  );
  assert.match(
    eventsController,
    /status === AttendanceStatus\.NO[\s\S]*lineupPosition\.deleteMany[\s\S]*squadMember\.deleteMany/,
  );
});
