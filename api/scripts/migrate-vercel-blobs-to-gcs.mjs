import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { get, list } from '@vercel/blob';

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

// Existing apps must be able to renew their sessions through the bridge.
function verifyRuntimeSecrets() {
  const project = process.env.GCP_PROJECT_ID?.trim();
  if (!project) throw new Error('GCP_PROJECT_ID is required for cutover verification.');
  const readGoogle = name => execFileSync('gcloud', [
    'secrets', 'versions', 'access', 'latest', `--secret=${name}`, `--project=${project}`,
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  for (const name of ['ACCESS_TOKEN_SECRET', 'REFRESH_TOKEN_SECRET']) {
    const source = process.env[name]?.trim() || process.env.JWT_SECRET?.trim();
    if (!source || sha256(source) !== sha256(readGoogle(name))) {
      throw new Error(`Session signing configuration differs for ${name}; do not cut over.`);
    }
  }
  const sourceDatabase = new URL(process.env.DATABASE_URL);
  const targetDatabase = new URL(readGoogle('DATABASE_URL'));
  const identity = url => [url.hostname.replace('-pooler.', '.'), url.port || '5432',
    url.pathname, url.username, url.password].join('\n');
  if (sha256(identity(sourceDatabase)) !== sha256(identity(targetDatabase))) {
    throw new Error('Source and target database identity differs; do not cut over.');
  }
  console.log('Session signing secrets and database identity match; no secret values are logged.');
}
if (verify) verifyRuntimeSecrets();

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
