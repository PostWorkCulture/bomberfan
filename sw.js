const params = new URL(self.location.href).searchParams;
const BUILD = params.get('v') || 'dev';
const DOC = params.get('doc') || new URL('./', self.registration.scope).href;
const CACHE = `bomberfan-${BUILD}-v2`;
const ASSETS = [
  DOC,
  new URL('./manifest.webmanifest', self.registration.scope).href,
  new URL('./icon-192.png', self.registration.scope).href,
  new URL('./icon-512.png', self.registration.scope).href,
  new URL('./icon-maskable.png', self.registration.scope).href,
  new URL('./apple-touch-icon.png', self.registration.scope).href,
  new URL('./Main Logo.png', self.registration.scope).href,
  new URL('./assets/vendor/character-bootstrap.js', self.registration.scope).href,
  new URL('./assets/vendor/three.module.min.js', self.registration.scope).href,
  new URL('./assets/vendor/three.core.min.js', self.registration.scope).href,
  new URL('./assets/vendor/GLTFLoader.js', self.registration.scope).href,
  new URL('./assets/vendor/SkeletonUtils.js', self.registration.scope).href,
  new URL('./assets/vendor/BufferGeometryUtils.js', self.registration.scope).href,
  ...[
    'bunny', 'alien', 'evolved-dragon', 'skull-orc', 'orc',
    'fish-monster', 'demon', 'tribal', 'cactoro', 'yeti',
    'mushroom-king', 'ninja', 'evolved-goleling', 'monkroose',
    'blue-demon', 'bomber-og', 'dino', 'flying-tribal', 'frog', 'squidle'
  ].map(name => new URL(`./assets/portraits/${name}.webp`, self.registration.scope).href)
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
    await Promise.all(
      keys.filter(k => k.startsWith('bomberfan-') && k !== CACHE)
          .map(k => caches.delete(k))
    );
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const request = event.request;
  const requestUrl = new URL(request.url);
  if (requestUrl.origin !== self.location.origin) return;

  // Navigations are NETWORK FIRST. This keeps the installed game current while
  // preserving offline fallback. The old worker was cache-first here, which
  // could keep serving an obsolete index.html after a successful deployment.
  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const fresh = await fetch(request, { cache: 'no-store' });
        if (fresh && fresh.ok) {
          await cache.put(DOC, fresh.clone());
          return fresh;
        }
      } catch (_) {}
      return (await cache.match(DOC, { ignoreSearch: true })) || Response.error();
    })());
    return;
  }

  // Static assets stay cache-first, with a background refresh.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request);
    if (cached) {
      event.waitUntil((async () => {
        try {
          const fresh = await fetch(request, { cache: 'no-store' });
          if (fresh && fresh.ok) await cache.put(request, fresh.clone());
        } catch (_) {}
      })());
      return cached;
    }

    try {
      const fresh = await fetch(request, { cache: 'no-store' });
      if (fresh && fresh.ok) await cache.put(request, fresh.clone());
      return fresh;
    } catch (_) {
      return Response.error();
    }
  })());
});
