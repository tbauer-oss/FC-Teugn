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

export class GoogleCloudStorage implements ObjectStorage {
  constructor(private readonly bucketName: string) {}

  private bucket() {
    if (!this.bucketName) {
      throw new Error(
        'OBJECT_STORAGE_BUCKET is required when OBJECT_STORAGE_PROVIDER=gcs.',
      );
    }
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

export class ObjectStorageError extends Error {
  constructor() { super('Private Google storage is unavailable.'); this.name = 'ObjectStorageError'; }
}

const googleStorage = new GoogleCloudStorage(process.env.OBJECT_STORAGE_BUCKET?.trim() || '');
async function storageOperation<T>(work: () => Promise<T>): Promise<T> {
  try { return await work(); } catch { throw new ObjectStorageError(); }
}

export const objectStorage: ObjectStorage = {
  uploadPrivate: (...args) => storageOperation(() => googleStorage.uploadPrivate(...args)),
  readPrivate: (...args) => storageOperation(() => googleStorage.readPrivate(...args)),
  delete: (...args) => storageOperation(() => googleStorage.delete(...args)),
};
