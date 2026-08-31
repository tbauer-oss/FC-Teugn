const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('event lists resolve shared viewer data once instead of once per event', () => {
  const controller = source('src/controllers/events.controller.ts');
  const listEvents = controller.slice(
    controller.indexOf('export async function listEvents'),
    controller.indexOf('export async function getEvent'),
  );

  assert.match(
    listEvents,
    /const \[events, roster, personalPlayerIds\] = await Promise\.all/,
  );
  assert.equal((listEvents.match(/ownPlayerIds\(user\)/g) ?? []).length, 1);
  assert.match(listEvents, /personalPlayerIds,[\s\S]*\),/);
  assert.match(listEvents, /const types = parseStringList/);
  assert.match(listEvents, /type: \{ in: types as EventType\[\] \}/);
});

test('match detail resolves independent capability and roster reads in parallel', () => {
  const controller = source('src/controllers/matches.controller.ts');
  const getMatch = controller.slice(
    controller.indexOf('export async function getMatch'),
    controller.indexOf('async function matchCancellationAudience'),
  );

  assert.match(
    getMatch,
    /const \[tickerEditable, availablePlayers, viewerPlayerIds\] = await Promise\.all/,
  );
  assert.match(getMatch, /canManageTicker\(user, match\.id\)/);
  assert.match(getMatch, /eligiblePlayers\(\)/);
});
