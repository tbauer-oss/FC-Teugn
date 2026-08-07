const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8');

const schema = read('prisma/schema.prisma');
const migration = read(
  'prisma/migrations/20260807140000_planned_substitution_position/migration.sql',
);
const controller = read('src/controllers/matches.controller.ts');

test('planned substitutions persist the target position explicitly', () => {
  assert.match(
    schema,
    /model PlannedSubstitution[\s\S]*positionCode\s+String\?/,
  );
  assert.match(
    migration,
    /ALTER TABLE "PlannedSubstitution" ADD COLUMN "positionCode" TEXT/,
  );
  assert.match(
    controller,
    /positionCode: text\(substitution\.positionCode, 30\)/,
  );
});
