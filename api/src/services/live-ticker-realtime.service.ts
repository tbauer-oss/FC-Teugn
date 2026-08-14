type LiveTickerUpdateListener = () => void;

type WaitForLiveTickerUpdateOptions = {
  eventId: string;
  after: number;
  waitMs: number;
  pollIntervalMs?: number;
  readSequence: () => Promise<number>;
};

const listenersByEvent = new Map<string, Set<LiveTickerUpdateListener>>();

function delay(milliseconds: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
}

/**
 * Wakes long-polling viewers handled by the same warm API instance. Vercel may
 * route the writer and viewers to different instances, so every waiter also
 * probes the authoritative database at a short, bounded interval.
 */
export function publishLiveTickerUpdate(eventId: string) {
  const listeners = listenersByEvent.get(eventId);
  if (!listeners) return;
  for (const listener of [...listeners]) listener();
}

export async function waitForLiveTickerUpdate({
  eventId,
  after,
  waitMs,
  pollIntervalMs = 450,
  readSequence,
}: WaitForLiveTickerUpdateOptions) {
  if (waitMs <= 0) return false;

  const deadline = Date.now() + waitMs;
  const listeners = listenersByEvent.get(eventId) ?? new Set();
  listenersByEvent.set(eventId, listeners);

  let wake: (() => void) | undefined;
  let signal = new Promise<void>((resolve) => {
    wake = resolve;
  });
  const listener = () => wake?.();
  listeners.add(listener);

  try {
    while (Date.now() < deadline) {
      const remaining = deadline - Date.now();
      await Promise.race([
        signal,
        delay(Math.min(Math.max(25, pollIntervalMs), remaining)),
      ]);

      if ((await readSequence()) !== after) return true;

      signal = new Promise<void>((resolve) => {
        wake = resolve;
      });
    }
    return false;
  } finally {
    listeners.delete(listener);
    if (listeners.size === 0) listenersByEvent.delete(eventId);
  }
}
