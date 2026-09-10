const test = require('node:test');
const assert = require('node:assert/strict');
const { validateTacticsDocument } = require('../dist/src/services/tactics-board');
const doc = () => ({ schemaVersion: 1, scenes: [{ id: 'one', name: 'Ecke', tokens: [
  { id: 'player', kind: 'own', label: 'Spieler 1', x: .25, y: .75 },
  { id: 'opponent', kind: 'opponent', label: 'Gegner 4', x: .2, y: .3 },
], strokes: [{ id: 'arrow', kind: 'arrow', color: 'yellow', points: [{ x: 0, y: 1 }, { x: 1, y: 0 }] }] }] });
test('tactics board round trip and unknown fields are stripped', () => {
  assert.deepEqual(validateTacticsDocument({ ...doc(), secret: 'unused' }), doc());
});
test('invalid coordinates, duplicate IDs, unknown tools and oversized boards rejected', () => {
  const mutations = [d => d.schemaVersion = 2, d => d.scenes = [],
    d => d.scenes[0].tokens[0].x = NaN, d => d.scenes[0].tokens[0].x = Infinity,
    d => d.scenes[0].tokens[0].y = 1.1, d => d.scenes[0].tokens[0].x = -.01,
    d => d.scenes[0].tokens.push(d.scenes[0].tokens[0]),
    d => d.scenes[0].strokes[0].kind = 'script', d => d.scenes[0].strokes[0].color = 'url(x)',
    d => d.scenes[0].strokes[0].points = [{ x: 0, y: 0 }],
    d => d.scenes[0].tokens[0].label = 'a'.repeat(51),
    d => d.scenes = Array.from({length: 9}, (_, i) => ({...d.scenes[0], id: String(i)})),
    d => d.unused = 'a'.repeat(350001)];
  for (const mutate of mutations) { const d = doc(); mutate(d); assert.throws(() => validateTacticsDocument(d)); }
});
