const assert = require('node:assert/strict');
const test = require('node:test');

const {
  routeEstimateFromTeugn,
} = require('../dist/src/services/route-estimate.service.js');

test('dashboard route estimate is calculated once and cached by full address', async () => {
  const originalFetch = global.fetch;
  const requests = [];
  global.fetch = async (url) => {
    requests.push(String(url));
    if (String(url).includes('nominatim.openstreetmap.org')) {
      return {
        ok: true,
        json: async () => [{ lat: '48.823', lon: '12.052' }],
      };
    }
    return {
      ok: true,
      json: async () => ({ routes: [{ distance: 32140, duration: 1690 }] }),
    };
  };

  try {
    const address = 'Am Waldstadion 1, 84085 Langquaid';
    const first = await routeEstimateFromTeugn(address);
    const second = await routeEstimateFromTeugn(address);
    assert.deepEqual(first, {
      available: true,
      distanceKm: 32.1,
      durationMinutes: 28,
      attribution: '© OpenStreetMap-Mitwirkende',
    });
    assert.deepEqual(second, first);
    assert.equal(requests.length, 2);
    assert.match(requests[0], /format=jsonv2/);
    assert.match(requests[1], /route\/v1\/driving/);
  } finally {
    global.fetch = originalFetch;
  }
});
