const CACHE_NAME = 'finance-compass-shell-v0.9.1';
// Keep the complete rendering and local-database runtime available after a
// successful first load. Do not add user data here: it stays in Drift's
// browser storage, outside the HTTP cache.
// tool/build_web.ps1 and tool/build_web.sh fail the release when any entry
// below is missing from build/web, because one missing file rejects the whole
// install. Flutter's flutter_service_worker.js is deliberately absent: in 3.44
// it is only a self-unregistering cleanup stub.
const CORE = [
  './',
  './index.html',
  './manifest.json',
  './version.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
  './pwa_bootstrap.js',
  './service-worker.js',
  './flutter_bootstrap.js',
  './flutter.js',
  './main.dart.js',
  './sqlite3.wasm',
  './drift_worker.js',
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/FontManifest.json',
  './assets/NOTICES',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  './assets/assets/support/touch-n-go-support-qr.jpg',
  './assets/shaders/ink_sparkle.frag',
  './assets/shaders/stretch_effect.frag',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  // flutter.js selects this variant on Chromium browsers (Chrome/Edge).
  './canvaskit/chromium/canvaskit.js',
  './canvaskit/chromium/canvaskit.wasm',
  './canvaskit/skwasm.js',
  './canvaskit/skwasm.wasm',
  './canvaskit/skwasm_heavy.js',
  './canvaskit/skwasm_heavy.wasm',
  './canvaskit/wimp.js',
  './canvaskit/wimp.wasm',
  './fonts/SHA256SUMS',
];
// Same-origin CanvasKit fallback fonts (see web/flutter_bootstrap.js). The
// list is the checksum file, so every vendored subset is cached for offline
// text input without repeating ~100 hashed file names here.
const FONT_INDEX = './fonts/SHA256SUMS';

async function precache() {
  const cache = await caches.open(CACHE_NAME);
  await cache.addAll(CORE);
  const index = await (await cache.match(FONT_INDEX)).text();
  const fonts = index.split(/\r?\n/)
    .map((line) => line.trim().split(/\s+/)[1])
    .filter(Boolean)
    .map((path) => `./fonts/${path}`);
  await cache.addAll(fonts);
}

self.addEventListener('install', (event) => {
  event.waitUntil(precache());
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
