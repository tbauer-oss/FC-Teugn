import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { get, list } from '@vercel/blob';

const execute = process.argv.includes('--execute');
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
      if (destinationExists(pathname)) {
        skipped += 1;
        continue;
      }

      if (!execute) {
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
