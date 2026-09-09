self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil((async () => {
  await Promise.all((await caches.keys()).map(key => caches.delete(key)));
  await self.clients.claim();
  for (const client of await self.clients.matchAll({type: 'window'})) {
    const old = new URL(client.url);
    await client.navigate('https://app.fc-teugn-talents.de' + old.pathname + old.search + old.hash);
  }
  await self.registration.unregister();
})()));
