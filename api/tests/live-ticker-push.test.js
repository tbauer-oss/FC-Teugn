const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  liveTickerNotificationCopy,
} = require('../dist/src/services/live-ticker-notification.service');
const {
  isRepeatedMatchEnd,
} = require('../dist/src/controllers/matches.controller');

const event = (type, ourGoals = 0, theirGoals = 0) => ({
  id: `event-${type}`,
  type,
  ourGoals,
  theirGoals,
});

test('live ticker push copy exists only for start, goals and end', () => {
  const input = { opponent: 'TSV Beispiel', fcIsHome: true };
  assert.match(
    liveTickerNotificationCopy({ ...input, event: event('MATCH_START') }).title,
    /Anpfiff/,
  );
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('HOME_GOAL', 1, 0),
    }).title,
    /Tor für FC Teugn! 1:0/,
  );
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('AWAY_GOAL', 1, 1),
    }).title,
    /Gegentor · 1:1/,
  );
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('MATCH_END', 2, 1),
    }).title,
    /Endstand 2:1/,
  );
  assert.equal(
    liveTickerNotificationCopy({ ...input, event: event('PERIOD_END') }),
    null,
  );
  assert.equal(
    liveTickerNotificationCopy({ ...input, event: event('COMMENT') }),
    null,
  );
});

test('away matches map FC Teugn and opponent goals correctly', () => {
  const input = { opponent: 'TSV Beispiel', fcIsHome: false };
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('AWAY_GOAL', 1, 0),
    }).title,
    /Tor für FC Teugn/,
  );
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('HOME_GOAL', 1, 1),
    }).title,
    /Gegentor/,
  );
});

test('playing communities use their own identity in ticker notifications', () => {
  const input = {
    opponent: 'TSV Beispiel',
    fcIsHome: true,
    ownTeamName: '(SG) SV Saal/Donau',
  };
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('HOME_GOAL', 1, 0),
    }).title,
    /Tor für \(SG\) SV Saal\/Donau! 1:0/,
  );
  assert.match(
    liveTickerNotificationCopy({
      ...input,
      event: event('MATCH_END', 2, 1),
    }).body,
    /Spiel von \(SG\) SV Saal\/Donau gegen TSV Beispiel/,
  );
});

test('ticker commands notify once after the authoritative commit', () => {
  const controller = fs.readFileSync(
    path.join(__dirname, '../src/controllers/matches.controller.ts'),
    'utf8',
  );
  const command = controller.slice(
    controller.indexOf('export async function tickerCommand'),
    controller.indexOf('export async function undoTickerEvent'),
  );
  assert.match(command, /if \(!result\.duplicate\)/);
  assert.match(command, /isRepeatedMatchEnd\(ticker\.status, type\)/);
  assert.match(command, /type: TickerEventType\.MATCH_END/);
  assert.match(command, /sendLiveTickerNotification\(match, result\.event\)/);
  assert.match(command, /settlePostCommitTasks\(postCommitTasks\)/);
  assert.match(command, /waitUntil\(settlePostCommitTasks\(postCommitTasks\)\)/);
});

test('notification uses the optional live ticker preference and deep link', () => {
  const service = fs.readFileSync(
    path.join(
      __dirname,
      '../src/services/live-ticker-notification.service.ts',
    ),
    'utf8',
  );
  assert.match(service, /category: NotificationCategory\.LIVE_TICKER/);
  assert.match(service, /actionUrl: `\/matches\/\$\{match\.id\}\?tab=live`/);
  assert.match(service, /dedupeKey: `live-ticker:\$\{event\.id\}`/);
  assert.match(service, /prisma\.teamMembership\.findMany/);
  assert.match(service, /familyReleasedAt/);
  assert.match(service, /kind:\s*'LIVE_MATCH'/);
  assert.match(service, /privacy:\s*'NO_PLAYER_NAMES'/);
  assert.doesNotMatch(service, /forcePush:/);
});

test('a finished ticker rejects another final whistle with a new client id', () => {
  assert.equal(isRepeatedMatchEnd('FINISHED', 'MATCH_END'), true);
  assert.equal(isRepeatedMatchEnd('LIVE', 'MATCH_END'), false);
  assert.equal(isRepeatedMatchEnd('FINISHED', 'COMMENT'), false);
});

test('ticker audience includes the whole team and published cross-team guests', () => {
  const service = fs.readFileSync(
    path.join(
      __dirname,
      '../src/services/live-ticker-notification.service.ts',
    ),
    'utf8',
  );
  assert.match(
    service,
    /status:\s*\{\s*in:\s*\[PlayerStatus\.ACTIVE, PlayerStatus\.INJURED\]/,
  );
  assert.match(
    service,
    /eventId:\s*release\.eventId,\s*publishedAt:\s*\{\s*not:\s*null\s*\}/,
  );
  assert.match(service, /where:\s*\{\s*status:\s*NominationStatus\.NOMINATED\s*\}/);
  assert.doesNotMatch(service, /if \(release\.audience === 'NOMINATED_SQUAD'\)/);
});
