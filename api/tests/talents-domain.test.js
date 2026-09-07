const test = require('node:test');
const assert = require('node:assert/strict');
const { mergeCompetitionFields } = require('../dist/src/services/competition-merge');
const { absenceApplies } = require('../dist/src/services/absence.service');
const { buildVotingUnits, validateVote } = require('../dist/src/services/poll-units');
const { attendanceAfterRevision } = require('../dist/src/services/attendance-revision');
const { carryAbsenceTeams } = require('../dist/src/services/talents-season');
const { talentsReport } = require('../dist/src/services/talents-report');
const { PDFDocument } = require('pdf-lib');

test('import keeps a local venue while taking a rescheduled kickoff', () => {
  const base = { startAt: '2030-09-10T10:00:00Z', location: 'A', opponent: 'Gast' };
  const result = mergeCompetitionFields(base, { ...base, location: 'Vereinsintern B' }, { ...base, startAt: '2030-09-11T10:00:00Z' });
  assert.deepEqual(result.conflicts, []);
  assert.equal(result.merged.location, 'Vereinsintern B');
  assert.equal(result.merged.startAt, '2030-09-11T10:00:00Z');
});
test('independent field decisions resolve conflicting source and local edits', () => {
  const base = { location: 'A', opponent: 'B' }, local = { location: 'C', opponent: 'D' }, source = { location: 'E', opponent: 'F' };
  assert.deepEqual(mergeCompetitionFields(base, local, source).conflicts, ['location', 'opponent']);
  assert.deepEqual(mergeCompetitionFields(base, local, source, false, { location: 'LOCAL', opponent: 'SOURCE' }), { merged: { location: 'C', opponent: 'F' }, conflicts: [] });
});
test('absence recurring day follows Berlin calendar across midnight and DST', () => {
  const a = { startsOn: '2030-03-31', endsOn: '2030-03-31', weekdays: [0], teamIds: ['team'], eventTypes: ['TRAINING'], endedAt: null };
  assert.equal(absenceApplies(a, { startAt: new Date('2030-03-30T23:30:00Z'), teamId: 'team', type: 'TRAINING' }), true);
  assert.equal(absenceApplies(a, { startAt: new Date('2030-03-31T22:30:00Z'), teamId: 'team', type: 'TRAINING' }), false);
  assert.equal(absenceApplies(a, { startAt: new Date('2030-03-31T10:00:00Z'), teamId: 'foreign', type: 'TRAINING' }), false);
});
test('bridge guardian merges overlapping families regardless of child order', () => {
  const players = [{ id: 'a', name: 'A', userIds: ['first'] }, { id: 'b', name: 'B', userIds: ['second'] }, { id: 'c', name: 'C', userIds: ['first', 'second'] }];
  for (const values of [players, [...players].reverse()]) {
    const units = buildVotingUnits('FAMILY', values, []);
    assert.equal(units.length, 1); assert.equal(units[0].unitKey, 'family:a'); assert.equal(units[0].authorizedUserIds.length, 2);
  }
  assert.equal(buildVotingUnits('CHILD', players, []).length, 3);
  assert.throws(() => validateVote([0, 0], 2, true)); assert.throws(() => validateVote([2], 2, false)); assert.throws(() => validateVote([0, 1], 2, false));
});
test('rescheduling exposes previous answer but preserves absence and completed history', () => {
  const now = new Date('2030-01-01'), event = { startAt: new Date('2030-02-01'), responseRevisionAt: new Date('2029-12-30') };
  const reply = { status: 'YES', respondedAt: new Date('2029-12-01') };
  assert.equal(attendanceAfterRevision(reply, event, now).status, 'UNKNOWN');
  assert.equal(attendanceAfterRevision(reply, event, now).previousResponseStatus, 'YES');
  assert.equal(attendanceAfterRevision({ ...reply, absenceId: 'absence', status: 'NO' }, event, now).status, 'NO');
  assert.equal(attendanceAfterRevision(reply, { ...event, attendanceFinalized: true }, now).status, 'YES');
});
test('season absence scope preserves unrestricted and unrelated teams', () => {
  assert.deepEqual(carryAbsenceTeams([], { old: 'new' }), []);
  assert.deepEqual(carryAbsenceTeams(['old', 'unrelated'], { old: 'new' }), ['new', 'unrelated']);
});
test('print report paginates long text and accepts German names and Unicode', async () => {
  const result = await talentsReport('Entwicklungsrückblick', 'Ä Ü Ö ß → ⚽\n'.repeat(200));
  const pdf = await PDFDocument.load(result);
  assert.ok(pdf.getPageCount() >= 4);
});
