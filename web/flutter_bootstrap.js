{{flutter_js}}
{{flutter_build_config}}

// pwa_bootstrap.js owns the app's offline worker and update consent.
const renderParams = new URLSearchParams(window.location.search);
const fallbackKey = 'finance-compass-cpu-fallback';
const lastReloadKey = 'finance-compass-last-gl-reload';
const fallbackLifetime = 10 * 60_000;
const gpuRequested = renderParams.get('gpu') === '1';

function temporaryFallbackActive(storage) {
  const raw = storage.getItem(fallbackKey);
  if (raw === null) return false;
  const since = Number(raw);
  const age = Date.now() - since;
  if (since > 0 && age >= 0 && age < fallbackLifetime) return true;
  storage.removeItem(fallbackKey);
  return false;
}

function useSoftwareRenderer() {
  if (renderParams.has('cpu')) return true;
  try {
    const storage = window.sessionStorage;
    if (gpuRequested) {
      storage.removeItem(fallbackKey);
    } else {
      return temporaryFallbackActive(storage);
    }
  } catch {
    // Blocked session storage does not prevent a normal hardware launch.
  }
  return false;
}

const forceCpuOnly = useSoftwareRenderer();
window.financeCompassCpuRendering = forceCpuOnly;
const surfaces = new Set();
let checkTimer;
let repaintTimer;
let navigating = false;
let recoveryCover;
let resumeLoss;
let pageShown = false;

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

function lostSurface() {
  for (const reference of surfaces) {
    const gl = reference.deref();
    if (!gl) surfaces.delete(reference);
    else if (gl.canvas.isConnected !== false && gl.isContextLost()) return reference;
  }
}

function clearRecoveryCover() {
  recoveryCover?.remove();
  recoveryCover = undefined;
}

function paintCoverThen(action) {
  const cover = document.createElement('div');
  cover.id = 'finance-recovery';
  cover.lang = 'zh';
  cover.setAttribute('role', 'status');
  cover.textContent = '正在恢复画面…';
  recoveryCover = cover;
  document.body.appendChild(cover);
  // Give the DOM cover a paint before a synchronous navigation tears it down.
  window.requestAnimationFrame(() => window.requestAnimationFrame(() => {
    if (recoveryCover === cover) action();
  }));
}

function recoverRenderer(loss) {
  let storage;
  let previous;
  try {
    const session = window.sessionStorage;
    previous = Number(session.getItem(lastReloadKey));
    storage = session;
  } catch {
    // The CPU URL below is the loop breaker when we cannot record a retry.
  }
  const repeated = now => previous > 0 && now >= previous && now - previous <= 60_000;
  const editing = window.financeCompassHasOpenEditor?.();
  if (editing || (repeated(Date.now()) && gpuRequested)) {
    const message = editing
      ? '显示暂时无法恢复。重新加载可能丢失当前表单中未保存的内容。要继续吗？'
      : '硬件绘图再次失活。要按当前指定的 GPU 模式重新加载吗？';
    if (!window.confirm(message)) return;
  }

  paintCoverThen(() => {
    if (document.visibilityState !== 'visible' || lostSurface() !== loss ||
        window.financeCompassProtectPendingChanges ||
        (!editing && window.financeCompassHasOpenEditor?.())) {
      clearRecoveryCover();
      checkAfterGracePeriod();
      return;
    }
    navigating = true;
    if (storage) {
      try {
        const now = Date.now();
        storage.setItem(lastReloadKey, String(now));
        if (repeated(now) && !gpuRequested) storage.setItem(fallbackKey, String(now));
      } catch {
        storage = undefined;
      }
    }
    if (storage) {
      window.location.reload();
    } else {
      const url = new URL(window.location.href);
      url.searchParams.set('cpu', '1');
      window.location.replace(url.href);
    }
  });
}

function checkAfterGracePeriod(onResume = false) {
  if (forceCpuOnly || navigating || recoveryCover || checkTimer !== undefined ||
      document.visibilityState !== 'visible') return;
  const loss = lostSurface();
  resumeLoss = onResume ? loss : undefined;
  checkTimer = window.setTimeout(() => {
    checkTimer = undefined;
    resumeLoss = undefined;
    const current = lostSurface();
    if (document.visibilityState !== 'visible' || !current) return;
    if (current !== loss || window.financeCompassProtectPendingChanges) {
      checkAfterGracePeriod();
    } else {
      recoverRenderer(loss);
    }
  }, resumeLoss ? 350 : 900);
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
    // Install before CanvasProvider, even on targets that invoke capture and
    // non-capture listeners together in registration order.
    prototype.addEventListener = function(type) {
      if (type === 'webglcontextlost') observeLossStart(this);
      return Reflect.apply(addEventListener, this, arguments);
    };
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
        // A delayed native event for the loss already seen on resume must
        // not turn the shorter foreground-return grace into another 900ms.
        if (resumeLoss === reference) return;
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

function canReturnToHardware() {
  if (!forceCpuOnly || renderParams.has('cpu') ||
      document.visibilityState !== 'visible' || window.financeCompassProtectPendingChanges ||
      window.financeCompassHasOpenEditor?.()) return false;
  try {
    return !temporaryFallbackActive(window.sessionStorage);
  } catch {
    return false;
  }
}

function onForeground(event) {
  const returning = event.type === 'visibilitychange' || event.persisted || pageShown;
  if (event.type === 'pageshow') pageShown = true;
  if (document.visibilityState !== 'visible') {
    window.clearTimeout(checkTimer);
    checkTimer = undefined;
    resumeLoss = undefined;
    clearRecoveryCover();
    return;
  }
  requestRepaint();
  if (returning && !navigating && !recoveryCover && canReturnToHardware()) {
    paintCoverThen(() => {
      if (canReturnToHardware()) {
        navigating = true;
        window.location.reload();
      } else {
        clearRecoveryCover();
      }
    });
    return;
  }
  if (checkTimer !== undefined && !resumeLoss && lostSurface()) {
    window.clearTimeout(checkTimer);
    checkTimer = undefined;
  }
  checkAfterGracePeriod(true);
}

document.addEventListener('visibilitychange', onForeground);
window.addEventListener('pageshow', onForeground);
_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpuOnly,
    fontFallbackBaseUrl: 'fonts/',
  },
});
