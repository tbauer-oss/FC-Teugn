const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('regular training has two independent defaults and reminder deduplication', () => {
  const schema = source('prisma/schema.prisma');
  const reminders = source('src/services/reminder.service.ts');
  const organization = source('src/controllers/organization.controller.ts');
  const organizationRoutes = source('src/routes/organization.routes.ts');
  assert.match(schema, /defaultReminderMinutes\s+Int\?\s+@default\(60\)/);
  assert.match(schema, /secondaryReminderMinutes\s+Int\?\s+@default\(1440\)/);
  assert.match(reminders, /new Set\(\[[\s\S]*secondaryReminderMinutes[\s\S]*defaultReminderMinutes/);
  assert.match(reminders, /regular-training:\$\{team\.id\}:\$\{occurrence\}:\$\{minutesBefore\}:\$\{recipientId\}/);
  assert.match(reminders, /timeZone:\s*'Europe\/Berlin'/);
  assert.match(
    organization,
    /effectivePermissions\.includes\(Permission\.CONFIGURE_TRAINING_REMINDERS\)/,
  );
  assert.match(organization, /indoorTrainingTimes !== undefined/);
  assert.doesNotMatch(
    organizationRoutes,
    /training-schedule'[\s\S]{0,180}Permission\.MANAGE_ORGANIZATION/,
  );
});

test('training overview follows the selected youth and hides old occurrences', () => {
  const trainings = source('src/controllers/trainings.controller.ts');
  assert.match(
    trainings,
    /export async function listTrainings[\s\S]*contextualTeamIds\(req\.user!\)/,
  );
  assert.match(
    trainings,
    /export async function listTrainings[\s\S]*isHiddenRegularOccurrence:\s*false/,
  );
  assert.match(
    trainings,
    /export async function listExercises[\s\S]*contextualTeamIds\(req\.user!\)/,
  );
});

test('single training occurrence supports cancellation, deletion and hidden tombstones', () => {
  const events = source('src/controllers/events.controller.ts');
  const routes = source('src/routes/events.routes.ts');
  assert.match(routes, /regular-training-occurrences\/cancel[\s\S]*CANCEL_TRAINING_OCCURRENCE/);
  assert.match(events, /Trainingsabsage[\s\S]*forceInApp:\s*true[\s\S]*forcePush:\s*true/);
  assert.match(events, /isHiddenRegularOccurrence:\s*true/);
  assert.doesNotMatch(events, /muss zuerst abgesagt werden, bevor es endgültig gelöscht werden kann/);
  assert.match(events, /EVENT_SERIES_PERMANENTLY_DELETED/);
});

test('match communication uses explicit internal, nomination and family-release stages', () => {
  const schema = source('prisma/schema.prisma');
  const matches = source('src/controllers/matches.controller.ts');
  const routes = source('src/routes/matches.routes.ts');
  assert.match(schema, /enum EventCommunicationStatus[\s\S]*DRAFT[\s\S]*INTERNAL_PUBLISHED[\s\S]*FAMILY_RELEASED/);
  assert.match(routes, /internal-publish[\s\S]*PUBLISH_LINEUP_INTERNAL/);
  assert.match(routes, /family-release[\s\S]*RELEASE_MATCH_FAMILY/);
  assert.match(matches, /Kadernominierung – Rückmeldung erforderlich/);
  assert.match(matches, /communicationStatus:\s*EventCommunicationStatus\.INTERNAL_PUBLISHED/);
  assert.match(matches, /communicationStatus:\s*EventCommunicationStatus\.FAMILY_RELEASED/);
  assert.match(matches, /familyReleasedAt/);
});

test('event creation notification stays scoped and match release remains explicit', () => {
  const events = source('src/controllers/events.controller.ts');
  assert.match(events, /\['NONE', 'IN_APP', 'PUSH'\]/);
  assert.match(events, /reminderRecipientsForEvent\(created\.id/);
  assert.match(events, /Spiele werden erst über die gesonderte Familienfreigabe/);
  assert.match(events, /EVENT_CREATION_NOTIFICATION_SENT/);
});

test('away matches never inherit the Teugn home ground', () => {
  const {
    HOME_MATCH_VENUE,
    normalizedMatchVenue,
  } = require('../dist/src/services/match-venue.service.js');

  assert.deepEqual(
    normalizedMatchVenue({ isHome: true, requested: 'Fremder Platz' }),
    HOME_MATCH_VENUE,
  );
  assert.equal(
    normalizedMatchVenue({
      isHome: false,
      requested: HOME_MATCH_VENUE,
      previous: HOME_MATCH_VENUE,
      previousWasHome: true,
    }),
    '',
  );
  assert.equal(
    normalizedMatchVenue({
      isHome: false,
      requested: '',
      opponentVenue: 'Waldstadion',
      opponentAddress: 'Waldweg 4',
    }),
    'Waldstadion',
  );
});
