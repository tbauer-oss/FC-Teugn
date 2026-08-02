const test = require('node:test');
const assert = require('node:assert/strict');

const {
  confirmedLineupCandidates,
  planTeamDefaultLineup,
} = require('../dist/src/services/default-lineup.service.js');

const slots = [
  {
    playerId: 'keeper-default',
    positionCode: 'TW',
    x: 0.5,
    y: 0.9,
    isGoalkeeper: true,
    isCaptain: false,
    sortOrder: 0,
  },
  {
    playerId: 'striker-default',
    positionCode: 'ST',
    x: 0.5,
    y: 0.2,
    isGoalkeeper: false,
    isCaptain: true,
    sortOrder: 1,
  },
];

test('keeps available players from the team default lineup', () => {
  const result = planTeamDefaultLineup(slots, [
    { id: 'keeper-default', position: 'TW', secondaryPosition: null, shirtNumber: 1 },
    { id: 'striker-default', position: 'ST', secondaryPosition: null, shirtNumber: 9 },
  ]);

  assert.deepEqual(result.positions.map((item) => item.playerId), [
    'keeper-default',
    'striker-default',
  ]);
  assert.equal(result.automaticReplacements, 0);
});

test('replaces an unavailable starter with the best positional match', () => {
  const result = planTeamDefaultLineup(slots, [
    { id: 'keeper-default', position: 'TW', secondaryPosition: null, shirtNumber: 1 },
    { id: 'midfielder', position: 'ZM', secondaryPosition: null, shirtNumber: 8 },
    { id: 'striker-replacement', position: 'OM', secondaryPosition: 'ST', shirtNumber: 11 },
  ]);

  assert.deepEqual(result.positions.map((item) => item.playerId), [
    'keeper-default',
    'striker-replacement',
  ]);
  assert.equal(result.positions[1].replacedPlayerId, 'striker-default');
  assert.equal(result.automaticReplacements, 1);
});

test('never moves a goalkeeper into the field while a field player is available', () => {
  const result = planTeamDefaultLineup([slots[1]], [
    { id: 'second-keeper', position: 'TW', secondaryPosition: null, shirtNumber: 12 },
    { id: 'field-player', position: 'IV', secondaryPosition: null, shirtNumber: 4 },
  ]);

  assert.equal(result.positions[0].playerId, 'field-player');
});

test('reserves available default starters before filling an earlier missing slot', () => {
  const result = planTeamDefaultLineup(slots, [
    { id: 'striker-default', position: 'ST', secondaryPosition: null, shirtNumber: 9 },
    { id: 'field-replacement', position: 'IV', secondaryPosition: null, shirtNumber: 4 },
  ]);

  assert.equal(result.positions[0].playerId, 'field-replacement');
  assert.equal(result.positions[1].playerId, 'striker-default');
  assert.equal(result.automaticReplacements, 1);
});

test('uses only confirmed players before applying positional replacements', () => {
  const allNominated = [
    { id: 'keeper-default', position: 'TW', secondaryPosition: null, shirtNumber: 1 },
    { id: 'striker-default', position: 'ST', secondaryPosition: null, shirtNumber: 9 },
    { id: 'striker-replacement', position: 'OM', secondaryPosition: 'ST', shirtNumber: 11 },
  ];
  const confirmed = confirmedLineupCandidates(allNominated, [
    'keeper-default',
    'striker-replacement',
  ]);
  const result = planTeamDefaultLineup(slots, confirmed);

  assert.deepEqual(result.positions.map((item) => item.playerId), [
    'keeper-default',
    'striker-replacement',
  ]);
  assert.equal(result.positions[1].replacedPlayerId, 'striker-default');
});
