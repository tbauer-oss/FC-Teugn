import { RequestHandler } from 'express';
import { deferWork, beforeResponseEnd } from './runtime-deferred-work';
import { scheduledWorkCache } from '../services/scheduled-work-cache.service';

export function affectsScheduledWork(method: string, path: string) {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) return false;
  // Routine session renewal and read acknowledgements do not create deadlines.
  return !/^\/auth\/(?:login|refresh|logout|biometric)(?:\/|$)/.test(path) &&
    !/^\/notifications\/(?:read-all|read|[^/]+\/read)(?:\/|$)/.test(path);
}

export const invalidateScheduledWork: RequestHandler = (req, res, next) => {
  if (!affectsScheduledWork(req.method, req.path)) return next();
  const invalidate = async () => {
    try { await scheduledWorkCache.invalidate(); }
    catch (error) {
      console.error('[scheduled-work] invalidation failed', error instanceof Error ? error.name : 'Error');
    }
  };
  // Begin the write without waiting for cache I/O. Both invalidations settle
  // before Cloud Run ends the request and may suspend its CPU.
  deferWork(invalidate());
  if (!beforeResponseEnd(invalidate)) {
    // Supports independently mounted routers; production uses runtimeDeferredWork.
    res.once('finish', () => deferWork(invalidate()));
  }
  next();
};
