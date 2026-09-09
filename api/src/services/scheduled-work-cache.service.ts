import { randomUUID } from 'crypto';
import { GoogleRuntimeCache, SharedRuntimeCache } from './google-runtime-cache';
import { runtimeEnvironment } from '../lib/runtime-environment';

export const schedulerSafetySweepMs = 60 * 60_000;
// Cloud Run requests are limited to five minutes in our deployment.
const mutationGraceMs = 6 * 60_000;
const namespace = `fc-teugn:scheduled-work:v1:${runtimeEnvironment}`;

export function sharedRuntimeCacheAvailable(): boolean {
  return Boolean(process.env.OBJECT_STORAGE_BUCKET?.trim()) &&
    process.env.NEON_IDLE_GUARD_DISABLED !== 'true';
}

type Revision = { id: string; busyUntil: number };
type Plan = { revision: string; checkedAt: number; nextDueAt: number };

function revisionValue(value: unknown): Revision | null {
  if (!value || typeof value !== 'object') return null;
  const item = value as Revision;
  return typeof item.id === 'string' && Number.isFinite(item.busyUntil) ? item : null;
}

/** The cache only suppresses empty DB scans. It never stores recipients, ticker
 * payloads or authorization decisions. Missing/expired/broken entries run the
 * normal worker. An hourly sweep also catches changes made outside the API. */
export class ScheduledWorkCache {
  constructor(
    private readonly cache: SharedRuntimeCache | null,
    private readonly available: () => boolean = () => true,
  ) {}

  get enabled() { return this.cache !== null && this.available(); }

  async invalidate(now = Date.now()) {
    if (!this.enabled || !this.cache) return;
    // The grace period exceeds a complete Cloud Run request. A checkpoint taken
    // while a mutation is in flight cannot hide work committed afterwards.
    await Promise.all([
      this.cache.set('revision', {
        id: randomUUID(), busyUntil: now + mutationGraceMs,
      }, { ttl: 86_400 }),
      this.cache.delete('plan'),
    ]);
  }

  async shouldRun(now = Date.now()): Promise<boolean> {
    if (!this.enabled || !this.cache) return true;
    try {
      const [rawRevision, rawPlan] = await Promise.all([
        this.cache.get('revision'), this.cache.get('plan'),
      ]);
      const revision = revisionValue(rawRevision);
      if (!revision || revision.busyUntil > now || !rawPlan || typeof rawPlan !== 'object') return true;
      const plan = rawPlan as Plan;
      return plan.revision !== revision.id ||
        !Number.isFinite(plan.checkedAt) || !Number.isFinite(plan.nextDueAt) ||
        plan.checkedAt < revision.busyUntil || plan.checkedAt > now ||
        now >= plan.nextDueAt || now - plan.checkedAt >= schedulerSafetySweepMs;
    } catch {
      return true;
    }
  }

  async checkpoint(readNextDueAt: () => Promise<number>, now = Date.now()) {
    if (!this.enabled || !this.cache) return;
    try {
      const revision = revisionValue(await this.cache.get('revision'));
      if (!revision) {
        // Never overwrite a concurrent mutation with an immediately usable
        // empty revision: initialization carries the same in-flight grace.
        await this.invalidate(now);
        return;
      }
      if (revision.busyUntil > now) return;
      const nextDueAt = Math.min(await readNextDueAt(), now + schedulerSafetySweepMs);
      if (!Number.isFinite(nextDueAt)) return;
      await this.cache.set('plan', { revision: revision.id, checkedAt: now, nextDueAt }, {
        ttl: Math.ceil(schedulerSafetySweepMs / 1000),
      });
      // The plan embeds the pre-scan revision. A concurrent invalidation makes
      // it unusable even if the stale plan is written after the invalidation.
    } catch (error) {
      console.warn('[scheduled-work] checkpoint unavailable; normal scans retained', error instanceof Error ? error.name : 'Error');
    }
  }

  async acquireWorkerLease() {
    if (!this.enabled || !this.cache?.acquireLease) return async () => {};
    // A storage outage must fail the request so Cloud Scheduler retries it.
    return this.cache.acquireLease('worker', mutationGraceMs);
  }

  async maintenanceDue(key: string, intervalMs: number, task: () => Promise<unknown>, now = Date.now()) {
    if (!this.enabled || !this.cache) return task();
    const release = this.cache.acquireLease
      ? await this.cache.acquireLease(`maintenance:${key}`, mutationGraceMs)
      : async () => {};
    if (!release) return { skipped: true };
    try {
      const lastRun = await this.cache.get(`maintenance:${key}`);
      if (typeof lastRun === 'number' && now >= lastRun && now - lastRun < intervalMs) {
        return { skipped: true };
      }
      const result = await task();
      await this.cache.set(`maintenance:${key}`, now, { ttl: Math.ceil(intervalMs / 1000) });
      return result;
    } finally {
      await release();
    }
  }

  async nextMaintenanceAt(key: string, intervalMs: number, now = Date.now()) {
    if (!this.enabled) return now;
    try {
      const lastRun = await this.cache?.get(`maintenance:${key}`);
      return typeof lastRun === 'number' && Number.isFinite(lastRun) && lastRun <= now
        ? lastRun + intervalMs : now;
    } catch { return now; }
  }
}

export const scheduledWorkCache = new ScheduledWorkCache(
  new GoogleRuntimeCache(process.env.OBJECT_STORAGE_BUCKET?.trim() || '', namespace),
  sharedRuntimeCacheAvailable,
);
