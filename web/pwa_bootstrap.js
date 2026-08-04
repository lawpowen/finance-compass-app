// Flutter 3.44 no longer generates a service worker. This shell worker caches
// static application files only; finance records remain browser-local.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('service-worker.js').catch((error) => {
      console.warn('Finance Compass offline cache unavailable:', error);
    });
  });
}
