import {
  del,
  get,
  put,
} from '@vercel/blob';
import { getStorage } from 'firebase-admin/storage';
import { firebaseAdminApp } from '../lib/firebase-admin';

export interface StoredObject {
  pathname: string;
  url: string;
}

export interface ObjectStorage {
  uploadPrivate(
    pathname: string,
    data: Buffer,
    contentType: string,
  ): Promise<StoredObject>;
  readPrivate(pathname: string): Promise<StoredObjectContent | null>;
  delete(pathname: string): Promise<void>;
}

export interface StoredObjectContent {
  data: Buffer;
  contentType: string;
  size: number;
  etag: string;
}

export class VercelBlobStorage implements ObjectStorage {
  async uploadPrivate(
    pathname: string,
    data: Buffer,
    contentType: string,
  ): Promise<StoredObject> {
    const blob = await put(pathname, data, {
      access: 'private',
      contentType,
      addRandomSuffix: true,
      cacheControlMaxAge: 300,
    });
    return { pathname: blob.pathname, url: blob.url };
  }

  async readPrivate(pathname: string): Promise<StoredObjectContent | null> {
    const result = await get(pathname, { access: 'private' });
    if (!result || result.statusCode !== 200) return null;

    const reader = result.stream.getReader();
    const chunks: Uint8Array[] = [];
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    return {
      data: Buffer.concat(chunks.map((chunk) => Buffer.from(chunk))),
      contentType: result.blob.contentType,
      size: result.blob.size,
      etag: result.blob.etag,
    };
  }

  async delete(pathname: string) {
    await del(pathname);
  }
}

export class GoogleCloudStorage implements ObjectStorage {
  constructor(private readonly bucketName: string) {
    if (!bucketName) {
      throw new Error(
        'OBJECT_STORAGE_BUCKET is required when OBJECT_STORAGE_PROVIDER=gcs.',
      );
    }
  }

  private bucket() {
    const app = firebaseAdminApp();
    if (!app) {
      throw new Error(
        'Firebase Admin is not configured for Google Cloud Storage.',
      );
    }
    return getStorage(app).bucket(this.bucketName);
  }

  async uploadPrivate(
    pathname: string,
    data: Buffer,
    contentType: string,
  ): Promise<StoredObject> {
    const file = this.bucket().file(pathname);
    await file.save(data, {
      resumable: false,
      contentType,
      metadata: {
        cacheControl: 'private, max-age=300, no-transform',
      },
    });

    return {
      pathname,
      url: `gs://${this.bucketName}/${pathname}`,
    };
  }

  async readPrivate(pathname: string): Promise<StoredObjectContent | null> {
    const file = this.bucket().file(pathname);
    const [exists] = await file.exists();
    if (!exists) return null;

    const [data] = await file.download();
    const [metadata] = await file.getMetadata();
    return {
      data,
      contentType: metadata.contentType || 'application/octet-stream',
      size: Number(metadata.size || data.length),
      etag: metadata.etag || '',
    };
  }

  async delete(pathname: string) {
    await this.bucket().file(pathname).delete({ ignoreNotFound: true });
  }
}

function createObjectStorage(): ObjectStorage {
  const provider = (process.env.OBJECT_STORAGE_PROVIDER || 'vercel')
    .trim()
    .toLowerCase();

  if (provider === 'gcs' || provider === 'google') {
    return new GoogleCloudStorage(
      process.env.OBJECT_STORAGE_BUCKET?.trim() || '',
    );
  }

  if (provider !== 'vercel') {
    throw new Error(`Unsupported OBJECT_STORAGE_PROVIDER: ${provider}`);
  }

  return new VercelBlobStorage();
}

export const objectStorage: ObjectStorage = createObjectStorage();
