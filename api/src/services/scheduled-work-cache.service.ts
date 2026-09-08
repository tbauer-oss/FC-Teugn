import { randomUUID } from 'crypto';
import { getCache, RuntimeCache } from '@vercel/functions';
import { runtimeEnvironment } from '../lib/runtime-environment';

export const schedulerSafetySweepMs = 60 * 60_000;
// Vercel's automatic Express runtime currently allows five-minute requests,
// even when the legacy api/index.ts function configuration specifies 30 s.
const mutationGraceMs = 6 * 60_000;
const namespace = `fc-teugn:scheduled-work:v1:${runtimeEnvironment}`;

/** getCache falls back to process-local memory outside the Vercel request
 * context. Such a cache must NEVER decide whether another instance has work.
 * This guarded capability check follows the installed SDK's request-context
 * protocol; if Vercel changes it, we safely resume the ordinary DB scans. */
export function sharedRuntimeCacheAvailable(): boolean {
  if (process.env.VERCEL !== '1' || process.env.NEON_IDLE_GUARD_DISABLED === 'true') return false;
  try {
    const context = (globalThis as Record<symbol, { get?: () => { cache?: RuntimeCache } }>)[
      Symbol.for('@vercel/request-context')
    ]?.get?.();
    if (context?.cache && typeof context.cache.get === 'function' &&
      typeof context.cache.set === 'function') return true;
    // Some Vercel runtimes provide the shared cache through the SDK's HTTP
    // transport instead. Validate its configuration without exposing headers.
    if (process.env.RUNTIME_CACHE_DISABLE_BUILD_CACHE === 'true' ||
      !process.env.RUNTIME_CACHE_ENDPOINT || !process.env.RUNTIME_CACHE_HEADERS) return false;
    const headers = JSON.parse(process.env.RUNTIME_CACHE_HEADERS);
    return headers !== null && typeof headers === 'object' && !Array.isArray(headers);
  } catch { return false; }
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
    private readonly cache: RuntimeCache | null,
    private readonly available: () => boolean = () => true,
  ) {}

  get enabled() { return this.cache !== null && this.available(); }

  async invalidate(now = Date.now()) {
    if (!this.enabled || !this.cache) return;
    // The grace period exceeds a complete Vercel request. A checkpoint taken
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

  async maintenanceDue(key: string, intervalMs: number, task: () => Promise<unknown>, now = Date.now()) {
    if (!this.enabled) return task();
    let lastRun: unknown;
    try { lastRun = await this.cache?.get(`maintenance:${key}`); } catch { /* fail open */ }
    if (typeof lastRun === 'number' && now >= lastRun && now - lastRun < intervalMs) {
      return { skipped: true };
    }
    const result = await task();
    try { await this.cache?.set(`maintenance:${key}`, now, { ttl: Math.ceil(intervalMs / 1000) }); }
    catch { /* A repeated maintenance run is safe; suppress no unfinished work. */ }
    return result;
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
  getCache({ namespace }), sharedRuntimeCacheAvailable,
);
