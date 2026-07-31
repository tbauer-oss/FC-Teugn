(function () {
  function urlBase64ToUint8Array(value) {
    const padding = '='.repeat((4 - (value.length % 4)) % 4);
    const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    return Uint8Array.from([...raw].map((character) => character.charCodeAt(0)));
  }

  window.fcTeugnSubscribePush = async function (vapidPublicKey) {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      throw new Error('Dieser Browser unterstützt keine Push-Benachrichtigungen.');
    }
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') {
      throw new Error('Push-Benachrichtigungen wurden nicht freigegeben.');
    }
    // Push läuft absichtlich in einem eigenen Scope. So bleibt der von Flutter
    // registrierte Root-Service-Worker für Offline-Cache und App-Updates aktiv.
    const registrations = await navigator.serviceWorker.getRegistrations();
    let registration = registrations.find(
      (item) => new URL(item.scope).pathname === '/fc-teugn-push/',
    );
    if (!registration) {
      registration = await navigator.serviceWorker.register('/push-sw.js', {
        scope: '/fc-teugn-push/',
      });
    }
    let subscription = await registration.pushManager.getSubscription();
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
    });
  };
})();
