import {
  del,
  get,
  put,
} from '@vercel/blob';

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

export const objectStorage: ObjectStorage = new VercelBlobStorage();

