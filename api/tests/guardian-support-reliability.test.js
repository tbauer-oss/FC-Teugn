const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('technical support metadata is reduced to a safe whitelist', () => {
  const { sanitizeTechnicalMetadata } = require('../dist/src/controllers/support.controller');
  const result = sanitizeTechnicalMetadata({
    appVersion: '1.5.41',
    platform: 'android',
    route: '/family',
    token: 'must-not-leak',
    password: 'must-not-leak',
    nested: { secret: true },
  });

  assert.deepEqual(result, {
    appVersion: '1.5.41',
    platform: 'android',
    route: '/family',
  });
});

test('support creation and replies honor the optional push selection', () => {
  const support = source('src/controllers/support.controller.ts');
  assert.match(support, /support-created:[\s\S]*pushEnabled:/);
  assert.match(support, /support-reply:[\s\S]*pushEnabled:/);
  assert.match(support, /internal/);
});

test('family response endpoint is role-independent and auditable', () => {
  const events = source('src/controllers/events.controller.ts');
  const routes = source('src/routes/events.routes.ts');
  assert.match(routes, /personal-responses\/list/);
  assert.match(events, /PERSONAL_GUARDIAN/);
  assert.match(events, /parentPlayerLink/);
  assert.match(events, /ATTENDANCE_RESPONSE_CHANGED/);
  assert.match(events, /responderRelationship/);
});

test('matches accept only yes or no responses', () => {
  const events = source('src/controllers/events.controller.ts');
  assert.match(
    events,
    /event\.type === EventType\.MATCH && status === AttendanceStatus\.MAYBE/,
  );
  assert.match(events, /Bei Spielen ist nur eine Zu- oder Absage möglich/);
});

test('family response inbox materializes only the next regular training', () => {
  const {
    nextRegularTrainingOccurrence,
  } = require('../dist/src/services/regular-training-occurrence.service');
  const team = {
    id: 'team-e1',
    name: 'E1-Jugend',
    trainingLocation: 'Teugn Sportplatz',
    trainingTimes: ['Dienstag 17:30–19:00 · Platz: Platz 1 unten'],
    seasonStartDate: new Date('2026-08-18T00:00:00.000Z'),
    seasonEndDate: new Date('2027-06-30T00:00:00.000Z'),
    indoorSeasonStartDate: null,
    indoorSeasonEndDate: null,
    indoorTrainingLocation: null,
    indoorTrainingTimes: [],
    ageGroup: {
      season: {
        name: '2026/27',
        startDate: new Date('2026-08-01T00:00:00.000Z'),
        endDate: new Date('2027-06-30T00:00:00.000Z'),
      },
    },
  };

  const first = nextRegularTrainingOccurrence(
    team,
    new Date('2026-08-14T10:00:00.000Z'),
  );
  const following = nextRegularTrainingOccurrence(
    team,
    new Date('2026-08-18T16:00:00.000Z'),
  );

  assert.equal(first.startAt.toISOString(), '2026-08-18T15:30:00.000Z');
  assert.equal(first.endAt.toISOString(), '2026-08-18T17:00:00.000Z');
  assert.equal(first.location, 'Platz 1 unten');
  assert.equal(following.startAt.toISOString(), '2026-08-25T15:30:00.000Z');

  const events = source('src/controllers/events.controller.ts');
  const occurrenceService = source(
    'src/services/regular-training-occurrence.service.ts',
  );
  assert.match(events, /ensureNextRegularTrainingOccurrences\(teamIds, now\)/);
  assert.match(events, /isHiddenRegularOccurrence:\s*false/);
  assert.match(occurrenceService, /regular-training:\$\{team\.id\}/);
  assert.match(
    occurrenceService,
    /reconcileNextRegularTrainingOccurrence\(prisma, team, now\)/,
  );
  assert.match(occurrenceService, /isSeriesException:\s*true/);
});

test('published cross-team nominations grant access to exactly that event', () => {
  const { eventReadScope } = require('../dist/src/services/team-access');
  const scope = eventReadScope(['team-e2'], { playerIds: ['player-e2'] });

  assert.equal(scope.OR.length, 3);
  assert.deepEqual(scope.OR[0], { teamId: { in: ['team-e2'] } });
  assert.deepEqual(scope.OR[2], {
    squads: {
      some: {
        publishedAt: { not: null },
        members: {
          some: {
            playerId: { in: ['player-e2'] },
            status: 'NOMINATED',
          },
        },
      },
    },
  });

  const events = source('src/controllers/events.controller.ts');
  const matches = source('src/controllers/matches.controller.ts');
  assert.match(events, /eventReadScope\([\s\S]*userId: user\.id/);
  assert.match(matches, /scope\(teamIds, staff \? undefined : user\.id\)/);
  assert.match(matches, /!staff,[\s\S]*MANAGE_STATISTICS/);
});

test('mandatory lifecycle notifications override disabled push preferences', () => {
  const notifications = source('src/services/notification.service.ts');
  const matches = source('src/controllers/matches.controller.ts');
  assert.match(notifications, /input\.forcePush\s*\|\|/);
  assert.match(matches, /MATCH_CANCELLED[\s\S]*forcePush:\s*true/);
  assert.match(matches, /MATCH_DELETED/);
});
