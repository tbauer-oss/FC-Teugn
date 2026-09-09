(function () {
  const pushScopePath = '/fc-teugn-push/';
  const initialPromptKey = 'fc-teugn-web-push-prompt-v1';
  const repairPromptKey = 'fc-teugn-web-push-repair-v1';
  let pendingSubscription = null;

  function withTimeout(promise, timeoutMs, code) {
    let timer;
    return Promise.race([
      Promise.resolve(promise),
      new Promise((_, reject) => {
        timer = window.setTimeout(() => reject(new Error(code)), timeoutMs);
      }),
    ]).finally(() => window.clearTimeout(timer));
  }

  function urlBase64ToUint8Array(value) {
    const padding = '='.repeat((4 - (value.length % 4)) % 4);
    const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    return Uint8Array.from([...raw].map((character) => character.charCodeAt(0)));
  }

  function isIosDevice() {
    return /iPhone|iPad|iPod/i.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true;
  }

  function supportsPush() {
    return 'Notification' in window &&
      'serviceWorker' in navigator &&
      'PushManager' in window;
  }

  function usesVapidKey(subscription, vapidPublicKey) {
    const current = subscription?.options?.applicationServerKey;
    if (!current) return false;
    const expected = urlBase64ToUint8Array(vapidPublicKey);
    const actual = new Uint8Array(current);
    return actual.length === expected.length &&
      actual.every((value, index) => value === expected[index]);
  }

  async function findPushRegistration() {
    if (!('serviceWorker' in navigator)) return null;
    const registrations = await withTimeout(
      navigator.serviceWorker.getRegistrations(),
      8000,
      'PUSH_SERVICE_WORKER_TIMEOUT',
    );
    return registrations.find(
      (item) => new URL(item.scope).pathname === pushScopePath,
    ) || null;
  }

  window.fcTeugnWebPushStatus = async function (vapidPublicKey) {
    const supported = supportsPush();
    const registration = supported ? await findPushRegistration() : null;
    const subscription = registration
      ? await registration.pushManager.getSubscription()
      : null;
    const keyMismatch = subscription !== null && Boolean(vapidPublicKey) &&
      !usesVapidKey(subscription, vapidPublicKey);
    return JSON.stringify({
      supported,
      subscribed: subscription !== null && !keyMismatch,
      keyMismatch,
      isIos: isIosDevice(),
      isStandalone: isStandalone(),
      permission: supported ? Notification.permission : 'unavailable',
    });
  };

  window.fcTeugnShouldShowInitialPushPrompt = async function (vapidPublicKey) {
    const status = JSON.parse(await window.fcTeugnWebPushStatus(vapidPublicKey));
    let handled = false;
    let repairHandled = false;
    try {
      handled = localStorage.getItem(initialPromptKey) === 'handled';
      repairHandled = Boolean(vapidPublicKey) &&
        localStorage.getItem(repairPromptKey) === vapidPublicKey;
    } catch (_) {
      // In a privacy-restricted browser the prompt may be offered again.
    }
    return JSON.stringify({
      show: status.supported &&
        !status.subscribed &&
        !(status.isIos && !status.isStandalone) &&
        ((status.permission === 'default' && !handled) ||
          (status.permission === 'granted' && !repairHandled)),
    });
  };

  window.fcTeugnMarkInitialPushPromptHandled = function (vapidPublicKey) {
    try {
      localStorage.setItem(initialPromptKey, 'handled');
      if (vapidPublicKey) localStorage.setItem(repairPromptKey, vapidPublicKey);
    } catch (_) {
      // Push itself remains usable even when persistent browser storage is blocked.
    }
  };

  async function waitForActiveWorker(registration) {
    if (registration.active?.state === 'activated') return;
    const worker = registration.installing || registration.waiting || registration.active;
    if (!worker) throw new Error('PUSH_SERVICE_WORKER_UNAVAILABLE');
    let onStateChange;
    try {
      await withTimeout(new Promise((resolve, reject) => {
        onStateChange = () => {
          if (worker.state === 'activated') resolve();
          if (worker.state === 'redundant') reject(new Error('PUSH_SERVICE_WORKER_UNAVAILABLE'));
        };
        worker.addEventListener('statechange', onStateChange);
        onStateChange();
      }), 15000, 'PUSH_SERVICE_WORKER_TIMEOUT');
    } finally {
      worker.removeEventListener('statechange', onStateChange);
    }
  }

  async function subscribe(vapidPublicKey, requestPermission) {
    if (!supportsPush()) {
      throw new Error('WEB_PUSH_UNSUPPORTED');
    }
    if (isIosDevice() && !isStandalone()) {
      throw new Error('IOS_HOME_SCREEN_REQUIRED');
    }
    if (!requestPermission && Notification.permission !== 'granted') {
      throw new Error('PUSH_PERMISSION_REQUIRED');
    }
    const permission = Notification.permission === 'granted'
      ? 'granted'
      : await withTimeout(
          Notification.requestPermission(),
          20000,
          'PUSH_PERMISSION_TIMEOUT',
        );
    if (permission !== 'granted') {
      throw new Error('PUSH_PERMISSION_DENIED');
    }
    // Push läuft absichtlich in einem eigenen Scope. So bleibt der von Flutter
    // registrierte Root-Service-Worker für Offline-Cache und App-Updates aktiv.
    let registration = await findPushRegistration();
    if (!registration) {
      registration = await withTimeout(
        navigator.serviceWorker.register('/push-sw.js', {
          scope: pushScopePath,
        }),
        15000,
        'PUSH_SERVICE_WORKER_TIMEOUT',
      );
    }
    // register() can resolve before activation, especially on a new iPhone
    // installation. navigator.serviceWorker.ready would wait for the wrong
    // (root) scope, so wait on this push registration instead.
    await waitForActiveWorker(registration);
    let subscription = await withTimeout(
      registration.pushManager.getSubscription(),
      10000,
      'PUSH_SUBSCRIPTION_TIMEOUT',
    );
    if (subscription && !usesVapidKey(subscription, vapidPublicKey)) {
      await withTimeout(
        subscription.unsubscribe(),
        10000,
        'PUSH_UNSUBSCRIBE_TIMEOUT',
      );
      subscription = null;
    }
    if (!subscription) {
      subscription = await withTimeout(
        registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
        }),
        20000,
        'PUSH_SUBSCRIPTION_TIMEOUT',
      );
    }
    const json = subscription.toJSON();
    return JSON.stringify({
      endpoint: json.endpoint,
      p256dh: json.keys.p256dh,
      auth: json.keys.auth,
      deviceName: isIosDevice()
        ? 'FC Teugn Talents · iPhone/iPad Web-App'
        : 'FC Teugn Talents · Browser',
    });
  }

  window.fcTeugnSubscribePush = function (vapidPublicKey, requestPermission = true) {
    // A passive repair must never reuse a request that can open a permission UI.
    if (!requestPermission && Notification.permission !== 'granted') {
      return Promise.reject(new Error('PUSH_PERMISSION_REQUIRED'));
    }
    if (pendingSubscription?.key === vapidPublicKey) {
      return pendingSubscription.promise;
    }
    const promise = subscribe(vapidPublicKey, requestPermission).finally(() => {
      if (pendingSubscription?.promise === promise) pendingSubscription = null;
    });
    pendingSubscription = {key: vapidPublicKey, promise};
    return promise;
  };
})();
