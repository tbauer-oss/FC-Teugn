const test = require('node:test');
const assert = require('node:assert/strict');

const {
  publicConsentTemplates,
} = require('../dist/src/services/consent-templates');
const {
  buildConsentPdf,
  signatureLayout,
  smoothSignaturePath,
} = require('../dist/src/services/consent-pdf');

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

test('signature PDF layout preserves proportions and uses smooth vector curves', () => {
  const signature = {
    width: 900,
    height: 360,
    strokes: [[
      { x: 120, y: 220 },
      { x: 250, y: 80 },
      { x: 410, y: 240 },
      { x: 680, y: 100 },
      { x: 820, y: 190 },
    ]],
  };
  const layout = signatureLayout(signature);
  const sourceRatio = (820 - 120) / (240 - 80);
  assert.ok(layout.width <= 200);
  assert.ok(layout.height <= 55);
  assert.ok(Math.abs(layout.width / layout.height - sourceRatio) < 0.0001);

  const path = smoothSignaturePath(signature.strokes[0], layout);
  assert.match(path, /^M /);
  assert.match(path, / C /);
  assert.equal(path.includes(' L '), false);
});
