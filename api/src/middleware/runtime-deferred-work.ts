import { AsyncLocalStorage } from 'node:async_hooks';
import { RequestHandler } from 'express';

type DeferredPromise = Promise<unknown> | (() => Promise<unknown>);

type VercelCompatibleRequestContext = {
  waitUntil: (work: DeferredPromise) => void;
  headers: Record<string, string | undefined>;
  url: string;
};

type ContextReader = {
  get: () => VercelCompatibleRequestContext | undefined;
};

const requestContextSymbol = Symbol.for('@vercel/request-context');
const storage = new AsyncLocalStorage<VercelCompatibleRequestContext>();

/**
 * @vercel/functions.waitUntil() reads this request-context bridge. Vercel
 * provides it natively. Cloud Run does not, so we expose an equivalent bridge
 * and delay the response until registered work settles. This preserves the
 * existing post-commit behaviour without allowing important push/sync work to
 * be abandoned after the HTTP response has already been sent.
 */
function ensureCloudRunContextBridge() {
  if (process.env.VERCEL === '1') return;
  const globalWithContext = globalThis as typeof globalThis & {
    [requestContextSymbol]?: ContextReader;
  };
  if (!globalWithContext[requestContextSymbol]) {
    globalWithContext[requestContextSymbol] = {
      get: () => storage.getStore(),
    };
  }
}

ensureCloudRunContextBridge();

export const runtimeDeferredWork: RequestHandler = (req, res, next) => {
  if (process.env.VERCEL === '1') {
    next();
    return;
  }

  const pending = new Set<Promise<unknown>>();
  const context: VercelCompatibleRequestContext = {
    waitUntil(work) {
      let promise: Promise<unknown>;
      try {
        promise = Promise.resolve(typeof work === 'function' ? work() : work);
      } catch (error) {
        promise = Promise.reject(error);
      }
      pending.add(promise);
      void promise.finally(() => pending.delete(promise)).catch(() => undefined);
    },
    headers: Object.fromEntries(
      Object.entries(req.headers).map(([key, value]) => [
        key,
        Array.isArray(value) ? value.join(',') : value,
      ]),
    ),
    url: `${req.protocol}://${req.get('host') ?? 'localhost'}${req.originalUrl}`,
  };

  const originalEnd = res.end.bind(res) as (...args: unknown[]) => unknown;
  let ending = false;

  (res as unknown as { end: (...args: unknown[]) => unknown }).end = (...args: unknown[]) => {
    if (ending) return res;
    ending = true;

    const complete = async () => {
      // Work can enqueue follow-up work while it settles. Drain until stable.
      while (pending.size > 0) {
        await Promise.allSettled(Array.from(pending));
      }
      return originalEnd(...args);
    };

    void complete().catch((error) => {
      console.error(
        '[runtime-deferred-work] deferred request work failed',
        error instanceof Error ? error.name : 'Error',
      );
      originalEnd(...args);
    });
    return res;
  };

  storage.run(context, next);
};
