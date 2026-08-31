const test = require('node:test');
const assert = require('node:assert/strict');

const {
  estimateInjuryRecovery,
  playerData,
  playerInjurySeverities,
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
    injurySeverity: ' unknown ',
    injuryStartDate: '2026-08-31T00:00:00.000Z',
  });

  assert.equal(data.status, 'INJURED');
  assert.equal(data.injuryType, 'OTHER');
  assert.equal(data.injuryDetails, 'Reizung nach Fremdeinwirkung');
  assert.equal(data.injurySeverity, 'UNKNOWN');
  assert.equal(data.injuryStartDate.toISOString(), '2026-08-31T00:00:00.000Z');
  assert.equal(data.estimatedRecoveryMinDays, null);
  assert.equal(data.estimatedRecoveryMaxDays, null);
  assert.ok(playerInjuryTypes.includes('HEAD_INJURY_CONCUSSION'));
  assert.ok(playerInjuryTypes.includes('ACL_INJURY'));
  assert.ok(playerInjuryTypes.includes('OTHER'));
  assert.ok(playerInjurySeverities.includes('UNKNOWN'));
});

test('clears the current injury snapshot when the player is no longer injured', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    status: 'ACTIVE',
    injuryType: 'MUSCLE_INJURY',
    injuryDetails: 'Darf nicht erhalten bleiben',
  });

  assert.equal(data.injuryType, null);
  assert.equal(data.injuryDetails, null);
  assert.equal(data.injurySeverity, null);
  assert.equal(data.injuryStartDate, null);
  assert.equal(data.estimatedReturnTo, null);
  assert.equal(data.manualReturnTo, null);
  assert.equal(data.recoveryEstimateOverridden, false);
});

test('calculates deliberately broad recovery and return ranges', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    status: 'INJURED',
    injuryType: 'STRAIN',
    injurySeverity: 'MEDIUM',
    injuryStartDate: '2026-08-31T00:00:00.000Z',
  });

  assert.deepEqual(estimateInjuryRecovery('STRAIN', 'MEDIUM'), {
    minDays: 7,
    maxDays: 21,
  });
  assert.equal(data.estimatedRecoveryMinDays, 7);
  assert.equal(data.estimatedRecoveryMaxDays, 21);
  assert.equal(data.estimatedReturnFrom.toISOString(), '2026-09-07T00:00:00.000Z');
  assert.equal(data.estimatedReturnTo.toISOString(), '2026-09-21T00:00:00.000Z');
});

test('does not calculate a sporting clearance for head injuries', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    status: 'INJURED',
    injuryType: 'HEAD_INJURY_CONCUSSION',
    injuryStartDate: '2026-08-31T00:00:00.000Z',
  });

  assert.equal(data.estimatedRecoveryMinDays, null);
  assert.equal(data.estimatedRecoveryMaxDays, null);
  assert.equal(data.estimatedReturnFrom, null);
  assert.equal(data.estimatedReturnTo, null);
});

test('stores a manual range explicitly and never replaces it with the estimate', () => {
  const data = playerData({
    firstName: 'Max',
    lastName: 'Muster',
    status: 'INJURED',
    injuryType: 'STRAIN',
    injuryStartDate: '2026-08-31T00:00:00.000Z',
    recoveryEstimateOverridden: true,
    manualReturnFrom: '2026-09-25T00:00:00.000Z',
    manualReturnTo: '2026-09-20T00:00:00.000Z',
  });

  assert.equal(data.recoveryEstimateOverridden, true);
  assert.equal(data.manualReturnFrom.toISOString(), '2026-09-20T00:00:00.000Z');
  assert.equal(data.manualReturnTo.toISOString(), '2026-09-25T00:00:00.000Z');
  assert.equal(data.estimatedReturnTo.toISOString(), '2026-09-21T00:00:00.000Z');
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
