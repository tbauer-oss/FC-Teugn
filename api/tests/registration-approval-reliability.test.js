const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  canLimitedManagerUpdateMember,
  limitedManagerTeamAssignmentAllowed,
} = require('../dist/src/controllers/admin.controller');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('limited staff can approve but cannot escalate or disable accounts', () => {
  assert.equal(
    canLimitedManagerUpdateMember('PENDING', 'PARENT', 'APPROVED', 'PARENT'),
    true,
  );
  assert.equal(
    canLimitedManagerUpdateMember('PENDING', 'PARENT', 'APPROVED', 'COACH'),
    false,
  );
  assert.equal(
    canLimitedManagerUpdateMember('APPROVED', 'PARENT', 'APPROVED', 'PARENT'),
    true,
  );
  assert.equal(
    canLimitedManagerUpdateMember('APPROVED', 'PARENT', 'BLOCKED', 'PARENT'),
    false,
  );
});

test('a second youth may add only its own child relation later', () => {
  assert.equal(
    limitedManagerTeamAssignmentAllowed(
      'APPROVED',
      ['team-f1'],
      [],
      ['team-f1'],
    ),
    true,
  );
  assert.equal(
    limitedManagerTeamAssignmentAllowed(
      'APPROVED',
      ['team-f1', 'team-e1'],
      [],
      ['team-f1'],
    ),
    false,
  );
  assert.equal(
    limitedManagerTeamAssignmentAllowed(
      'APPROVED',
      ['team-e2'],
      ['team-e1'],
      ['team-e1', 'team-e2'],
    ),
    false,
  );
});

test('multi-child approvals are scoped and committed atomically', () => {
  const admin = source('src/controllers/admin.controller.ts');
  const teamAccess = source('src/services/team-access.ts');

  assert.match(admin, /guardianLinks\?: Array/);
  assert.match(admin, /guardianAssignments = new Map/);
  assert.match(admin, /teamId:\s*\{[\s\S]*limitedManager[\s\S]*managementTeamIds/);
  assert.match(admin, /prisma\.\$transaction\(async \(tx\)/);
  assert.match(admin, /for \(const \[assignedPlayerId, assignedRelationship\]/);
  assert.match(admin, /tx\.parentPlayerLink\.upsert/);
  assert.match(admin, /parentId_playerId/);
  assert.match(admin, /tx\.user\.updateMany\([\s\S]*status: AccountStatus\.PENDING/);
  assert.match(admin, /RegistrationApprovalConflict/);
  assert.match(admin, /TransactionIsolationLevel\.Serializable/);
  assert.match(admin, /error\.code === 'P2034'/);
  assert.match(admin, /status\(409\)/);

  assert.match(teamAccess, /Member administration deliberately ignores family links/);
  assert.match(teamAccess, /memberManagementTeamIds/);
});
