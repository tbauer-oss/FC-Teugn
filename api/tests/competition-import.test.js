const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  competitionTeamIdentity,
  parseCompetitionSource,
} = require('../dist/src/services/competition-provider.js');

const fixture = fs.readFileSync(
  path.join(__dirname, 'fixtures', 'bfv-spielplan.ics'),
  'utf8',
);
const rows = parseCompetitionSource('ICS', fixture);

assert.equal(rows.length, 7, 'all seven BfV matches should be parsed');
assert.ok(rows.every((row) => row.match), 'no BfV row should be invalid');

const first = rows[0].match;
assert.equal(first.externalId, '031PT45JGG000000VS5489BUVSV0FPBG');
assert.equal(first.opponent, 'SC Thaldorf E1');
assert.equal(first.opponentClubName, 'SC Thaldorf');
assert.equal(first.opponentTeamDesignation, 'E1');
assert.equal(first.isHome, true);
assert.equal(first.startAt, '2026-09-18T16:00:00.000Z');
assert.equal(first.location, 'Sportanlage Teugn, Platz 2');
assert.equal(first.address, 'Kreutweg 13, 93356 Teugn');
assert.equal(first.competition, 'Meisterschaften');
assert.equal(first.division, 'U11 (E7-Jun.) Gruppe Teugn (Herbst 1)');

const away = rows[1].match;
assert.equal(away.opponent, 'TSV Langquaid E3');
assert.equal(away.opponentTeamDesignation, 'E3');
assert.equal(away.isHome, false);
assert.equal(away.title, 'TSV Langquaid E3 – FC Teugn');

const community = rows[2].match;
assert.equal(community.opponent, 'FC Laimerstadt E1');
assert.equal(community.opponentClubName, 'FC Laimerstadt');

assert.deepEqual(competitionTeamIdentity('FC Hausen E7 2'), {
  rawName: 'FC Hausen E7 2',
  clubName: 'FC Hausen',
  teamDesignation: 'E2',
  displayName: 'FC Hausen E2',
});

console.log('competition import tests passed');
