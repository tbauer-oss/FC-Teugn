const test = require('node:test');
const assert = require('node:assert/strict');

const {
  playerData,
} = require('../dist/src/controllers/players.controller.js');

test('normalizes all editable player master data including pass number', () => {
  const data = playerData({
    firstName: '  Max ',
    lastName: ' Muster  ',
    preferredName: ' Maxi ',
    birthDate: '2015-04-08T00:00:00.000Z',
    nationality: ' deutsch ',
    position: ' ZM ',
    secondaryPosition: ' OM ',
    dominantFoot: 'RIGHT',
    shirtNumber: 8,
    passNumber: ' BFV-001234 ',
    status: 'ACTIVE',
    joinedAt: '2022-07-01T00:00:00.000Z',
  });

  assert.equal(data.firstName, 'Max');
  assert.equal(data.lastName, 'Muster');
  assert.equal(data.passNumber, 'BFV-001234');
  assert.equal(data.birthDate.toISOString(), '2015-04-08T00:00:00.000Z');
  assert.equal(data.joinedAt.toISOString(), '2022-07-01T00:00:00.000Z');
});

test('allows optional association dates and pass number to be removed', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    passNumber: '   ',
    birthDate: null,
    joinedAt: null,
  });

  assert.equal(data.passNumber, null);
  assert.equal(data.birthDate, null);
  assert.equal(data.joinedAt, null);
});
