const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

test('parent homepage preview leaves messages unread and preserves recipient/team scope', async () => {
  const originalLoad = Module._load;
  const queries = [], writes = [];
  let purges = 0;
  const now = new Date();
  const notification = { id: 'note', userId: 'parent', entityType: 'FamilyContact:coach',
    entityId: 'thread.parent.E1', dedupeKey: 'family-contact:message:parent',
    readAt: null, body: 'Bitte früher kommen', createdAt: now, expiresAt: new Date(+now + 86400000) };
  const prisma = {
    notification: {
      findMany: async (query) => { queries.push(query); return [notification, { ...notification, id: 'other', entityId: 'thread.parent.F2' }]; },
      updateMany: async (query) => { writes.push(query); },
    },
    user: { findMany: async () => [{ id: 'coach', name: 'Trainer', role: 'COACH' }, { id: 'parent', name: 'Eltern', role: 'PARENT' }] },
    team: { findMany: async () => [{ id: 'E1', name: 'E1-Jugend', shortName: 'E1' }] },
    familyContactAttachment: { findMany: async () => [] },
  };
  Module._load = function (id, parent, ...args) {
    if (parent?.filename.endsWith('communications.controller.js')) {
      if (id === '../lib/prisma') return { prisma };
      if (id === '../services/team-access') return { accessibleTeamIds: async () => ['E1'], contextualTeamIds: async () => ['E1'] };
      if (id === '../services/privacy-retention.service') return { familyContactRetentionDays: 30, purgeExpiredFamilyContacts: async () => { purges++; } };
      if (id === '../services/notification-scope.service') return { familyContactEntityPrefix: 'FamilyContact:' };
      if (id.startsWith('../services/') || id === '../security/permissions') return {};
    }
    return originalLoad.call(this, id, parent, ...args);
  };
  const filename = require.resolve('../dist/src/controllers/communications.controller');
  let controller;
  try { delete require.cache[filename]; controller = require(filename); }
  finally { Module._load = originalLoad; }
  let result;
  const user = { id: 'parent', role: 'PARENT' }, res = { json: (value) => { result = value; return value; } };
  try {
    for (let poll = 0; poll < 3; poll++) {
      await controller.listFamilyContacts({ user, query: { preview: '1' } }, res);
      assert.equal(result.messages.length, 1, 'only the accessible team is returned');
      assert.equal(result.messages[0].isRead, false);
    }
    assert.equal(purges, 0); assert.deepEqual(writes, []);
    assert.ok(queries.every(q => q.where.userId === user.id && q.where.expiresAt.gt instanceof Date));
    await controller.listFamilyContacts({ user, query: {} }, res);
    assert.equal(result.messages[0].isRead, true);
    assert.equal(purges, 1); assert.equal(writes.length, 1);
    assert.deepEqual(writes[0].where, { id: { in: ['note'] }, userId: 'parent' });
  } finally { delete require.cache[filename]; }
});
