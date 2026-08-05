const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('live ticker polling uses the lightweight incremental query', () => {
  const controller = source('src/controllers/matches.controller.ts');
  const getTicker = controller.slice(
    controller.indexOf('export async function getTicker(req'),
    controller.indexOf('export async function tickerCommand'),
  );

  assert.match(getTicker, /findAccessibleTickerMatch/);
  assert.doesNotMatch(getTicker, /findMatch\(/);
  assert.match(getTicker, /sequence: \{ gt: after \}/);
  assert.match(getTicker, /revokedAt: null/);
});

test('live goal commands defer statistics until match end', () => {
  const controller = source('src/controllers/matches.controller.ts');
  const tickerCommand = controller.slice(
    controller.indexOf('export async function tickerCommand'),
    controller.indexOf('export async function undoTickerEvent'),
  );

  assert.match(tickerCommand, /findTickerCommandMatch/);
  assert.doesNotMatch(tickerCommand, /findMatch\(/);
  assert.match(
    tickerCommand,
    /if \(type === TickerEventType\.MATCH_END\) \{\s+await recalculateMatchStatistics/,
  );
  assert.doesNotMatch(tickerCommand, /goalTypes/);
});
