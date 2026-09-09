import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { get, list } from '@vercel/blob';

const execute = process.argv.includes('--execute');
const bucketName = process.env.OBJECT_STORAGE_BUCKET?.trim();
const projectId =
  process.env.GOOGLE_CLOUD_PROJECT?.trim() ||
  process.env.GCLOUD_PROJECT?.trim() ||
  process.env.FIREBASE_PROJECT_ID?.trim();

if (!process.env.BLOB_READ_WRITE_TOKEN?.trim()) {
  throw new Error('BLOB_READ_WRITE_TOKEN is required.');
}
if (!bucketName) {
  throw new Error('OBJECT_STORAGE_BUCKET is required.');
}

const app = initializeApp({
  credential: applicationDefault(),
  ...(projectId ? { projectId } : {}),
});
const bucket = getStorage(app).bucket(bucketName);

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
    const destination = bucket.file(pathname);

    try {
      const [exists] = await destination.exists();
      if (exists) {
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

      await destination.save(data, {
        resumable: false,
        contentType: source.blob.contentType || 'application/octet-stream',
        metadata: {
          cacheControl: 'private, max-age=300, no-transform',
          metadata: {
            migratedFrom: 'vercel-blob',
            originalPathname: pathname,
          },
        },
      });

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
