const test = require('node:test');
const assert = require('node:assert/strict');

const { Permission, hasPermission } = require('../dist/src/security/permissions');
const { Role } = require('../dist/src/types/enums');

test('club administrators can manage the organization', () => {
  assert.equal(
    hasPermission(Role.CLUB_ADMIN, Permission.MANAGE_ORGANIZATION),
    true,
  );
});

test('coaches can manage players and events but not the organization', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_PLAYERS), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_EVENTS), true);
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_ORGANIZATION),
    false,
  );
});

test('parents can respond to attendance without changing team data', () => {
  assert.equal(
    hasPermission(Role.PARENT, Permission.RESPOND_ATTENDANCE),
    true,
  );
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_PLAYERS), false);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_EVENTS), false);
});

test('read-only members cannot mutate data', () => {
  assert.equal(hasPermission(Role.READ_ONLY, Permission.VIEW_TEAM), true);
  assert.equal(hasPermission(Role.READ_ONLY, Permission.MANAGE_TEAM), false);
});
