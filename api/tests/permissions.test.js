const test = require('node:test');
const assert = require('node:assert/strict');

const { Permission, hasPermission } = require('../dist/src/security/permissions');
const { AccountStatus, Role } = require('../dist/src/types/enums');
const {
  generateOccurrences,
  icsEscape,
  icsDate,
} = require('../dist/src/controllers/events.controller');
const { RecurrenceFrequency } = require('@prisma/client');
const {
  AnnouncementAudience,
} = require('@prisma/client');
const {
  audienceVisible,
} = require('../dist/src/controllers/communications.controller');
const {
  summarizeMatchResults,
} = require('../dist/src/services/statistics.service');
const {
  competitionMatchChecksum,
  parseCompetitionSource,
} = require('../dist/src/services/competition-provider');
const {
  buildTransitionTeamPlans,
  nextAgeGroupCode,
} = require('../dist/src/services/season-transition');
const {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
} = require('../dist/src/lib/jwt');
const {
  checklistItems,
} = require('../dist/src/controllers/team-operations.controller');

test('access and refresh tokens use separate verifiable token classes', () => {
  const access = signAccessToken({ id: 'user-1' }, '5m');
  const refresh = signRefreshToken(
    { sessionId: 'session-1', userId: 'user-1', familyId: 'family-1' },
    '5m',
  );
  assert.equal(verifyAccessToken(access).id, 'user-1');
  assert.equal(verifyRefreshToken(refresh).sessionId, 'session-1');
  assert.throws(() => verifyRefreshToken(access));
  assert.throws(() => verifyAccessToken(refresh));
});

test('club administrators can manage the organization', () => {
  assert.equal(
    hasPermission(Role.CLUB_ADMIN, Permission.MANAGE_ORGANIZATION),
    true,
  );
});

test('coaches can manage players and events but not the organization', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_PLAYERS), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_DOCUMENTS), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_EVENTS), true);
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_DEVELOPMENT),
    true,
  );
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_SENSITIVE_PLAYER),
    true,
  );
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_ORGANIZATION),
    false,
  );
});

test('parents can respond to attendance without changing team data', () => {
  assert.equal(
    hasPermission(Role.PARENT, Permission.RESPOND_ATTENDANCE),
    true,
  );
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_PLAYERS), false);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_DOCUMENTS), false);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_EVENTS), false);
  assert.equal(
    hasPermission(Role.PARENT, Permission.VIEW_SENSITIVE_PLAYER),
    false,
  );
});

test('read-only members cannot mutate data', () => {
  assert.equal(hasPermission(Role.READ_ONLY, Permission.VIEW_TEAM), true);
  assert.equal(hasPermission(Role.READ_ONLY, Permission.MANAGE_TEAM), false);
  assert.equal(
    hasPermission(Role.READ_ONLY, Permission.VIEW_SENSITIVE_PLAYER),
    false,
  );
});

test('registration lifecycle exposes all auditable account states', () => {
  assert.deepEqual(Object.values(AccountStatus), [
    'PENDING',
    'APPROVED',
    'REJECTED',
    'BLOCKED',
    'ARCHIVED',
  ]);
});

test('assistant coaches can document development but not edit medical data', () => {
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_DEVELOPMENT),
    true,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_SENSITIVE_PLAYER),
    false,
  );
});

test('matchday operations are restricted to assigned staff roles', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_LINEUPS),
    true,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_LIVE_TICKER),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.MANAGE_LINEUPS),
    false,
  );
  assert.equal(
    hasPermission(Role.PLAYER, Permission.MANAGE_LIVE_TICKER),
    false,
  );
});

test('training and statistics mutations remain staff-only', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_TRAINING), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_STATISTICS), true);
  assert.equal(hasPermission(Role.PARENT, Permission.VIEW_PLAYER_STATS), true);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_TRAINING), false);
  assert.equal(hasPermission(Role.PLAYER, Permission.MANAGE_STATISTICS), false);
});

test('team communications can only be sent by staff roles', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.SEND_ANNOUNCEMENTS),
    true,
  );
  assert.equal(
    hasPermission(Role.TEAM_MANAGER, Permission.SEND_ANNOUNCEMENTS),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.SEND_ANNOUNCEMENTS),
    false,
  );
  assert.equal(
    hasPermission(Role.PLAYER, Permission.SEND_ANNOUNCEMENTS),
    false,
  );
});

