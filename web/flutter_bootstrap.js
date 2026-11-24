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
// Android can lose the WebGL surface while Chrome or its installed app is
// backgrounded. Use CanvasKit's software path so the page can keep its state.
const isAndroid =
  navigator.userAgentData?.platform === 'Android' ||
  /\bAndroid\b/i.test(navigator.userAgent);
_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: isAndroid,
    fontFallbackBaseUrl: 'fonts/',
  },
});
