import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const bootstrap = readFileSync(new URL('../web/flutter_bootstrap.js', import.meta.url), 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

class Target {
  listeners = [];
  addEventListener(type, callback, options) {
    this.listeners.push({ type, callback, capture: options === true || options?.capture, once: options?.once });
  }
  dispatchEvent(event) {
    for (const capture of [true, false]) {
      for (const listener of this.listeners.slice()) {
        if (listener.type !== event.type || !!listener.capture !== capture) continue;
        listener.callback.call(this, event);
        if (listener.once) this.listeners.splice(this.listeners.indexOf(listener), 1);
      }
    }
  }
  emit(type, options = {}) { this.dispatchEvent({ type, ...options }); }
}

function browser({ url = 'https://example.test/finance/', storage = new Map(), blocked = false, userAgent = '', standalone = false } = {}) {
  const window = new Target();
  window.matchMedia = query => ({ matches: standalone && query === '(display-mode: standalone)' });
  const document = new Target();
  document.visibilityState = 'visible';
  let now = 100000, config, repaints = 0, removals = 0;
  const navigations = [], timers = new Map();
  let sequence = 0;
  window.location = {
    href: url, search: new URL(url).search,
    reload: () => navigations.push(url), replace: next => navigations.push(next),
  };
  window.sessionStorage = {
    getItem: key => { if (blocked) throw new Error('denied'); return storage.get(key) ?? null; },
    setItem: (key, value) => { if (blocked) throw new Error('denied'); storage.set(key, value); },
  };
  window.setTimeout = (fn, delay) => { timers.set(++sequence, { at: now + delay, fn }); return sequence; };
  window.clearTimeout = id => timers.delete(id);
  const advance = (ms = 1000) => {
    const until = now + ms;
    for (;;) {
      const first = [...timers].sort((a,b) => a[1].at - b[1].at)[0];
      if (!first || first[1].at > until) break;
      timers.delete(first[0]); now = first[1].at; first[1].fn();
    }
    now = until;
  };
  class Canvas extends Target {
    width = 400; height = 800;
    context = { canvas: this, lost: false, isContextLost() { return this.lost; } };
    getContext(type) { return type.startsWith('webgl') ? this.context : {}; }
    getGL() { return this.getContext('webgl2', { majorVersion: 2 }); }
    lose() { this.context.lost = true; this.emit('webglcontextlost'); }
    restore() { this.context.lost = false; this.emit('webglcontextrestored'); }
  }
  window.HTMLCanvasElement = class extends Canvas { isConnected = true; };
  window.OffscreenCanvas = class extends Canvas {
    // OffscreenCanvas is an EventTarget without a parent node. Chromium invokes
    // the listeners in registration order, including capture listeners.
    dispatchEvent(event) {
      for (const listener of this.listeners.slice()) {
        if (listener.type === event.type) listener.callback.call(this, event);
      }
    }
  };
  document.getElementById = id => id === 'finance-boot' ? { remove() { removals++; } } : null;
  window.addEventListener('finance-compass-repaint', () => repaints++);
  runInNewContext(bootstrap, {
    window, document, URL, URLSearchParams, Event, Date: { now: () => now }, navigator: { userAgent },
    _flutter: { loader: { load: options => { config = options.config; } } },
  });
  return {
    window, document, config, advance, navigations, repaints: () => repaints, removals: () => removals,
    visible(state) { document.visibilityState = state; document.emit('visibilitychange'); },
    offscreen() { return new window.OffscreenCanvas(); },
    html() { return new window.HTMLCanvasElement(); },
  };
}

test('hardware remains default, CPU opt-in preserves same-origin fonts; first frame dismisses startup shell once', () => {
  for (const userAgent of ['Android 14; Mobile', 'iPhone', 'Windows NT 10.0']) {
    const b = browser({ userAgent });
    assert.equal(b.config.canvasKitForceCpuOnly, false);
    assert.equal(b.config.fontFallbackBaseUrl, 'fonts/');
    assert.equal(b.removals(), 0);
    b.window.emit('flutter-first-frame'); b.window.emit('flutter-first-frame');
    assert.equal(b.removals(), 1);
  }
  const cpu = browser({ url: 'https://example.test/?cpu=1' });
  assert.equal(cpu.config.canvasKitForceCpuOnly, true);
  const c = cpu.offscreen(); c.getGL(); c.lose();
  cpu.window.emit('pageshow', { persisted: true }); cpu.advance();
  assert.ok(cpu.repaints() > 0); assert.deepEqual(cpu.navigations, []);
});

test('installed Android uses software by default and shares its render mode with Flutter effects', () => {
  const userAgent = 'Mozilla/5.0 (Linux; Android 14; Pixel)';
  for (const [standalone, agent, query, expected] of [
    [true, userAgent, '', true],
    [false, userAgent, '', false],
    [true, 'Mozilla/5.0 (iPhone)', '', false],
    [true, 'Windows', '', false],
    [true, userAgent, '?gpu=1', false],
    [true, userAgent, '?gpu=1&cpu=1', true],
  ]) {
    const b = browser({standalone, userAgent: agent, url: 'https://example.test/app/' + query});
    assert.equal(b.config.canvasKitForceCpuOnly, expected);
    assert.equal(b.window.financeCompassCpuRendering, expected);
  }
});

test('foreground and BFCache probe an already lost offscreen context even without an event', () => {
  for (const resume of [b => b.visible('visible'), b => b.window.emit('pageshow', { persisted: true })]) {
    const b = browser(), c = b.offscreen(); c.getGL();
    b.visible('hidden'); c.context.lost = true;
    b.advance(); assert.deepEqual(b.navigations, []);
    b.document.visibilityState = 'visible'; resume(b); b.advance();
    assert.ok(b.repaints() > 0); assert.deepEqual(b.navigations, [b.window.location.href]);
  }
});

test('non-composed loss after visible recovers, but hides and timely native repairs cancel navigation', () => {
  const b = browser(), c = b.html(); c.getGL();
  b.visible('visible'); b.advance(); c.lose();
  b.advance(200); b.visible('hidden'); b.advance();
  assert.deepEqual(b.navigations, []);
  b.visible('visible'); b.advance(200); c.restore(); b.advance();
  assert.deepEqual(b.navigations, []);
  c.lose(); b.advance(); assert.deepEqual(b.navigations, [b.window.location.href]);
});

test('Flutter can replace a lost surface synchronously while another independent surface stays tracked', () => {
  const b = browser(), retired = b.offscreen(), other = b.offscreen();
  let next;
  // CanvasProvider installs this listener before CanvasKit creates the GL context.
  retired.addEventListener('webglcontextlost', () => { next = b.offscreen(); next.getGL(); });
  retired.getGL(); other.getGL(); retired.lose(); b.advance();
  assert.ok(next); assert.ok(b.repaints() > 0);
  b.window.emit('pageshow', { persisted: true }); b.advance(); assert.deepEqual(b.navigations, []);
  other.lose(); b.advance(); assert.deepEqual(b.navigations, [b.window.location.href]);
});

test('renderer checks exclude feature probes and detached DOM surfaces', () => {
  const b = browser(), probe = b.html(), detached = b.html(), displayed = b.html();
  probe.getContext('webgl2'); detached.getGL(); displayed.getGL();
  probe.lose(); detached.isConnected = false; detached.lose();
  b.visible('visible'); b.advance(); assert.deepEqual(b.navigations, []);
  displayed.lose(); b.advance(); assert.equal(b.navigations.length, 1);
});

test('a late loss gets a full grace period after visible, even if detected by the probe', () => {
  for (const sendEvent of [true, false]) {
    const b = browser(), c = b.offscreen(); c.getGL();
    b.visible('visible'); b.advance(850);
    if (sendEvent) c.lose(); else c.context.lost = true;
    b.advance(100);
    assert.deepEqual(b.navigations, []);
    c.restore(); b.advance(1000);
    assert.deepEqual(b.navigations, []);
  }
});

test('consecutive failures switch this entry to CPU and denied session storage cannot loop', () => {
  const url = 'https://example.test/subpath/?account=x#detail';
  const storage = new Map();
  for (const [blocked, expected] of [[false, url], [false, url.replace('#', '&cpu=1#')], [true, url.replace('#', '&cpu=1#')]]) {
    const b = browser({ url, blocked, storage }), c = b.offscreen(); c.getGL(); c.lose(); b.advance();
    b.window.emit('pageshow', { persisted: true }); b.advance();
    assert.deepEqual(b.navigations, [expected]);
  }
});

test('in-memory pending changes survive loss and may recover after the write completes', () => {
  const b = browser(), c = b.offscreen(); c.getGL();
  b.window.financeCompassProtectPendingChanges = true;
  c.lose(); b.advance(4000); assert.deepEqual(b.navigations, []);
  b.window.financeCompassProtectPendingChanges = false; b.advance(4000);
  assert.deepEqual(b.navigations, [b.window.location.href]);
});

test('an open form requires confirmation and declining waits for a new foreground event', () => {
  const b = browser(), c = b.offscreen(); c.getGL();
  let prompts = 0, agreed = false;
  b.window.financeCompassHasOpenEditor = () => true;
  b.window.confirm = () => { prompts++; return agreed; };
  b.window.financeCompassProtectPendingChanges = true;
  c.lose(); b.advance(4000); assert.equal(prompts, 0);
  b.window.financeCompassProtectPendingChanges = false;
  b.advance(5000); assert.equal(prompts, 1); assert.deepEqual(b.navigations, []);
  agreed = true;
  b.window.emit('pageshow', { persisted: true }); b.advance();
  assert.equal(prompts, 2); assert.deepEqual(b.navigations, [b.window.location.href]);
});
