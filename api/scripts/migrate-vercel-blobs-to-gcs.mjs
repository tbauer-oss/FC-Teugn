import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { get, list } from '@vercel/blob';
import jwt from 'jsonwebtoken';

const execute = process.argv.includes('--execute');
const verify = process.argv.includes('--verify');
const sha256 = data => createHash('sha256').update(data).digest('hex');
const bucketName = process.env.OBJECT_STORAGE_BUCKET?.trim();
const hasStaticToken = Boolean(process.env.BLOB_READ_WRITE_TOKEN?.trim());
const hasOidc = Boolean(
  process.env.VERCEL_OIDC_TOKEN?.trim() && process.env.BLOB_STORE_ID?.trim(),
);

if (!hasStaticToken && !hasOidc) {
  throw new Error(
    'Vercel Blob authentication is required (OIDC with BLOB_STORE_ID or BLOB_READ_WRITE_TOKEN).',
  );
}
if (!bucketName) {
  throw new Error('OBJECT_STORAGE_BUCKET is required.');
}

// Vercel cannot export sensitive values. Verify signing compatibility through
// rejected synthetic requests; never create a session or impersonate a user.
async function verifyRuntimeSecrets() {
  const project = process.env.GCP_PROJECT_ID?.trim();
  if (!project) throw new Error('GCP_PROJECT_ID is required for cutover verification.');
  const readGoogle = name => execFileSync('gcloud', [
    'secrets', 'versions', 'access', 'latest', `--secret=${name}`, `--project=${project}`,
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  const accessToken = jwt.sign({
    id: `cutover-probe-${randomUUID()}`, role: 'PARENT', status: 'PENDING', teamId: '',
  }, readGoogle('ACCESS_TOKEN_SECRET'), { expiresIn: '60s' });
  // Missing session claims yield a distinct rejection only after signature
  // validation, before any refresh-session lookup or mutation.
  const refreshToken = jwt.sign({ cutoverProbe: randomUUID() },
    readGoogle('REFRESH_TOKEN_SECRET'), { expiresIn: '60s' });
  const targets = [
    ['Google', 'https://app.fc-teugn-talents.de/api'],
    ['legacy Vercel address', 'https://fc-teugn-backend.vercel.app'],
  ];
  let signingCompatible = true;
  for (const [label, base] of targets) {
    let targetCompatible = true;
    for (const [path, options, expected] of [
      ['/auth/me', { headers: { authorization: `Bearer ${accessToken}` } },
        'Account nicht gefunden.'],
      ['/auth/refresh', { method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ refreshToken }) }, 'Ungültige Sitzung.'],
    ]) {
      const response = await fetch(`${base}${path}`, {
        ...options, redirect: 'error', signal: AbortSignal.timeout(20_000),
      });
      const body = await response.json();
      if (response.status !== 401 || body.message !== expected) {
        const reason = ['Invalid token', 'Sitzung ist abgelaufen.'].includes(body.message)
          ? 'signature rejected' : 'unexpected response';
        console.error(`Signing probe for ${label} ${path}: HTTP ${response.status}, ${reason}.`);
        targetCompatible = false;
        signingCompatible = false;
      }
    }
    if (targetCompatible) console.log(`Access and refresh signing compatibility confirmed for ${label}.`);
  }
  if (!signingCompatible) throw new Error('Legacy session compatibility is not confirmed; do not cut over.');
  if (process.env.DATABASE_URL?.startsWith('postgres')) {
    const sourceDatabase = new URL(process.env.DATABASE_URL);
    const targetDatabase = new URL(readGoogle('DATABASE_URL'));
    const identity = url => [url.hostname.replace('-pooler.', '.'), url.port || '5432',
      url.pathname, url.username, url.password].join('\n');
    if (sha256(identity(sourceDatabase)) !== sha256(identity(targetDatabase))) {
      throw new Error('Source and target database identity differs; do not cut over.');
    }
    console.log('Database connection identity matches.');
  } else {
    console.log('Vercel database secret is not exportable; direct database identity comparison unavailable.');
  }
}
if (process.argv.includes('--verify-sessions')) await verifyRuntimeSecrets();

function storageUri(pathname) {
  return `gs://${bucketName}/${pathname}`;
}

function destinationExists(pathname) {
  try {
    execFileSync(
      'gcloud',
      ['storage', 'objects', 'describe', storageUri(pathname), '--format=value(name)'],
      { stdio: 'ignore' },
    );
    return true;
  } catch {
    return false;
  }
}

function uploadToGoogleCloud(pathname, data, contentType) {
  const directory = mkdtempSync(join(tmpdir(), 'fc-teugn-blob-'));
  const temporaryFile = join(directory, 'blob');
  const uri = storageUri(pathname);

  try {
    writeFileSync(temporaryFile, data);
    execFileSync('gcloud', ['storage', 'cp', temporaryFile, uri, '--quiet'], {
      stdio: 'ignore',
    });
    execFileSync(
      'gcloud',
      [
        'storage',
        'objects',
        'update',
        uri,
        `--content-type=${contentType || 'application/octet-stream'}`,
        '--cache-control=private, max-age=300, no-transform',
        `--update-custom-metadata=migratedFrom=vercel-blob,originalPathname=${pathname}`,
        '--quiet',
      ],
      { stdio: 'ignore' },
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

let cursor;
let discovered = 0;
let copied = 0;
let skipped = 0;
let pending = 0;
let failed = 0;
let verified = 0;

console.log(
  execute
    ? 'Copying private Vercel blobs to Google Cloud Storage without deleting the source.'
    : 'DRY RUN: scanning private Vercel blobs without exposing pathnames.',
);

do {
  const page = await list({ cursor, limit: 1000 });
  for (const blob of page.blobs) {
    discovered += 1;
    const pathname = blob.pathname;

    try {
      const exists = destinationExists(pathname);
      if (exists && !verify) {
        skipped += 1;
        continue;
      }

      if (!execute && !exists) {
        pending += 1;
        continue;
      }

      const source = await get(pathname, { access: 'private' });
      if (!source || source.statusCode !== 200) {
        throw new Error(`Vercel Blob returned status ${source?.statusCode ?? 'missing'}`);
      }

      const reader = source.stream.getReader();
      const chunks = [];
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(Buffer.from(value));
      }
      const data = Buffer.concat(chunks);

      if (exists) {
        const destination = execFileSync('gcloud', ['storage', 'cat', storageUri(pathname)], {
          maxBuffer: 128 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'],
        });
        if (sha256(destination) !== sha256(data)) throw new Error('Storage checksum mismatch');
        verified++;
        continue;
      }
      uploadToGoogleCloud(
        pathname,
        data,
        source.blob.contentType || 'application/octet-stream',
      );

      copied += 1;
    } catch (error) {
      failed += 1;
      console.error(
        'A blob migration item failed:',
        error instanceof Error ? error.name : 'Error',
      );
    }
  }

  cursor = page.hasMore ? page.cursor : undefined;
} while (cursor);

console.log(
  JSON.stringify(
    {
      mode: execute ? 'execute' : 'dry-run',
      discovered,
      pending,
      copied,
      skipped,
      failed,
      verified,
      bucket: bucketName,
      authentication: hasOidc ? 'vercel-oidc' : 'static-token',
    },
    null,
    2,
  ),
);

if (failed > 0) {
  process.exitCode = 1;
}
