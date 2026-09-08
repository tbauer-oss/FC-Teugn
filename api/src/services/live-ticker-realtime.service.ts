type WaitForLiveTickerUpdateOptions = {
  eventId: string;
  after: number;
  waitMs: number;
  pollIntervalMs?: number;
  readSequence: () => Promise<number>;
};

type Viewer = {
  after: number;
  interval: number;
  finish: (changed: boolean, error?: unknown) => void;
};

type EventProbe = {
  eventId: string;
  viewers: Set<Viewer>;
  readSequence: () => Promise<number>;
  timer?: ReturnType<typeof setTimeout>;
  running: boolean;
  signalled: boolean;
};

// Only share the change probe. Every HTTP request still checks its own access
// before waiting and again before reading/returning the actual ticker data.
const probesByEvent = new Map<string, EventProbe>();

function scheduleProbe(probe: EventProbe) {
  if (!probe.viewers.size || probe.running) return;
  clearTimeout(probe.timer);
  const interval = Math.min(...[...probe.viewers].map(viewer => viewer.interval));
  probe.timer = setTimeout(() => void readProbe(probe), interval);
}

async function readProbe(probe: EventProbe) {
  clearTimeout(probe.timer);
  if (!probe.viewers.size) return;
  if (probe.running) {
    probe.signalled = true;
    return;
  }
  probe.running = true;
  probe.signalled = false;
  try {
    const sequence = await probe.readSequence();
    for (const viewer of [...probe.viewers]) {
      if (sequence !== viewer.after) viewer.finish(true);
    }
  } catch (error) {
    for (const viewer of [...probe.viewers]) viewer.finish(false, error);
  } finally {
    probe.running = false;
    // Do not lose an update that committed while the shared query was in flight.
    if (probe.signalled && probe.viewers.size) void readProbe(probe);
    else scheduleProbe(probe);
  }
}

/** Same-instance updates wake viewers immediately; other instances retain the
 * existing 450 ms cadence, with one DB query per match/instance, not per viewer. */
export function publishLiveTickerUpdate(eventId: string) {
  const probe = probesByEvent.get(eventId);
  if (probe) void readProbe(probe);
}

export function waitForLiveTickerUpdate({
  eventId,
  after,
  waitMs,
  pollIntervalMs = 450,
  readSequence,
}: WaitForLiveTickerUpdateOptions): Promise<boolean> {
  if (waitMs <= 0) return Promise.resolve(false);
  let probe = probesByEvent.get(eventId);
  if (!probe) {
    probe = { eventId, viewers: new Set(), readSequence, running: false, signalled: false };
    probesByEvent.set(eventId, probe);
  }
  const shared = probe;
  return new Promise<boolean>((resolve, reject) => {
    const viewer: Viewer = {
      after,
      interval: Math.max(25, pollIntervalMs),
      finish(changed, error) {
        if (!shared.viewers.delete(viewer)) return;
        clearTimeout(timeout);
        if (!shared.viewers.size) {
          clearTimeout(shared.timer);
          if (probesByEvent.get(eventId) === shared) probesByEvent.delete(eventId);
        }
        if (error !== undefined) reject(error);
        else resolve(changed);
      },
    };
    const previousInterval = Math.min(...[...shared.viewers].map(item => item.interval));
    const timeout = setTimeout(() => viewer.finish(false), waitMs);
    shared.viewers.add(viewer);
    // Adding viewers must never postpone an already scheduled probe.
    if (shared.viewers.size === 1 || viewer.interval < previousInterval) scheduleProbe(shared);
  });
}
