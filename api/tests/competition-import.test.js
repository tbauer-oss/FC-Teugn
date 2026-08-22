const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  competitionTeamIdentity,
  parseCompetitionSource,
} = require('../dist/src/services/competition-provider.js');
const {
  competitionMatchTiming,
} = require('../dist/src/services/competition-import-write.service.js');
const {
  matchTitleForPlayingIdentity,
} = require('../dist/src/services/team-playing-identity.service.js');

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
assert.equal(first.periodCount, null);
assert.equal(first.periodMinutes, null);

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

assert.deepEqual(
  competitionMatchTiming(
    { periodCount: null, periodMinutes: null },
    { periodCount: 4, periodMinutes: 15 },
  ),
  {
    periodCount: 4,
    periodMinutes: 15,
    durationMinutes: 60,
    explicit: false,
  },
);
assert.deepEqual(
  competitionMatchTiming(
    { periodCount: 3, periodMinutes: 20 },
    { periodCount: 4, periodMinutes: 15 },
  ),
  {
    periodCount: 3,
    periodMinutes: 20,
    durationMinutes: 60,
    explicit: true,
  },
);

const explicitCsv = parseCompetitionSource(
  'CSV',
  'Datum;Uhrzeit;Gegner;Abschnitte;Minuten pro Abschnitt\n18.09.2026;18:00;Testverein E1;4;15',
);
assert.equal(explicitCsv[0].match.periodCount, 4);
assert.equal(explicitCsv[0].match.periodMinutes, 15);

const playingCommunityIcs = `BEGIN:VCALENDAR
BEGIN:VEVENT
UID:sg-a-jugend-1
DTSTART:20260920T120000Z
SUMMARY:(SG) SV Saal/Donau A-Jun. - TSV Beispiel A-Jun., Meisterschaften
LOCATION:Sportplatz Saal
END:VEVENT
END:VCALENDAR`;
const playingCommunityRows = parseCompetitionSource(
  'ICS',
  playingCommunityIcs,
  {
    ownTeamNames: ['(SG) SV Saal/Donau', 'SG Saal/Donau'],
    displayOwnTeamName: '(SG) SV Saal/Donau',
  },
);
assert.equal(playingCommunityRows.length, 1);
assert.equal(playingCommunityRows[0].match.isHome, true);
assert.equal(playingCommunityRows[0].match.opponent, 'TSV Beispiel A1');
assert.equal(
  playingCommunityRows[0].match.title,
  '(SG) SV Saal/Donau – TSV Beispiel A1',
);
assert.equal(
  matchTitleForPlayingIdentity({
    ownTeamName: '(SG) SV Saal/Donau',
    opponent: 'TSV Beispiel A1',
    isHome: false,
  }),
  'TSV Beispiel A1 – (SG) SV Saal/Donau',
);

console.log('competition import tests passed');
