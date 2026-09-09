import { getStorage } from 'firebase-admin/storage';
import { firebaseAdminApp } from '../lib/firebase-admin';

export interface SharedRuntimeCache {
  get(key: string): Promise<unknown>;
  set(key: string, value: unknown, options: { ttl: number }): Promise<unknown>;
  delete(key: string): Promise<unknown>;
  acquireLease?(key: string, durationMs: number): Promise<(() => Promise<void>) | null>;
}

function code(error: unknown) {
  return typeof error === 'object' && error && 'code' in error ? Number(error.code) : 0;
}

/** Shared scheduler records in the existing private Google bucket. */
export class GoogleRuntimeCache implements SharedRuntimeCache {
  constructor(
    private readonly bucketName: string,
    private readonly namespace: string,
    private readonly storage = getStorage,
  ) {}

  private file(key: string) {
    const app = firebaseAdminApp();
    if (!app) throw new Error('Google runtime credentials unavailable');
    return this.storage(app).bucket(this.bucketName).file(
      `_runtime/${encodeURIComponent(this.namespace)}/${encodeURIComponent(key)}.json`,
    );
  }

  async get(key: string) {
    try {
      const [data] = await this.file(key).download();
      const record = JSON.parse(data.toString('utf8'));
      return Number.isFinite(record.expiresAt) && record.expiresAt > Date.now()
        ? record.value : null;
    } catch (error) {
      if (code(error) === 404) return null;
      throw error;
    }
  }

  async set(key: string, value: unknown, { ttl }: { ttl: number }) {
    await this.file(key).save(JSON.stringify({ value, expiresAt: Date.now() + ttl * 1000 }), {
      resumable: false,
      contentType: 'application/json',
      metadata: { cacheControl: 'private, no-store' },
    });
  }

  async delete(key: string) {
    await this.file(key).delete({ ignoreNotFound: true });
  }

  async acquireLease(key: string, durationMs: number): Promise<(() => Promise<void>) | null> {
    const file = this.file(`lease:${key}`);
    let generation: string | number = 0;
    try {
      const [metadata] = await file.getMetadata();
      generation = metadata.generation!;
      if (Number(metadata.metadata?.leaseExpiresAt) > Date.now()) return null;
    } catch (error) {
      if (code(error) !== 404) throw error;
    }
    try {
      await file.save('', {
        resumable: false,
        preconditionOpts: { ifGenerationMatch: generation },
        metadata: { cacheControl: 'private, no-store', metadata: {
          leaseExpiresAt: String(Date.now() + durationMs),
        } },
      });
    } catch (error) {
      if (code(error) === 412 || code(error) === 409) return null;
      throw error;
    }
    // File.save records the generation it wrote. A reread could see a successor.
    const ownedGeneration = file.metadata.generation;
    if (!ownedGeneration) throw new Error('Google storage did not return the lease generation');
    return async () => {
      try {
        await file.delete({ ifGenerationMatch: ownedGeneration, ignoreNotFound: true });
      } catch (error) {
        if (code(error) !== 412 && code(error) !== 404) throw error;
      }
    };
  }
}
