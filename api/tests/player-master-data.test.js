const test = require('node:test');
const assert = require('node:assert/strict');

const {
  playerData,
  playerInjuryTypes,
} = require('../dist/src/controllers/players.controller.js');

test('normalizes all editable player master data including pass number', () => {
  const data = playerData({
    firstName: '  Max ',
    lastName: ' Muster  ',
    preferredName: ' Maxi ',
    birthDate: '2015-04-08T00:00:00.000Z',
    nationality: ' deutsch ',
    gender: 'DIVERSE',
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
  assert.equal(data.gender, 'DIVERSE');
  assert.equal(data.birthDate.toISOString(), '2015-04-08T00:00:00.000Z');
  assert.equal(data.joinedAt.toISOString(), '2022-07-01T00:00:00.000Z');
});

test('normalizes structured injury data and a custom description', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    status: 'INJURED',
    injuryType: ' other ',
    injuryDetails: '  Reizung nach Fremdeinwirkung  ',
  });

  assert.equal(data.status, 'INJURED');
  assert.equal(data.injuryType, 'OTHER');
  assert.equal(data.injuryDetails, 'Reizung nach Fremdeinwirkung');
  assert.ok(playerInjuryTypes.includes('HEAD_INJURY_CONCUSSION'));
  assert.ok(playerInjuryTypes.includes('OTHER'));
});

test('clears injury data when the player is no longer injured', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    status: 'ACTIVE',
    injuryType: 'MUSCLE_INJURY',
    injuryDetails: 'Darf nicht erhalten bleiben',
  });

  assert.equal(data.injuryType, null);
  assert.equal(data.injuryDetails, null);
});

test('allows optional association dates and pass number to be removed', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    passNumber: '   ',
    gender: null,
    birthDate: null,
    joinedAt: null,
  });

  assert.equal(data.passNumber, null);
  assert.equal(data.gender, null);
  assert.equal(data.birthDate, null);
  assert.equal(data.joinedAt, null);
});
