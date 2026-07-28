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
    const registration = await navigator.serviceWorker.register('/push-sw.js');
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