test('announcement audiences are separated by member role', () => {
  assert.equal(
    audienceVisible(Role.PARENT, AnnouncementAudience.PARENTS),
    true,
  );
  assert.equal(
    audienceVisible(Role.PLAYER, AnnouncementAudience.PARENTS),
    false,
  );
  assert.equal(
    audienceVisible(Role.COACH, AnnouncementAudience.STAFF),
    true,
  );
  assert.equal(
    audienceVisible(Role.PARENT, AnnouncementAudience.STAFF),
    false,
  );
  assert.equal(
    audienceVisible(Role.PARENT, AnnouncementAudience.ALL_MEMBERS),
    true,
  );
});

test('competition imports are restricted to staff roles', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_IMPORTS), true);
  assert.equal(
    hasPermission(Role.TEAM_MANAGER, Permission.MANAGE_IMPORTS),
    true,
  );
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_IMPORTS), false);
});

test('team operations are visible to members but mutable only by staff', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_TEAM_OPERATIONS),
    true,
  );
  assert.equal(
    hasPermission(Role.TEAM_MANAGER, Permission.MANAGE_TEAM_OPERATIONS),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.VIEW_TEAM_OPERATIONS),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.MANAGE_TEAM_OPERATIONS),
    false,
  );
});

test('checklist templates discard empty items and preserve required flags', () => {
  assert.deepEqual(checklistItems([
    { title: 'Trikots prüfen', isRequired: true },
    'Bälle einladen',
    { title: '   ' },
    { title: 'Getränke', isRequired: false },
  ]), [
    { title: 'Trikots prüfen', position: 0, isRequired: true },
    { title: 'Bälle einladen', position: 1, isRequired: true },
    { title: 'Getränke', position: 3, isRequired: false },
  ]);
});

test('season transition advances youth age groups without changing A youth', () => {
  assert.equal(nextAgeGroupCode('G'), 'F');
  assert.equal(nextAgeGroupCode('E'), 'D');
  assert.equal(nextAgeGroupCode('A'), 'A');
});

test('season transition preview respects explicit team overrides', () => {
  const plans = buildTransitionTeamPlans(
    [
      {
        id: 'team-e1',
        name: 'E1',
        shortName: 'E1',
        level: 'Kreisliga',
        ageGroup: { code: 'E', name: 'E-Jugend' },
        playerCount: 14,
        activePlayerCount: 12,
        staffCount: 3,
      },
    ],
    [
      {
        sourceTeamId: 'team-e1',
        targetAgeGroupCode: 'D',
        targetName: 'D2',
        includeStaff: false,
      },
    ],
  );
  assert.deepEqual(
    {
      targetAgeGroupCode: plans[0].targetAgeGroupCode,
      targetName: plans[0].targetName,
      includePlayers: plans[0].includePlayers,
      includeStaff: plans[0].includeStaff,
      archivedPlayerCount: plans[0].archivedPlayerCount,
    },
    {
      targetAgeGroupCode: 'D',
      targetName: 'D2',
      includePlayers: true,
      includeStaff: false,
      archivedPlayerCount: 2,
    },
  );
});

test('CSV competition provider normalizes German exports deterministically', () => {
  const rows = parseCompetitionSource(
    'CSV',
    [
      'Spielkennung;Datum;Uhrzeit;Gegner;Heimspiel;Wettbewerb;Ort',
      'bfv-4711;15.08.2026;10:30;SV Beispiel;ja;Kreisliga;Sportplatz Teugn',
    ].join('\n'),
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].match.externalId, 'bfv-4711');
  assert.equal(rows[0].match.opponent, 'SV Beispiel');
  assert.equal(rows[0].match.isHome, true);
  assert.equal(
    competitionMatchChecksum(rows[0].match),
    competitionMatchChecksum(rows[0].match),
  );
});

