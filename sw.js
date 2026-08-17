const params = new URL(self.location.href).searchParams;
const BUILD = params.get('v') || 'dev';
const DOC = params.get('doc') || new URL('./', self.registration.scope).href;
const CACHE = `bomberfan-${BUILD}`;
const ASSETS = [
  DOC,
  new URL('./manifest.webmanifest', self.registration.scope).href,
  new URL('./icon-192.png', self.registration.scope).href,
  new URL('./icon-512.png', self.registration.scope).href,
  new URL('./icon-maskable.png', self.registration.scope).href
];

async function cacheOne(cache, url) {
  try {
    const response = await fetch(url, { cache: 'no-store' });
    if (response && response.ok) await cache.put(url, response.clone());
  } catch (_) {}
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const url of ASSETS) await cacheOne(cache, url);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith('bomberfan-') && k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const request = event.request;
  const requestUrl = new URL(request.url);
  if (requestUrl.origin !== self.location.origin) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request, { ignoreSearch: request.mode === 'navigate' });

    const refresh = (async () => {
      try {
        const fresh = await fetch(request, { cache: 'no-store' });
        if (fresh && fresh.ok) {
          const previous = cached ? cached.clone() : null;
          await cache.put(request, fresh.clone());
          if (request.mode === 'navigate' && previous) {
            const oldText = await previous.text();
            const newText = await fresh.clone().text();
            const oldBuild = oldText.match(/<meta name="build" content="([^"]*)">/)?.[1];
            const newBuild = newText.match(/<meta name="build" content="([^"]*)">/)?.[1];
            if (oldBuild && newBuild && oldBuild !== newBuild) {
              const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
              for (const client of clients) client.postMessage({ type: 'update', build: newBuild });
            }
          }
        }
        return fresh;
      } catch (_) {
        return null;
      }
    })();

    if (cached) {
      event.waitUntil(refresh);
      return cached;
    }

    const fresh = await refresh;
    if (fresh) return fresh;
    if (request.mode === 'navigate') {
      return (await cache.match(DOC, { ignoreSearch: true })) || Response.error();
    }
    return Response.error();
  })());
});
