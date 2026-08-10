const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const controllerSource = fs.readFileSync(
  path.join(root, 'src/controllers/competitions.controller.ts'),
  'utf8',
);
const routeSource = fs.readFileSync(
  path.join(root, 'src/routes/competitions.routes.ts'),
  'utf8',
);
const schema = fs.readFileSync(
  path.join(root, 'prisma/schema.prisma'),
  'utf8',
);
const {
  canonicalTeamDesignation,
} = require('../dist/src/controllers/competitions.controller');

test('legacy game-format labels are converted to youth team labels', () => {
  assert.equal(canonicalTeamDesignation('E7 2', 'E'), 'E2');
  assert.equal(canonicalTeamDesignation('E7', 'E'), 'E1');
  assert.equal(canonicalTeamDesignation('D9 3', 'D'), 'D3');
  assert.equal(canonicalTeamDesignation('E2', 'E'), 'E2');
});

test('opponent clubs are shared while youth teams remain age-group scoped', () => {
  assert.match(schema, /model OpponentClub[\s\S]*organizationClubId String/);
  assert.match(schema, /Opponent[\s\S]*opponentClubId\s+String/);
  assert.match(
    schema,
    /@@unique\(\[ageGroupId, opponentClubId, teamDesignation\]\)/,
  );
  assert.match(controllerSource, /listOpponentClubs[\s\S]*organizationClubId/);
  assert.match(controllerSource, /saveOpponent[\s\S]*accessibleAgeGroup/);
  assert.match(
    controllerSource,
    /Kein Zugriff auf diese Jugend\./,
  );
});

test('all approved users may read the club pool but writes require event rights', () => {
  assert.match(routeSource, /router\.get\('\/opponent-clubs', listOpponentClubs\)/);
  assert.match(
    routeSource,
    /router\.post\([\s\S]*?'\/opponent-clubs'[\s\S]*?Permission\.MANAGE_EVENTS/,
  );
  assert.match(
    routeSource,
    /router\.post\('\/opponents'[\s\S]*?Permission\.MANAGE_EVENTS[\s\S]*?saveOpponent/,
  );
});
