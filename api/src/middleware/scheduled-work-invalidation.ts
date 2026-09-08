import { RequestHandler } from 'express';
import { waitUntil } from '@vercel/functions';
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
  // Start invalidation before AND after the mutation, retained by waitUntil.
  // Cache I/O must not delay saves or goal entry. The second invalidation also
  // invalidates any checkpoint taken before this write finished committing.
  waitUntil(invalidate());
  res.once('finish', () => waitUntil(invalidate()));
  next();
};
