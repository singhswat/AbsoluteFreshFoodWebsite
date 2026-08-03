const CACHE = 'aff-v1';
const OFFLINE_PAGES = [
  '/index.html',
  '/pages/beat.html',
  '/pages/deliveries.html',
  '/pages/done-today.html',
  '/css/style.css',
  '/js/app.js'
];

// Install - cache core pages
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(OFFLINE_PAGES))
  );
  self.skipWaiting();
});

// Activate - clean old caches
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch - serve from cache when offline
self.addEventListener('fetch', e => {
  // Only cache GET requests
  if (e.request.method !== 'GET') return;
  // Don't cache Supabase API calls
  if (e.request.url.includes('supabase.co')) return;

  e.respondWith(
    fetch(e.request)
      .then(res => {
        // Cache successful responses for app pages
        if (res.ok && e.request.url.includes(self.location.origin)) {
          const clone = res.clone();
          caches.open(CACHE).then(cache => cache.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
