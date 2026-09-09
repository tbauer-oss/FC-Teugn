import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../fc_teugn_app/web/push_bridge.js', import.meta.url), 'utf8');
const key = Buffer.alloc(65, 1).toString('base64url');
const oldKey = Buffer.alloc(65, 2).toString('base64url');

function browser({permission = 'granted', subscriptionKey = key, freshWorker = false,
  ios = false, standalone = true, needsGesture = false} = {}) {
  const calls = {permission: 0, subscribe: 0, unsubscribe: 0};
  const storage = new Map();
  const worker = new EventTarget();
  worker.state = freshWorker ? 'installing' : 'activated';
  const makeSubscription = value => ({
    options: {applicationServerKey: Buffer.from(value, 'base64url')},
    unsubscribe: async () => {calls.unsubscribe++; subscription = null; return true;},
    toJSON: () => ({endpoint: 'https://push.example/device', keys: {p256dh: 'p256dh', auth: 'auth'}}),
  });
  let subscription = subscriptionKey ? makeSubscription(subscriptionKey) : null;
  const registration = {
    scope: 'https://app.example/fc-teugn-push/',
    active: freshWorker ? null : worker,
    installing: freshWorker ? worker : null,
    pushManager: {
      getSubscription: async () => subscription,
      subscribe: async options => {
        calls.subscribe++;
        assert.equal(worker.state, 'activated', 'subscribe must wait for this worker');
        if (needsGesture) throw new Error('user gesture required');
        assert.deepEqual([...options.applicationServerKey], [...Buffer.from(key, 'base64url')]);
        return subscription = makeSubscription(key);
      },
    },
  };
  let registered = !freshWorker;
  const notification = {permission, requestPermission: async () => {calls.permission++; return 'granted';}};
  const navigator = {
    userAgent: ios ? 'iPhone Safari' : 'Chrome',
    serviceWorker: {
      getRegistrations: async () => registered ? [registration] : [],
      register: async () => {
        registered = true;
        setTimeout(() => {
          worker.state = 'activated'; registration.active = worker;
          worker.dispatchEvent(new Event('statechange'));
        }, 5);
        return registration;
      },
    },
  };
  const window = {Notification: notification, PushManager: {}, navigator, setTimeout, clearTimeout,
    matchMedia: () => ({matches: standalone})};
  vm.runInNewContext(source, {window, navigator, Notification: notification,
    URL, Uint8Array, atob, localStorage: {getItem: k => storage.get(k), setItem: (k,v) => storage.set(k,v)}});
  return {window, calls, notification};
}

test('valid subscription is returned for server reconciliation without renewal', async () => {
  const {window, calls} = browser();
  const value = JSON.parse(await window.fcTeugnSubscribePush(key, false));
  assert.equal(value.endpoint, 'https://push.example/device');
  assert.deepEqual(calls, {permission: 0, subscribe: 0, unsubscribe: 0});
});

test('overlapping repairs rotate an outdated key only once', async () => {
  const {window, calls} = browser({subscriptionKey: oldKey});
  const [a,b] = await Promise.all([window.fcTeugnSubscribePush(key, false), window.fcTeugnSubscribePush(key, false)]);
  assert.equal(a,b);
  assert.deepEqual(calls, {permission: 0, subscribe: 1, unsubscribe: 1});
});

test('new push registration activates before subscribing in its own scope', async () => {
  const {window, calls} = browser({freshWorker: true, subscriptionKey: null});
  await window.fcTeugnSubscribePush(key, false);
  assert.equal(calls.subscribe, 1);
});

test('passive repair never requests a missing or revoked permission', async () => {
  for (const permission of ['default', 'denied']) {
    const {window, calls} = browser({permission});
    await assert.rejects(window.fcTeugnSubscribePush(key, false), /PUSH_PERMISSION_REQUIRED/);
    assert.equal(calls.permission, 0);
    assert.equal(calls.subscribe, 0);
  }
});

test('iOS gesture failure is recoverable and offers a single repair prompt', async () => {
  const {window} = browser({ios: true, subscriptionKey: oldKey, needsGesture: true});
  window.fcTeugnMarkInitialPushPromptHandled(oldKey);
  await assert.rejects(window.fcTeugnSubscribePush(key, false), /user gesture required/);
  assert.equal(JSON.parse(await window.fcTeugnShouldShowInitialPushPrompt(key)).show, true);
  window.fcTeugnMarkInitialPushPromptHandled(key);
  assert.equal(JSON.parse(await window.fcTeugnShouldShowInitialPushPrompt(key)).show, false);
});

test('current subscriptions do not prompt again, even with old prompt history', async () => {
  const {window} = browser();
  assert.equal(JSON.parse(await window.fcTeugnShouldShowInitialPushPrompt(key)).show, false);
});

test('iOS browser tabs and denied permission cannot offer activation', async () => {
  for (const options of [{ios: true, standalone: false}, {permission: 'denied'}]) {
    const {window} = browser({...options, subscriptionKey: null});
    assert.equal(JSON.parse(await window.fcTeugnShouldShowInitialPushPrompt(key)).show, false);
  }
});
