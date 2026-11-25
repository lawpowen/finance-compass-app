{{flutter_js}}
{{flutter_build_config}}

// pwa_bootstrap.js owns the app's offline worker and update consent.
const renderParams = new URLSearchParams(window.location.search);
// In 3.44.1 a native loss can throw before CkSurface acquires a replacement.
// Android standalone must survive OS backgrounding with the current form intact.
const installedAndroid =
  (navigator.userAgentData?.platform === 'Android' || /Android/i.test(navigator.userAgent)) &&
  window.matchMedia?.('(display-mode: standalone)').matches;
const forceCpuOnly = renderParams.has('cpu') || (Boolean(installedAndroid) && renderParams.get('gpu') !== '1');
window.financeCompassCpuRendering = forceCpuOnly;
const surfaces = new Set();
let checkTimer;
let repaintTimer;
let navigating = false;

window.addEventListener('flutter-first-frame', () => {
  document.getElementById('finance-boot')?.remove();
}, { once: true });

function requestRepaint() {
  if (document.visibilityState !== 'visible' || repaintTimer !== undefined) return;
  // CanvasKit's synchronous loss handler must finish replacing its surface first.
  repaintTimer = window.setTimeout(() => {
    repaintTimer = undefined;
    if (document.visibilityState === 'visible') {
      window.dispatchEvent(new Event('finance-compass-repaint'));
    }
  }, 0);
}

function hasLostSurface() {
  let lost = false;
  for (const reference of surfaces) {
    const gl = reference.deref();
    if (!gl) surfaces.delete(reference);
    else if (gl.canvas.isConnected !== false && gl.isContextLost()) lost = true;
  }
  return lost;
}

function recoverRenderer() {
  const key = 'finance-compass-last-gl-reload';
  const now = Date.now();
  let retryHardware = false;
  try {
    const previous = Number(window.sessionStorage.getItem(key));
    window.sessionStorage.setItem(key, String(now));
    retryHardware = !previous || now - previous > 60_000;
  } catch {
    // A CPU URL survives navigation even when session storage is blocked.
  }
  navigating = true;
  if (retryHardware) {
    window.location.reload();
  } else {
    const url = new URL(window.location.href);
    url.searchParams.set('cpu', '1');
    window.location.replace(url.href);
  }
}

function checkAfterGracePeriod() {
  if (forceCpuOnly || navigating || checkTimer !== undefined ||
      document.visibilityState !== 'visible') return;
  const lostAtStart = hasLostSurface();
  checkTimer = window.setTimeout(() => {
    checkTimer = undefined;
    if (document.visibilityState !== 'visible' || !hasLostSurface()) return;
    if (!lostAtStart || window.financeCompassProtectPendingChanges) {
      checkAfterGracePeriod();
    } else if (!window.financeCompassHasOpenEditor?.() ||
        window.confirm('显示暂时无法恢复。重新加载可能丢失当前表单中未保存的内容。要继续吗？')) {
      recoverRenderer();
    }
  }, 900);
}

if (!forceCpuOnly) {
  const seen = new WeakSet();
  // CkSurface handles loss on the canvas itself. It creates a new canvas
  // inside that event; the retired context may report lost indefinitely.
  let handlingLoss;
  function track(canvasType) {
    if (!canvasType) return;
    const prototype = canvasType.prototype;
    const firstListenerInstalled = new WeakSet();
    const references = new WeakMap();
    const addEventListener = prototype.addEventListener;
    function observeLossStart(canvas) {
      if (firstListenerInstalled.has(canvas)) return;
      firstListenerInstalled.add(canvas);
      addEventListener.call(canvas, 'webglcontextlost', () => {
        const reference = references.get(canvas);
        if (!reference) return;
        if (typeof WeakRef !== 'function') surfaces.add(reference);
        if (surfaces.has(reference)) handlingLoss = reference;
      }, true);
    }
    if (canvasType === window.OffscreenCanvas) {
      // Chromium dispatches OffscreenCanvas events in registration order even
      // for capture listeners. CanvasProvider registers before requesting GL.
      prototype.addEventListener = function(type) {
        if (type === 'webglcontextlost') observeLossStart(this);
        return Reflect.apply(addEventListener, this, arguments);
      };
    }
    const getContext = prototype.getContext;
    prototype.getContext = function(type, options) {
      const gl = Reflect.apply(getContext, this, arguments);
      // CanvasKit supplies majorVersion; Flutter's detached capability probe does not.
      if (!gl || (type !== 'webgl' && type !== 'webgl2') ||
          !options?.majorVersion || seen.has(gl)) return gl;
      seen.add(gl);
      if (handlingLoss && !gl.isContextLost()) surfaces.delete(handlingLoss);
      const ref = typeof WeakRef === 'function' ? new WeakRef(gl) : undefined;
      const reference = ref ?? { deref: () => gl };
      references.set(this, reference);
      observeLossStart(this);
      // On older browsers without WeakRef retain a surface only while it is lost.
      if (ref) {
        for (const item of surfaces) {
          if (!item.deref()) surfaces.delete(item);
        }
        surfaces.add(reference);
      }
      this.addEventListener('webglcontextlost', () => {
        handlingLoss = undefined;
        requestRepaint();
        window.clearTimeout(checkTimer);
        checkTimer = undefined;
        checkAfterGracePeriod();
      });
      this.addEventListener('webglcontextrestored', () => {
        if (!ref) surfaces.delete(reference);
        requestRepaint();
      });
      return gl;
    };
  }
  track(window.HTMLCanvasElement);
  track(window.OffscreenCanvas);
}

function onForeground() {
  if (document.visibilityState !== 'visible') {
    window.clearTimeout(checkTimer);
    checkTimer = undefined;
    return;
  }
  requestRepaint();
  checkAfterGracePeriod();
}

document.addEventListener('visibilitychange', onForeground);
window.addEventListener('pageshow', onForeground);
_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpuOnly,
    fontFallbackBaseUrl: 'fonts/',
  },
});