test('ICS competition provider requires events and preserves UID', () => {
  const rows = parseCompetitionSource(
    'ICS',
    [
      'BEGIN:VCALENDAR',
      'BEGIN:VEVENT',
      'UID:spiel-123@example.test',
      'DTSTART:20260822T090000Z',
      'SUMMARY:FC Teugn - TSV Muster',
      'LOCATION:Waldstadion',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n'),
  );
  assert.equal(rows[0].match.externalId, 'spiel-123@example.test');
  assert.equal(rows[0].match.opponent, 'TSV Muster');
  assert.equal(rows[0].match.isHome, true);
  assert.equal(rows[0].match.location, 'Waldstadion');
});

test('ICS competition provider converts Europe/Berlin summer time to UTC', () => {
  const rows = parseCompetitionSource(
    'ICS',
    [
      'BEGIN:VEVENT',
      'UID:spiel-sommer@example.test',
      'DTSTART;TZID=Europe/Berlin:20260822T110000',
      'SUMMARY:FC Teugn - TSV Sommer',
      'END:VEVENT',
    ].join('\r\n'),
  );
  assert.equal(rows[0].match.startAt, '2026-08-22T09:00:00.000Z');
});

test('team statistics summarize results, form and home-away records', () => {
  const summary = summarizeMatchResults([
    { ourGoals: 3, theirGoals: 1, result: 'WIN', isHome: true },
    { ourGoals: 1, theirGoals: 1, result: 'DRAW', isHome: false },
    { ourGoals: 0, theirGoals: 2, result: 'LOSS', isHome: false },
    { ourGoals: 2, theirGoals: 0, result: 'WIN', isHome: true },
  ]);
  assert.deepEqual(
    {
      matches: summary.matches,
      wins: summary.wins,
      draws: summary.draws,
      losses: summary.losses,
      goalsFor: summary.goalsFor,
      goalsAgainst: summary.goalsAgainst,
      winRate: summary.winRate,
      goalsPerMatch: summary.goalsPerMatch,
      home: summary.home,
      away: summary.away,
    },
    {
      matches: 4,
      wins: 2,
      draws: 1,
      losses: 1,
      goalsFor: 6,
      goalsAgainst: 4,
      winRate: 50,
      goalsPerMatch: 1.5,
      home: { matches: 2, wins: 2 },
      away: { matches: 2, wins: 0 },
    },
  );
  assert.deepEqual(summary.form, ['WIN', 'DRAW', 'LOSS', 'WIN']);
});

test('weekly and biweekly calendar series include the boundary occurrence', () => {
  const start = new Date('2026-08-03T16:00:00.000Z');
  const weekly = generateOccurrences(
    start,
    new Date('2026-08-24T16:00:00.000Z'),
    RecurrenceFrequency.WEEKLY,
    1,
    [],
  );
  const biweekly = generateOccurrences(
    start,
    new Date('2026-08-31T16:00:00.000Z'),
    RecurrenceFrequency.BIWEEKLY,
    1,
    [],
  );
  assert.deepEqual(
    weekly.map((value) => value.toISOString()),
    [
      '2026-08-03T16:00:00.000Z',
      '2026-08-10T16:00:00.000Z',
      '2026-08-17T16:00:00.000Z',
      '2026-08-24T16:00:00.000Z',
    ],
  );
  assert.equal(biweekly.length, 3);
});

test('custom calendar series supports selected weekdays and an interval', () => {
  const dates = generateOccurrences(
    new Date('2026-08-03T16:00:00.000Z'),
    new Date('2026-08-16T16:00:00.000Z'),
    RecurrenceFrequency.CUSTOM,
    1,
    [1, 3],
  );
  assert.deepEqual(
    dates.map((value) => value.toISOString().slice(0, 10)),
    ['2026-08-03', '2026-08-05', '2026-08-10', '2026-08-12'],
  );
});

test('calendar generation is bounded and ICS values are escaped safely', () => {
  const dates = generateOccurrences(
    new Date('2026-01-01T10:00:00.000Z'),
    new Date('2030-01-01T10:00:00.000Z'),
    RecurrenceFrequency.CUSTOM,
    1,
    [1, 2, 3, 4, 5, 6, 7],
  );
  assert.equal(dates.length, 120);
  assert.equal(icsEscape('FC, Teugn; A\\B\nTraining'), 'FC\\, Teugn\\; A\\\\B\\nTraining');
  assert.equal(
    icsDate(new Date('2026-08-03T16:00:00.123Z')),
    '20260803T160000Z',
  );
});
