// sw.js - Book Library PWA Service Worker

// ---------- 1. Dynamic path & cache ----------
const BASE_PATH = self.location.pathname.replace(/[^/]+$/, '');
const CACHE_NAME = `pwa-cache${BASE_PATH.replace(/\//g, '-')}v3`;

const PRECACHE_URLS = [
  BASE_PATH,
  `${BASE_PATH}index.html`,
  `${BASE_PATH}manifest.json`,
];

const STATIC_EXTENSIONS = [
  'js', 'css', 'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp',
  'woff', 'woff2', 'ttf', 'eot', 'ico', 'epub', 'mobi',
];

// ---------- 2. Helpers ----------
function isStaticResource(url) {
  const ext = url.pathname.split('.').pop().toLowerCase();
  return STATIC_EXTENSIONS.includes(ext);
}

function isNavigateRequest(request) {
  return request.mode === 'navigate' || (request.method === 'GET' && request.destination === 'document');
}

// ---------- 3. Install ----------
self.addEventListener('install', (event) => {
  console.log('[SW] Install, BASE_PATH =', BASE_PATH);
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        return Promise.allSettled(
          PRECACHE_URLS.map(url => cache.add(url).catch(err => console.warn(`Precache fail ${url}:`, err)))
        );
      })
      .then(() => self.skipWaiting())
  );
});

// ---------- 4. Activate ----------
self.addEventListener('activate', (event) => {
  console.log('[SW] Activate');
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cache => {
          if (cache.startsWith('pwa-cache-') && cache !== CACHE_NAME) {
            console.log('[SW] Delete old cache:', cache);
            return caches.delete(cache);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// ---------- 5. Fetch ----------
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (url.origin !== location.origin || request.method !== 'GET') return;

  // 5.1 index.json: network-first
  if (url.pathname.endsWith('/books/index.json')) {
    event.respondWith(
      fetch(request)
        .then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const clone = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
          }
          return networkResponse;
        })
        .catch(async () => {
          const cached = await caches.match(request);
          if (cached) return cached;
          return new Response('{"magazines":[]}', {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        })
    );
    return;
  }

  // 5.2 Book files (epub/pdf/mobi): cache-first + background update
  if (url.pathname.includes('/books/') && !url.pathname.endsWith('/books/index.json')) {
    event.respondWith(
      caches.match(request).then(cached => {
        const networkFetch = fetch(request).then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const clone = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
          }
          return networkResponse;
        }).catch(() => cached);

        return cached || networkFetch;
      })
    );
    return;
  }

  // 5.3 Navigation: network-first
  if (isNavigateRequest(request)) {
    event.respondWith(
      fetch(request)
        .then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const clone = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
          }
          return networkResponse;
        })
        .catch(async () => {
          const cached = await caches.match(request);
          if (cached) return cached;
          return new Response(
            '<h1>📴 离线状态</h1><p>请检查网络连接后刷新页面。</p>',
            { status: 503, statusText: 'Offline', headers: { 'Content-Type': 'text/html; charset=utf-8' } }
          );
        })
    );
    return;
  }

  // 5.4 Static resources: cache-first
  if (isStaticResource(url)) {
    event.respondWith(
      caches.match(request).then(cached => {
        if (cached) return cached;
        return fetch(request).then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const clone = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
          }
          return networkResponse;
        }).catch(() => new Response('', { status: 408 }));
      })
    );
    return;
  }
});
