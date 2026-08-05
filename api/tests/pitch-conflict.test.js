const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  parseTrainingSlot,
  pitchesOverlap,
  requestableEventPitch,
} = require('../dist/src/services/pitch-conflict.service.js');

test('parses a weekly training slot with its individual pitch', () => {
  assert.deepEqual(
    parseTrainingSlot(
      'Dienstag 17:30–19:00 · Platz: Platz 1 unten',
      'Platz 2 oben',
    ),
    {
      raw: 'Dienstag 17:30–19:00 · Platz: Platz 1 unten',
      weekday: 'Dienstag',
      startMinute: 1050,
      endMinute: 1140,
      pitch: 'Platz 1 unten',
    },
  );
});

test('falls back to the team training location for legacy schedules', () => {
  assert.equal(
    parseTrainingSlot('Donnerstag 16:30-18:00', 'Platz 2 oben').pitch,
    'Platz 2 oben',
  );
});

test('parses legacy labels and the written bis separator', () => {
  assert.deepEqual(
    parseTrainingSlot(
      'Regeltraining am Dienstag von 17:30 bis 19:00 | Platz: Platz 2 oben',
      null,
    ),
    {
      raw: 'Regeltraining am Dienstag von 17:30 bis 19:00 | Platz: Platz 2 oben',
      weekday: 'Dienstag',
      startMinute: 1050,
      endMinute: 1140,
      pitch: 'Platz 2 oben',
    },
  );
});

test('both pitches conflicts with either concrete Teugn pitch', () => {
  assert.equal(
    pitchesOverlap('Sportplatz Teugn · beide Plätze', 'Platz 1 unten'),
    true,
  );
  assert.equal(
    pitchesOverlap('Sportplatz Teugn · beide Plätze', 'Platz 2 oben'),
    true,
  );
});

test('open or unclear pitches never produce false conflicts', () => {
  assert.equal(
    pitchesOverlap('Platz noch offen / unklar', 'Platz 1 unten'),
    false,
  );
});

test('individual non-match events can request a pitch approval', () => {
  assert.equal(
    requestableEventPitch(null, 'Platz 1 unten'),
    'Platz 1 unten',
  );
  assert.equal(
    requestableEventPitch('AWAY', 'Platz 1 unten'),
    null,
  );
  assert.equal(
    requestableEventPitch(null, 'Platz noch offen / unklar'),
    null,
  );
});

test('pitch conflict requests are restricted to event managers', () => {
  const routes = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'routes', 'events.routes.ts'),
    'utf8',
  );
  assert.match(
    routes,
    /'\/pitch-conflict-requests\/list',[\s\S]*?requirePermission\(Permission\.MANAGE_EVENTS\),[\s\S]*?listPitchConflictRequests/,
  );
  assert.match(
    routes,
    /'\/pitch-conflict-requests\/:requestId',[\s\S]*?requirePermission\(Permission\.MANAGE_EVENTS\),[\s\S]*?respondToPitchConflictRequest/,
  );
});
