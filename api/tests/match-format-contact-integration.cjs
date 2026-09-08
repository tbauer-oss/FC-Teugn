const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

module.exports = async ({ prisma, team, coach, parent, stranger }) => {
  const events = require('../dist/src/controllers/events.controller');
  const matches = require('../dist/src/controllers/matches.controller');
  const contacts = require('../dist/src/controllers/communications.controller');
  const { objectStorage } = require('../dist/src/services/object-storage');
  const call = async (fn, user, body = {}, params = {}, query = {}) => {
    let status = 200, result;
    const res = { status: n => { status = n; return res; }, json: v => { result = v; return res; }, send: () => res, set: () => res };
    await fn({ user, body, params, query }, res);
    return { status, result };
  };
  // A per-match override must not alter the team, and every read/edit path must preserve it.
  const created = await call(events.createEvent, coach, {
    category: 'FRIENDLY_MATCH', title: 'Format-Test', startAt: '2031-06-10T15:00:00Z',
    location: 'Testplatz', teamIds: [team.id], opponent: 'Testgegner', homeAway: 'HOME',
    gameFormat: 'FOOTBALL_5', periodCount: 5, periodMinutes: 12, notificationMode: 'NONE',
  });
  assert.equal(created.status, 201, JSON.stringify(created.result));
  const eventId = created.result.id;
  assert.ok(eventId, JSON.stringify(created.result));
  assert.equal((await prisma.matchDetails.findUnique({ where: { eventId } })).gameFormat, 'FOOTBALL_5');
  const view = await call(matches.getMatch, coach, {}, { id: eventId });
  assert.equal(view.result.teamGameFormat, 'FOOTBALL_5');
  assert.equal((await prisma.team.findUnique({ where: { id: team.id } })).gameFormat, 'FOOTBALL_7');
  const squad = await prisma.squad.create({ data: { eventId, formation: '1-2-1', lineup: { create: { formation: '1-2-1', fieldSize: 5 } } } });
  const edited = await call(events.upsertMatchDetails, coach, { opponent: 'Testgegner', gameFormat: 'FOOTBALL_7' }, { id: eventId });
  assert.equal(edited.status, 200);
  assert.equal(edited.result.gameFormat, 'FOOTBALL_7');
  assert.equal(await prisma.lineup.count({ where: { squadId: squad.id } }), 0);
  const unchanged = await call(events.upsertMatchDetails, coach, { opponent: 'Testgegner', notes: 'Unverändert' }, { id: eventId });
  assert.equal(unchanged.result.gameFormat, 'FOOTBALL_7');
  const invalid = await call(events.upsertMatchDetails, coach, { opponent: 'Testgegner', gameFormat: 'FOOTBALL_11' }, { id: eventId });
  assert.equal(invalid.status, 400);
  await call(events.updateEvent, coach, { gameFormat: 'FOOTBALL_5' }, { id: eventId });
  assert.equal((await prisma.matchDetails.findUnique({ where: { eventId } })).gameFormat, 'FOOTBALL_5');
  await call(matches.updateMatch, coach, { opponent: 'Testgegner', gameFormat: 'FOOTBALL_7' }, { id: eventId });
  assert.equal((await prisma.matchDetails.findUnique({ where: { eventId } })).gameFormat, 'FOOTBALL_7');
  await prisma.matchDetails.update({ where: { eventId }, data: { status: 'LIVE' } });
  await assert.rejects(call(events.upsertMatchDetails, coach, { opponent: 'Testgegner', gameFormat: 'FOOTBALL_5' }, { id: eventId }), e => e.status === 409);
  assert.equal((await prisma.matchDetails.findUnique({ where: { eventId } })).gameFormat, 'FOOTBALL_7');
  await prisma.event.delete({ where: { id: eventId } });
  console.log('PASS per-match format creation, all editors, invalid age, lineup reset, legacy edit and live guard');

  const conversationId = `${randomUUID()}.${parent.id}.${team.id}`;
  async function message(content) {
    const id = randomUUID();
    const rows = await Promise.all([coach, parent].map(user => prisma.notification.create({ data: {
      userId: user.id, category: 'ANNOUNCEMENT', title: 'Test', body: content,
      entityType: `FamilyContact:${coach.id}`, entityId: conversationId,
      dedupeKey: `family-contact:${id}:${user.id}`, expiresAt: new Date(Date.now() + 86400000),
    } })));
    return { id, rows };
  }
  const first = await message('Eins');
  const second = await message('Zwei');
  const asset = await prisma.fileAsset.create({ data: { kind: 'FAMILY_CONTACT_ATTACHMENT', pathname: 'synthetic/test.pdf', storageUrl: 'https://example.invalid/test.pdf', originalName: 'test.pdf', contentType: 'application/pdf', size: 5, checksum: 'synthetic', uploadedById: coach.id, ownerTeamId: team.id, isPrivate: true } });
  await prisma.familyContactAttachment.create({ data: { messageId: first.id, conversationId, teamId: team.id, uploadedById: coach.id, fileAssetId: asset.id, expiresAt: new Date(Date.now() + 86400000) } });
  await prisma.notificationDelivery.create({ data: { notificationId: first.rows[1].id, userId: parent.id } });
  assert.equal((await call(contacts.deleteFamilyContact, parent, {}, { id: first.rows[1].id })).status, 403);
  assert.equal((await call(contacts.deleteFamilyContact, { ...stranger, role: 'COACH' }, {}, { id: first.rows[0].id })).status, 404);
  const originalDelete = objectStorage.delete;
  try {
    objectStorage.delete = async () => { throw new Error('temporary storage failure'); };
    await assert.rejects(call(contacts.deleteFamilyContact, coach, {}, { id: first.rows[0].id }));
    assert.equal(await prisma.notification.count({ where: { entityId: conversationId } }), 4);
    assert.equal(await prisma.fileAsset.count({ where: { id: asset.id } }), 1);
    const deletedPaths = [];
    objectStorage.delete = async path => deletedPaths.push(path);
    assert.equal((await call(contacts.deleteFamilyContact, coach, {}, { id: first.rows[0].id })).status, 204);
    assert.deepEqual(deletedPaths, ['synthetic/test.pdf']);
    assert.equal(await prisma.notification.count({ where: { entityId: conversationId } }), 2);
    assert.equal(await prisma.fileAsset.count({ where: { id: asset.id } }), 0);
    assert.equal(await prisma.notificationDelivery.count({ where: { notificationId: first.rows[1].id } }), 0);
    assert.equal((await call(contacts.deleteFamilyContact, coach, {}, { id: second.rows[0].id }, { conversation: 'true' })).status, 204);
    assert.equal(await prisma.notification.count({ where: { entityId: conversationId } }), 0);
  } finally { objectStorage.delete = originalDelete; }
  console.log('PASS delete for all: staff scope, individual message, full conversation, attachment, delivery cascade and storage failure retry');
  const sent = await call(contacts.sendFamilyContact, parent, { teamId: team.id, message: 'Atomar gesendete Testnachricht' });
  assert.equal(sent.status, 201);
  const sentCopies = await prisma.notification.findMany({ where: { entityId: sent.result.conversationId } });
  assert.equal(sentCopies.length, 2);
  assert.ok(sentCopies.every(n => n.body === 'Atomar gesendete Testnachricht'));
  const coachCopy = sentCopies.find(n => n.userId === coach.id);
  assert.ok(coachCopy);
  assert.equal((await call(contacts.deleteFamilyContact, coach, {}, { id: coachCopy.id })).status, 204);
  assert.equal(await prisma.notification.count({ where: { entityId: sent.result.conversationId } }), 0);
  console.log('PASS real send creates all recipient copies atomically and can be deleted');
};
