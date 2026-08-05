const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'matches.controller.ts'),
  'utf8',
);

test('matchday responses resolve the crest from the saved opponent pool', () => {
  assert.match(source, /opponentRecord:\s*\{[\s\S]*logoAsset:\s*true/);
  assert.match(source, /matchDetails\.opponentRecord\?\.logoAsset/);
  assert.match(source, /mediaAssetUrl\([\s\S]*logoAsset\.id/);
  assert.match(source, /opponentRecord:\s*undefined/);
});
