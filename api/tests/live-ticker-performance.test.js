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
  const readTickerSnapshot = controller.slice(
    controller.indexOf('function readTickerSnapshot'),
    controller.indexOf('export async function getTicker(req'),
  );

  assert.match(getTicker, /findAccessibleTickerMatch/);
  assert.doesNotMatch(getTicker, /findMatch\(/);
  assert.match(readTickerSnapshot, /sequence: \{ gt: after \}/);
  assert.match(readTickerSnapshot, /revokedAt: null/);
  assert.match(getTicker, /waitMs/);
  assert.match(getTicker, /waitForLiveTickerUpdate/);
  assert.match(getTicker, /Cache-Control/);
  assert.match(getTicker, /findAccessibleTickerMatch[\s\S]*findAccessibleTickerMatch/);
});

test('every authoritative ticker mutation wakes waiting viewers', () => {
  const controller = source('src/controllers/matches.controller.ts');
  const tickerCommand = controller.slice(
    controller.indexOf('export async function tickerCommand'),
    controller.indexOf('export async function undoTickerEvent'),
  );
  const undo = controller.slice(
    controller.indexOf('export async function undoTickerEvent'),
    controller.indexOf('export async function resetTicker'),
  );
  const reset = controller.slice(
    controller.indexOf('export async function resetTicker'),
  );

  assert.match(tickerCommand, /publishLiveTickerUpdate\(match\.id\)/);
  assert.match(undo, /publishLiveTickerUpdate\(match\.id\)/);
  assert.match(reset, /publishLiveTickerUpdate\(match\.id\)/);
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
    /if \(type === TickerEventType\.MATCH_END\) \{[\s\S]*promise: recalculateMatchStatistics/,
  );
  assert.match(tickerCommand, /waitUntil\(settlePostCommitTasks\(postCommitTasks\)\)/);
  assert.doesNotMatch(tickerCommand, /goalTypes/);
});
