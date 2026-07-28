import {
  del,
  issueSignedToken,
  presignUrl,
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
  signedReadUrl(pathname: string, validForSeconds?: number): Promise<string>;
  delete(pathname: string): Promise<void>;
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

  async signedReadUrl(pathname: string, validForSeconds = 600) {
    const validUntil = Date.now() + validForSeconds * 1000;
    const token = await issueSignedToken({
      pathname,
      operations: ['get'],
      validUntil,
    });
    const result = await presignUrl(token, {
      operation: 'get',
      pathname,
      access: 'private',
      validUntil,
    });
    return result.presignedUrl;
  }

  async delete(pathname: string) {
    await del(pathname);
  }
}

export const objectStorage: ObjectStorage = new VercelBlobStorage();

