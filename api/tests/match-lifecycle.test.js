const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relative) {
  return fs.readFileSync(path.join(__dirname, '..', relative), 'utf8');
}

test('match lifecycle exposes dedicated delete and reschedule permissions', () => {
  const { Permission, hasPermission } = require('../dist/src/security/permissions');
  const { Role } = require('../dist/src/types/enums');
  for (const permission of [
    Permission.EVENT_DELETE,
    Permission.MATCH_CANCEL,
    Permission.MATCH_DELETE,
    Permission.MATCH_RESCHEDULE,
    Permission.LEAGUE_MATCH_CANCEL,
    Permission.LEAGUE_MATCH_DELETE,
    Permission.LEAGUE_MATCH_RESCHEDULE,
  ]) {
    assert.equal(hasPermission(Role.COACH, permission), true, permission);
    assert.equal(hasPermission(Role.ASSISTANT_COACH, permission), true, permission);
    assert.equal(hasPermission(Role.PARENT, permission), false, permission);
  }
});

test('match and league routes publish online-only lifecycle endpoints', () => {
  const matches = source('src/routes/matches.routes.ts');
  const leagues = source('src/routes/competitions.routes.ts');
  assert.match(matches, /router\.delete\([\s\S]*'\/:id'[\s\S]*MATCH_DELETE/);
  assert.match(matches, /'\/:id\/cancel'[\s\S]*MATCH_CANCEL/);
  assert.match(matches, /'\/:id\/reschedule'[\s\S]*MATCH_RESCHEDULE/);
  assert.match(
    leagues,
    /'\/leagues\/:leagueId\/matches\/:matchId'[\s\S]*LEAGUE_MATCH_DELETE/,
  );
  assert.match(
    leagues,
    /'\/leagues\/:leagueId\/matches\/:matchId\/cancel'[\s\S]*LEAGUE_MATCH_CANCEL/,
  );
});

test('server enforces Teugn venue defaults and checks conflicts before moving', () => {
  const events = source('src/controllers/events.controller.ts');
  const matches = source('src/controllers/matches.controller.ts');
  const venue = source('src/services/match-venue.service.ts');
  assert.match(venue, /Stadion am Kreutweg, Teugn/);
  assert.match(venue, /Vereinsheim Teugn/);
  assert.match(events, /HOME_MATCH_VENUE/);
  assert.match(matches, /normalizedMatchVenue/);
  assert.match(matches, /meetingAt && meetingAt >= startAt/);
  assert.match(matches, /status\(409\)[\s\S]*conflicts/);
  assert.match(matches, /syncScheduledRemindersForEvent\(match\.id\)/);
  assert.match(matches, /MATCH_RESCHEDULED/);
});

test('permanent deletion supports series scope, audit and optional league removal', () => {
  const events = source('src/controllers/events.controller.ts');
  assert.match(events, /\['future', 'series', 'all'\]/);
  assert.match(events, /deleteLeagueMatch === 'true'/);
  assert.match(events, /EVENT_SERIES_PERMANENTLY_DELETED/);
  assert.match(events, /MATCH_DELETED/);
  assert.match(events, /MATCH_CANCELLED/);
  assert.match(events, /forcePush:\s*true/);
  assert.match(events, /notification\.deleteMany/);
});

test('a deliberately deleted import is only recreated by an explicit source-wins decision', () => {
  const imports = source('src/controllers/imports.controller.ts');
  assert.match(imports, /action:\s*ImportRowAction\.CONFLICT/);
  assert.match(imports, /bewusst gel.scht/iu);
  assert.match(imports, /SOURCE_WINS/);
});
