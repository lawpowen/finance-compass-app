// Keep "consent-" in future release cache names so installed clients can
// choose when to activate the next worker.
const CACHE_NAME = 'finance-compass-shell-consent-v0.10.1-sync23';
const SHELL_CACHE_PREFIX = 'finance-compass-shell-';
const CONSENT_CACHE_PREFIX = 'finance-compass-shell-consent-';
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
  './assets/assets/fonts/MiSans-Regular.ttf',
  './assets/assets/fonts/MisansTC-Regular.ttf',
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
  await cache.addAll(CORE.map(path => new Request(path, { cache: 'reload' })));
  const index = await (await cache.match(FONT_INDEX)).text();
  const fonts = index.split(/\r?\n/)
    .map((line) => line.trim().split(/\s+/)[1])
    .filter(Boolean)
    .map((path) => `./fonts/${path}`);
  await cache.addAll(fonts);
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const hasConsentWorker = (await caches.keys()).some(
      (key) => key !== CACHE_NAME && key.startsWith(CONSENT_CACHE_PREFIX),
    );
    try {
      await precache();
    } catch (error) {
      await caches.delete(CACHE_NAME);
      throw error;
    }
    // Earlier app shells have no update button. Activate this transition once
    // without navigating open tabs so their next launch gets the new feature.
    if (!hasConsentWorker) await self.skipWaiting();
  })());
});

let pushGeneration = 0;

self.addEventListener('message', (event) => {
  const client = event.source;
  if (client?.type !== 'window' || !client.url.startsWith(self.registration.scope)) return;
  if (event.data?.type === 'finance-compass-push-transition') pushGeneration++;
  if (event.data?.type === 'finance-compass-activate-update') event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith(SHELL_CACHE_PREFIX) && key !== CACHE_NAME)
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin ||
      url.pathname.startsWith(new URL('api/', self.registration.scope).pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);
    if (cached) return cached;
    // A waiting worker uses its own cache. Refreshes and deep links should
    // still use the shell paired with this controlling worker.
    if (request.mode === 'navigate') {
      return await cache.match('./index.html') ?? fetch(request);
    }
    const response = await fetch(request);
    if (response.ok && response.type === 'basic' &&
        !/\b(?:private|no-store)\b/i.test(response.headers.get('Cache-Control') || '')) {
      await cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  })());
});

// A push can be queued while another account owns this browser. The message
// carries its intended recipient; the server checks the live cookie AND the
// current endpoint before any account-specific text reaches the lock screen.
self.addEventListener('push', (event) => event.waitUntil((async () => {
  try {
    const generation = pushGeneration;
    const { accountId, notification } = event.data.json();
    if (typeof accountId !== 'string' || !accountId || !notification) return;
    const sub = await self.registration.pushManager.getSubscription();
    if (!sub) return;
    const verified = await fetch(new URL('/api/sync/v1/push/verify-delivery', self.registration.scope), {
      method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { 'Content-Type': 'application/json', 'X-Finance-Account': accountId },
      body: JSON.stringify({ endpoint: sub.endpoint }),
    });
    if (verified.status !== 204 || generation !== pushGeneration) return;
    const { title, body, tag } = notification;
    if (typeof title !== 'string' || typeof body !== 'string') return;
    await self.registration.showNotification(title.slice(0, 100), {
      body: body.slice(0, 300), icon: new URL('icons/Icon-192.png', self.registration.scope).href,
      tag: typeof tag === 'string' ? tag.slice(0, 160) : undefined,
      data: { accountId },
    });
    if (generation !== pushGeneration) {
      for (const item of await self.registration.getNotifications()) {
        if (item.data?.accountId === accountId && item.tag === tag) item.close();
      }
    }
  } catch (_) {
    // Offline, malformed, expired and unbound deliveries have no verified recipient.
  }
})()));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const root = new URL(self.registration.scope);
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      const url = new URL(client.url);
      if (url.origin === root.origin && url.pathname.startsWith(root.pathname)) {
        try {
          await client.focus();
          return;
        } catch (_) {
          // The client can disappear between lookup and focus.
        }
      }
    }
    await self.clients.openWindow(root.href);
  })());
});
