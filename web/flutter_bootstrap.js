{{flutter_js}}
{{flutter_build_config}}

// No service worker settings: Flutter 3.44 still emits
// flutter_service_worker.js, but only as a self-unregistering cleanup stub; the
// default bootstrap would register it over pwa_bootstrap.js's
// service-worker.js whenever that registration exists, wiping the offline
// shell on the next visit. service-worker.js is the only app service worker.
//
// CanvasKit bundles no text font. Its default fallback (Roboto, Noto Sans SC)
// comes from fonts.gstatic.com, which the self-hosted CSP blocks and which is
// unreachable offline, leaving every label blank. web/fonts mirrors those
// paths same-origin; tool/build_web.* verify it against web/fonts/SHA256SUMS.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: 'fonts/',
  },
});
