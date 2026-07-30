const test = require('node:test');
const assert = require('node:assert/strict');

const {
  publicConsentTemplates,
} = require('../dist/src/services/consent-templates');
const { buildConsentPdf } = require('../dist/src/services/consent-pdf');

test('consent templates are separate, versioned and granular', () => {
  const templates = publicConsentTemplates();
  assert.deepEqual(
    templates.map((item) => item.type).sort(),
    ['COMMUNICATION', 'MEDICAL_DATA', 'PHOTO', 'TEAM_PHOTO', 'TRANSPORT'],
  );
  for (const template of templates) {
    assert.match(template.version, /^\d{4}-\d{2}-\d{2}\.\d+$/);
    assert.ok(template.options.length >= 4);
    assert.ok(template.purpose.length > 30);
    assert.ok(template.legalBasis.includes('Art.'));
    assert.ok(template.retention.length > 30);
  }
  assert.equal(
    templates.find((item) => item.type === 'MEDICAL_DATA').explicit,
    true,
  );
});

test('blank and signed consent PDFs are valid PDF documents', async () => {
  const template = publicConsentTemplates().find(
    (item) => item.type === 'PHOTO',
  );
  const blank = await buildConsentPdf({ template });
  const signed = await buildConsentPdf({
    template,
    playerName: 'Max Mustermann',
    playerBirthDate: new Date('2014-04-12T00:00:00Z'),
    signerName: 'Erika Mustermann',
    selections: ['APP_INTERNAL', 'CLUB_WEBSITE'],
    signedAt: new Date('2026-07-30T18:00:00Z'),
    documentHash: 'a'.repeat(64),
    signature: {
      width: 300,
      height: 150,
      strokes: [[
        { x: 10, y: 90 },
        { x: 60, y: 30 },
        { x: 110, y: 100 },
        { x: 180, y: 35 },
        { x: 250, y: 80 },
      ]],
    },
  });
  assert.equal(Buffer.from(blank).subarray(0, 4).toString(), '%PDF');
  assert.equal(Buffer.from(signed).subarray(0, 4).toString(), '%PDF');
  assert.ok(signed.length > blank.length);
});
