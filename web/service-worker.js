const CACHE_NAME = 'finance-compass-shell-v0.9.0.1';
// Keep the complete rendering and local-database runtime available after a
// successful first load. Do not add user data here: it stays in Drift's
// browser storage, outside the HTTP cache.
const CORE = [
  './',
  './index.html',
  './manifest.json',
  './version.json',
  './pwa_bootstrap.js',
  './service-worker.js',
  './flutter_service_worker.js',
  './flutter_bootstrap.js',
  './flutter.js',
  './main.dart.js',
  './sqlite3.wasm',
  './drift_worker.js',
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/FontManifest.json',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/assets/support/touch-n-go-support-qr.jpg',
  './assets/shaders/ink_sparkle.frag',
  './assets/shaders/stretch_effect.frag',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  './canvaskit/skwasm.js',
  './canvaskit/skwasm.wasm',
  './canvaskit/skwasm_heavy.js',
  './canvaskit/skwasm_heavy.wasm',
  './canvaskit/wimp.js',
  './canvaskit/wimp.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CORE)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((key) => key.startsWith('finance-compass-shell-') && key !== CACHE_NAME)
        .map((key) => caches.delete(key)),
    )),
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request).then((response) => {
      if (response.ok && response.type === 'basic') {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
      }
      return response;
    })),
  );
});
