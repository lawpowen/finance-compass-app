// Flutter 3.44 only emits a self-unregistering flutter_service_worker.js stub,
// and web/flutter_bootstrap.js never registers it. This shell worker caches
// static application files only; finance records remain browser-local.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('service-worker.js').catch((error) => {
      console.warn('Finance Compass offline cache unavailable:', error);
    });
  });
}
