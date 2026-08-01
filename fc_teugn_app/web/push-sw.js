self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(
    self.registration.showNotification(data.title || 'FC Teugn Talents', {
      body: data.body || 'Es gibt eine neue Nachricht.',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      data: { actionUrl: data.actionUrl || '/' },
      tag: data.notificationId || undefined,
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data?.actionUrl || '/';
  event.waitUntil(clients.openWindow(url));
});
