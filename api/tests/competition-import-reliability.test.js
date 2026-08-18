const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const controller = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'controllers', 'imports.controller.ts'),
  'utf8',
);
const repository = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'fc_teugn_app',
    'lib',
    'core',
    'data_repository.dart',
  ),
  'utf8',
);

assert.match(
  controller,
  /competitionImportTransactionOptions\s*=\s*\{[\s\S]*maxWait:\s*10_000,[\s\S]*timeout:\s*20_000,/,
  'competition imports need explicit serverless transaction limits',
);
assert.match(
  controller,
  /\},\s*competitionImportTransactionOptions\);/,
  'the import transaction must use the reliability options',
);

const applyStart = controller.indexOf('export async function applyCompetitionImport');
const listStart = controller.indexOf('export async function listCompetitionImports');
const applyBody = controller.slice(applyStart, listStart);
assert.ok(
  applyBody.indexOf('tx.auditLog.create') < applyBody.indexOf('return savedJob'),
  'audit logging must commit atomically with the import response',
);
assert.match(
  repository,
  /\/imports\/competition\/\$importId\/apply[\s\S]*receiveTimeout:\s*const Duration\(seconds:\s*28\)/,
  'the app must wait long enough for the atomic import to finish',
);
assert.match(
  repository,
  /competition-import-\$importId-\$\{sourceWinsConflicts \? 'source-wins' : 'skip'\}-\$selectionKey/,
  'an import apply retry needs a stable operation-specific idempotency key',
);
assert.match(
  repository,
  /if \(sortedRowIds != null\) 'selectedRowIds': sortedRowIds/,
  'the app must submit the explicitly selected preview rows',
);
assert.match(
  applyBody,
  /const selectedRowIds = selectedRowIdsInput == null[\s\S]*const requestedRows = selectedRowIds[\s\S]*job\.rows\.filter\(\(row\) => selectedRowIds\.has\(row\.id\)\)/,
  'the server must only apply rows selected in the preview',
);
assert.match(
  repository,
  /\/imports\/competition\/\$importId\/apply[\s\S]*'retryTransientWrite': true,[\s\S]*'requireOnline': true,/,
  'a transient import failure should retry visibly instead of entering the generic offline queue',
);

console.log('competition import reliability tests passed');
