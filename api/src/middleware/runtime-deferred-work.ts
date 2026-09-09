import { AsyncLocalStorage } from 'node:async_hooks';
import { RequestHandler } from 'express';

type Work = Promise<unknown> | (() => Promise<unknown>);
type RequestWork = {
  pending: Set<Promise<unknown>>;
  beforeEnd: Array<() => Promise<unknown>>;
};
const storage = new AsyncLocalStorage<RequestWork>();

/** Keep the Cloud Run request open until registered work has settled. */
export function deferWork(work: Work) {
  const context = storage.getStore();
  const promise = Promise.resolve().then(() => typeof work === 'function' ? work() : work);
  context?.pending.add(promise);
  void promise.catch(error => {
    console.error('[deferred-work] task failed', error instanceof Error ? error.name : 'Error');
  }).finally(() => context?.pending.delete(promise));
}

export function beforeResponseEnd(work: () => Promise<unknown>) {
  const context = storage.getStore();
  if (!context) return false;
  context.beforeEnd.push(work);
  return true;
}

export const runtimeDeferredWork: RequestHandler = (_req, res, next) => {
  const context: RequestWork = { pending: new Set(), beforeEnd: [] };
  const originalEnd = res.end.bind(res) as (...args: unknown[]) => unknown;
  let ending = false;
  (res as unknown as { end: (...args: unknown[]) => unknown }).end = (...args: unknown[]) => {
    if (ending) return res;
    ending = true;
    void (async () => {
      await Promise.allSettled(context.beforeEnd.map(work => Promise.resolve().then(work)));
      while (context.pending.size) await Promise.allSettled([...context.pending]);
    })().catch(error => {
      console.error('[deferred-work] response drain failed', error instanceof Error ? error.name : 'Error');
    }).finally(() => originalEnd(...args));
    return res;
  };
  storage.run(context, next);
};
