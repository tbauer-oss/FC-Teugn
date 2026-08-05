const test = require('node:test');
const assert = require('node:assert/strict');

const {
  openAttendancePlayerIds,
} = require('../dist/src/services/attendance-summary.js');

test('placeholder attendance remains open until a real response arrives', () => {
  const roster = ['player-1', 'player-2', 'player-3'];
  const replies = [
    { playerId: 'player-1', status: 'UNKNOWN' },
    { playerId: 'player-2', status: 'YES' },
    { playerId: 'player-3', status: 'MAYBE' },
  ];

  assert.deepEqual(openAttendancePlayerIds(roster, replies), ['player-1']);
});

test('every explicitly requested player stays open without a response', () => {
  const roster = ['player-1', 'player-2'];
  const replies = roster.map((playerId) => ({
    playerId,
    status: 'UNKNOWN',
  }));

  assert.deepEqual(openAttendancePlayerIds(roster, replies), roster);
});
