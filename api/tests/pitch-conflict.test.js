const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseTrainingSlot,
  pitchesOverlap,
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
