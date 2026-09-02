const teugnOrigin = { latitude: 48.8923, longitude: 12.0127 };
const cacheTtlMs = 30 * 24 * 60 * 60 * 1000;

export type RouteEstimate = {
  available: true;
  distanceKm: number;
  durationMinutes: number;
  attribution: string;
};

type CachedEstimate = { expiresAt: number; value: RouteEstimate | null };
const cache = new Map<string, CachedEstimate>();
const pending = new Map<string, Promise<RouteEstimate | null>>();
let nextGeocodeAt = 0;

function normalized(value: string) {
  return value.trim().replace(/\s+/g, ' ').toLocaleLowerCase('de-DE');
}

async function fetchJson(url: string, timeoutMs = 6500) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        Accept: 'application/json',
        'User-Agent': 'FC-Teugn-Talents/1.0 (route estimate)',
      },
    });
    if (!response.ok) return null;
    return response.json() as Promise<unknown>;
  } finally {
    clearTimeout(timeout);
  }
}

async function geocode(address: string) {
  const waitMs = Math.max(0, nextGeocodeAt - Date.now());
  if (waitMs) await new Promise((resolve) => setTimeout(resolve, waitMs));
  nextGeocodeAt = Date.now() + 1050;
  const query = new URLSearchParams({
    q: address,
    format: 'jsonv2',
    limit: '1',
    countrycodes: 'de',
  });
  const body = await fetchJson(
    `https://nominatim.openstreetmap.org/search?${query.toString()}`,
  );
  if (!Array.isArray(body) || !body.length) return null;
  const first = body[0] as { lat?: string; lon?: string };
  const latitude = Number(first.lat);
  const longitude = Number(first.lon);
  return Number.isFinite(latitude) && Number.isFinite(longitude)
    ? { latitude, longitude }
    : null;
}

async function calculate(address: string): Promise<RouteEstimate | null> {
  const destination = await geocode(address);
  if (!destination) return null;
  const coordinates = [
    `${teugnOrigin.longitude},${teugnOrigin.latitude}`,
    `${destination.longitude},${destination.latitude}`,
  ].join(';');
  const body = await fetchJson(
    `https://router.project-osrm.org/route/v1/driving/${coordinates}?overview=false&alternatives=false&steps=false`,
  ) as { routes?: Array<{ distance?: number; duration?: number }> } | null;
  const route = body?.routes?.[0];
  if (!route || !Number.isFinite(route.distance) || !Number.isFinite(route.duration)) {
    return null;
  }
  return {
    available: true,
    distanceKm: Math.max(1, Math.round((route.distance ?? 0) / 100) / 10),
    durationMinutes: Math.max(1, Math.round((route.duration ?? 0) / 60)),
    attribution: '© OpenStreetMap-Mitwirkende',
  };
}

export async function routeEstimateFromTeugn(address: string) {
  const key = normalized(address);
  if (!key) return null;
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.value;
  const inFlight = pending.get(key);
  if (inFlight) return inFlight;
  const request = calculate(address)
    .catch(() => null)
    .then((value) => {
      cache.set(key, { expiresAt: Date.now() + cacheTtlMs, value });
      pending.delete(key);
      return value;
    });
  pending.set(key, request);
  return request;
}
