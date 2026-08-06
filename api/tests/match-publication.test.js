const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  buildFamilyReleaseMessage,
  buildInternalPublicationMessage,
  resolveMeetingPoint,
} = require('../dist/src/services/match-publication.service.js');
const { EventCategory } = require('@prisma/client');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('relative meeting time is resolved from kick-off and survives the DST boundary', () => {
  const meeting = resolveMeetingPoint({
    startAt: new Date('2026-03-29T01:30:00.000Z'),
    meetingMinutesBefore: 60,
    meetingLocation: 'Vereinsheim Teugn',
  });
  assert.equal(meeting.at.toISOString(), '2026-03-29T00:30:00.000Z');
  assert.equal(meeting.summary, 'Treffpunkt: 01:30 Uhr am Vereinsheim Teugn');
});

test('concrete meeting time has priority over a relative setting', () => {
  const meeting = resolveMeetingPoint({
    startAt: new Date('2026-08-14T15:30:00.000Z'),
    meetingAt: new Date('2026-08-14T14:10:00.000Z'),
    meetingMinutesBefore: 60,
    meetingLocation: 'Vereinsheim Teugn',
  });
  assert.equal(meeting.at.toISOString(), '2026-08-14T14:10:00.000Z');
  assert.equal(meeting.summary, 'Treffpunkt: 16:10 Uhr am Vereinsheim Teugn');
});

test('meeting point formatter covers both, time-only, location-only and fully open states', () => {
  const startAt = new Date('2026-08-14T15:30:00.000Z');
  assert.equal(
    resolveMeetingPoint({ startAt, meetingAt: new Date('2026-08-14T14:30:00.000Z') }).summary,
    'Treffpunkt: 16:30 Uhr am Vereinsheim Teugn',
  );
  assert.equal(
    resolveMeetingPoint({
      startAt,
      meetingAt: new Date('2026-08-14T14:30:00.000Z'),
      useClubhouseDefault: false,
    }).summary,
    'Treffpunkt: 16:30 Uhr',
  );
  assert.equal(
    resolveMeetingPoint({
      startAt,
      meetingLocation: 'Sportheim Saal',
      useClubhouseDefault: false,
    }).summary,
    'Treffpunktort: Sportheim Saal – Uhrzeit noch offen',
  );
  assert.equal(
    resolveMeetingPoint({ startAt, useClubhouseDefault: false }).summary,
    'Treffpunkt noch offen',
  );
});

test('family release push and in-app text use the exact same server-side message', () => {
  const meeting = resolveMeetingPoint({
    startAt: new Date('2026-08-14T15:30:00.000Z'),
    meetingAt: new Date('2026-08-14T14:30:00.000Z'),
    meetingLocation: 'Vereinsheim Teugn',
  });
  assert.equal(
    buildFamilyReleaseMessage({
      category: EventCategory.FRIENDLY_MATCH,
      opponent: 'SV Saal E1',
      startAt: new Date('2026-08-14T15:30:00.000Z'),
      meeting,
    }),
    'Das Freundschaftsspiel gegen SV Saal E1 wurde für Freitag, 14. August 2026 um 17:30 Uhr freigegeben. Treffpunkt: 16:30 Uhr am Vereinsheim Teugn.',
  );
});

test('internal publication message names match type, team and opponent', () => {
  assert.equal(
    buildInternalPublicationMessage({
      category: EventCategory.FRIENDLY_MATCH,
      team: 'E1',
      opponent: 'SV Saal E1',
    }),
    'Kader und Aufstellung für das Freundschaftsspiel der E1 gegen SV Saal E1 wurden intern veröffentlicht.',
  );
});

test('internal publication endpoint only accepts assigned team staff and selected recipients', () => {
  const controller = source('src/controllers/matches.controller.ts');
  assert.match(controller, /Role\.COACH[\s\S]*Role\.TRAINER[\s\S]*Role\.ASSISTANT_COACH[\s\S]*Role\.TEAM_MANAGER/);
  assert.doesNotMatch(
    controller.slice(
      controller.indexOf('async function eligibleInternalPublicationRecipients'),
      controller.indexOf('function publicationOpponent'),
    ),
    /SUPER_ADMIN|CLUB_ADMIN|YOUTH_DIRECTOR|TRAINER_ADMIN/,
  );
  assert.match(controller, /invalidRecipientIds[\s\S]*außerhalb des zuständigen Trainerteams/);
  assert.match(controller, /Mindestens ein Trainerteam-Mitglied muss ausgewählt sein/);
  assert.match(controller, /isSender:\s*recipient\.id === req\.user!\.id/);
});

test('publication is idempotent for in-app notifications and device deliveries', () => {
  const schema = source('prisma/schema.prisma');
  const notifications = source('src/services/notification.service.ts');
  assert.match(schema, /@@unique\(\[notificationId, subscriptionId\]\)/);
  assert.match(notifications, /notificationId_subscriptionId/);
  assert.match(notifications, /delivery\.status !== NotificationDeliveryStatus\.SENT/);
});
