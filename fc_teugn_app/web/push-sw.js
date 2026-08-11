self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const actionUrl = new URL(data.actionUrl || '/', self.location.origin).href;
  const tasks = [
    self.registration.showNotification(data.title || 'FC Teugn Talents', {
      body: data.body || 'Es gibt eine neue Nachricht.',
      icon: '/icons/Icon-192.png?v=fctt-2',
      badge: '/icons/Icon-192.png?v=fctt-2',
      data: { actionUrl },
      tag: data.notificationId || undefined,
      lang: 'de-DE',
      timestamp: Date.now(),
    }),
  ];
  if (self.navigator && 'setAppBadge' in self.navigator) {
    tasks.push(self.navigator.setAppBadge(1));
  }
  event.waitUntil(Promise.all(tasks));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data?.actionUrl || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      async (windows) => {
        for (const client of windows) {
          if ('navigate' in client) await client.navigate(url);
          if ('focus' in client) return client.focus();
        }
        return clients.openWindow(url);
      },
    ),
  );
});
