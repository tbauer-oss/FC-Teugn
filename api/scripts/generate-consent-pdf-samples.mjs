import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import {
  publicConsentTemplates,
} from '../dist/src/services/consent-templates.js';
import { buildConsentPdf } from '../dist/src/services/consent-pdf.js';

const output = resolve(process.cwd(), 'output', 'pdf');
await mkdir(output, { recursive: true });

for (const template of publicConsentTemplates()) {
  const bytes = await buildConsentPdf({
    template,
    playerName: 'Max Mustermann',
    playerBirthDate: new Date('2014-04-12T00:00:00Z'),
    signerName: 'Erika Mustermann',
    selections: template.options.slice(0, 2).map((option) => option.id),
    signedAt: new Date('2026-07-30T18:00:00Z'),
    childAssentName: 'Max Mustermann',
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
  await writeFile(
    resolve(output, `${template.type.toLowerCase()}-sample.pdf`),
    bytes,
  );
}
