(function () {
  const pushScopePath = '/fc-teugn-push/';
  const initialPromptKey = 'fc-teugn-web-push-prompt-v1';

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
    const registrations = await navigator.serviceWorker.getRegistrations();
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

  window.fcTeugnShouldShowInitialPushPrompt = async function () {
    const status = JSON.parse(await window.fcTeugnWebPushStatus());
    let handled = false;
    try {
      handled = localStorage.getItem(initialPromptKey) === 'handled';
    } catch (_) {
      // In a privacy-restricted browser the prompt may be offered again.
    }
    return JSON.stringify({
      show: status.supported &&
        status.permission === 'default' &&
        !status.subscribed &&
        !(status.isIos && !status.isStandalone) &&
        !handled,
    });
  };

  window.fcTeugnMarkInitialPushPromptHandled = function () {
    try {
      localStorage.setItem(initialPromptKey, 'handled');
    } catch (_) {
      // Push itself remains usable even when persistent browser storage is blocked.
    }
  };

  window.fcTeugnSubscribePush = async function (vapidPublicKey) {
    if (!supportsPush()) {
      throw new Error('WEB_PUSH_UNSUPPORTED');
    }
    if (isIosDevice() && !isStandalone()) {
      throw new Error('IOS_HOME_SCREEN_REQUIRED');
    }
    const permission = Notification.permission === 'granted'
      ? 'granted'
      : await Notification.requestPermission();
    if (permission !== 'granted') {
      throw new Error('PUSH_PERMISSION_DENIED');
    }
    // Push läuft absichtlich in einem eigenen Scope. So bleibt der von Flutter
    // registrierte Root-Service-Worker für Offline-Cache und App-Updates aktiv.
    let registration = await findPushRegistration();
    if (!registration) {
      registration = await navigator.serviceWorker.register('/push-sw.js', {
        scope: pushScopePath,
      });
    }
    let subscription = await registration.pushManager.getSubscription();
    if (subscription && !usesVapidKey(subscription, vapidPublicKey)) {
      await subscription.unsubscribe();
      subscription = null;
    }
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      });
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
  };
})();
