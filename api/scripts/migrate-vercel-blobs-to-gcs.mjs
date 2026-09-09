import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { get, list } from '@vercel/blob';

const execute = process.argv.includes('--execute');
const bucketName = process.env.OBJECT_STORAGE_BUCKET?.trim();

if (!process.env.BLOB_READ_WRITE_TOKEN?.trim()) {
  throw new Error('BLOB_READ_WRITE_TOKEN is required.');
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
      stdio: 'inherit',
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
      { stdio: 'inherit' },
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

let cursor;
let discovered = 0;
let copied = 0;
let skipped = 0;
let failed = 0;

console.log(
  execute
    ? `Copying private Vercel blobs to gs://${bucketName} without deleting the source.`
    : `DRY RUN: scanning Vercel blobs for migration to gs://${bucketName}.`,
);

do {
  const page = await list({ cursor, limit: 1000 });
  for (const blob of page.blobs) {
    discovered += 1;
    const pathname = blob.pathname;

    try {
      if (destinationExists(pathname)) {
        skipped += 1;
        console.log(`SKIP ${pathname} (already exists)`);
        continue;
      }

      if (!execute) {
        console.log(`WOULD COPY ${pathname}`);
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
      console.log(`COPIED ${pathname} (${data.length} bytes)`);
    } catch (error) {
      failed += 1;
      console.error(`FAILED ${pathname}:`, error instanceof Error ? error.message : error);
    }
  }

  cursor = page.hasMore ? page.cursor : undefined;
} while (cursor);

console.log(
  JSON.stringify(
    {
      mode: execute ? 'execute' : 'dry-run',
      discovered,
      copied,
      skipped,
      failed,
      bucket: bucketName,
    },
    null,
    2,
  ),
);

if (failed > 0) {
  process.exitCode = 1;
}
