{{flutter_js}}
{{flutter_build_config}}

// No service worker settings: Flutter 3.44 still emits
// flutter_service_worker.js, but only as a self-unregistering cleanup stub; the
// default bootstrap would register it over pwa_bootstrap.js's
// service-worker.js whenever that registration exists, wiping the offline
// shell on the next visit. service-worker.js is the only app service worker.
//
// Flutter bundles the UI font with the app. CanvasKit's last-resort fonts
// must also remain same-origin for user-entered names outside its coverage.
// tool/build_web.* verify these fallback assets against web/fonts/SHA256SUMS.
// Use hardware WebGL rendering by default for smooth 60/120fps Liquid Glass
// backdrop blur, while allowing `?cpu=1` opt-in to software rendering and
// reloading if an idle mobile WebGL surface fails to restore on resume.
const renderParams = new URLSearchParams(window.location.search);
const forceCpuOnly = renderParams.has('cpu');
let webglLostAt = 0;
window.addEventListener(
  'webglcontextlost',
  (event) => {
    event.preventDefault();
    webglLostAt = Date.now();
  },
  true,
);
window.addEventListener(
  'webglcontextrestored',
  () => {
    webglLostAt = 0;
  },
  true,
);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && webglLostAt > 0) {
    window.setTimeout(() => {
      if (webglLostAt > 0 && document.visibilityState === 'visible') {
        window.location.reload();
      }
    }, 900);
  }
});
_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpuOnly,
    fontFallbackBaseUrl: 'fonts/',
  },
});
