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

function browser({ url = 'https://example.test/finance/', storage = new Map(), blocked = false, now = 100000,
  userAgent = '', standalone = false, htmlRegistrationOrder = false } = {}) {
  const window = new Target();
  window.matchMedia = query => ({ matches: standalone && query === '(display-mode: standalone)' });
  const document = new Target();
  document.visibilityState = 'visible';
  let config, repaints = 0, removals = 0;
  const navigations = [], timers = new Map();
  let sequence = 0;
  window.location = {
    href: url, search: new URL(url).search,
    reload: () => navigations.push(url), replace: next => navigations.push(next),
  };
  window.sessionStorage = {
    getItem: key => { if (blocked) throw new Error('denied'); return storage.get(key) ?? null; },
    setItem: (key, value) => { if (blocked) throw new Error('denied'); storage.set(key, value); },
    removeItem: key => { if (blocked) throw new Error('denied'); storage.delete(key); },
  };
  window.setTimeout = (fn, delay) => { timers.set(++sequence, { at: now + delay, fn }); return sequence; };
  window.clearTimeout = id => timers.delete(id);
  window.requestAnimationFrame = fn => window.setTimeout(() => fn(now), 16);
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
  class RegistrationOrderCanvas extends Canvas {
    // OffscreenCanvas is an EventTarget without a parent node. Chromium invokes
    // the listeners in registration order, including capture listeners.
    dispatchEvent(event) {
      for (const listener of this.listeners.slice()) {
        if (listener.type === event.type) listener.callback.call(this, event);
      }
    }
  }
  window.HTMLCanvasElement = class extends (htmlRegistrationOrder ? RegistrationOrderCanvas : Canvas) { isConnected = true; };
  window.OffscreenCanvas = class extends RegistrationOrderCanvas {};
  const elements = new Map([['finance-boot', { remove() { removals++; elements.delete('finance-boot'); } }]]);
  document.createElement = () => ({ setAttribute() {}, remove() { elements.delete(this.id); } });
  document.body = { appendChild(node) { elements.set(node.id, node); } };
  document.getElementById = id => elements.get(id) ?? null;
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

test('installed Android uses WebGL by default and shares its render mode with Flutter effects', () => {
  const userAgent = 'Mozilla/5.0 (Linux; Android 14; Pixel)';
  for (const [standalone, agent, query, expected] of [
    [true, userAgent, '', false],
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

test('two failures within a minute recover at the original URL; the CPU session expires', () => {
  const url = 'https://example.test/subpath/?account=x#detail';
  const storage = new Map();
  for (const now of [100000, 160000]) {
    const b = browser({ url, storage, now }), c = b.offscreen();
    assert.equal(b.config.canvasKitForceCpuOnly, false);
    c.getGL(); c.lose(); b.advance();
    assert.deepEqual(b.navigations, [url]);
  }
  const at = Number(storage.get('finance-compass-cpu-fallback'));
  assert.ok(at >= 160000 && at <= 161000);
  assert.equal(browser({ url, storage, now: at + 599999 }).config.canvasKitForceCpuOnly, true);
  assert.equal(browser({ url, now: at + 1000 }).config.canvasKitForceCpuOnly, false);
  assert.equal(browser({ url, storage, now: at + 600000 }).config.canvasKitForceCpuOnly, false);
  assert.equal(storage.has('finance-compass-cpu-fallback'), false);
});

test('separate losses over a minute apart remain hardware retries', () => {
  const storage = new Map();
  for (const now of [100000, 160001]) {
    const b = browser({ storage, now }), c = b.html();
    c.getGL(); c.lose(); b.advance();
    assert.deepEqual(b.navigations, [b.window.location.href]);
  }
  assert.equal(browser({ storage, now: 162000 }).config.canvasKitForceCpuOnly, false);
});

test('GPU override clears the temporary session flag; explicit CPU wins', () => {
  const storage = new Map([['finance-compass-cpu-fallback', '99000']]);
  const boot = query => browser({ storage, url: 'https://example.test/' + query });
  assert.equal(boot('?gpu=1&cpu=1').config.canvasKitForceCpuOnly, true);
  assert.equal(boot('?gpu=1').config.canvasKitForceCpuOnly, false);
  assert.equal(storage.has('finance-compass-cpu-fallback'), false);
  assert.equal(boot('').config.canvasKitForceCpuOnly, false);
});

test('a warm installed PWA returns from expired CPU fallback only on a safe foreground', () => {
  for (const protectedBy of ['editor', 'write']) {
    const storage = new Map([['finance-compass-cpu-fallback', '100000']]);
    const b = browser({ storage, userAgent: 'Android', standalone: true });
    assert.equal(b.config.canvasKitForceCpuOnly, true);
    b.advance(600000);
    assert.deepEqual(b.navigations, []);
    b.window.emit('pageshow'); b.advance(); // initial display, not an app return
    assert.deepEqual(b.navigations, []);
    b.window.financeCompassHasOpenEditor = () => protectedBy === 'editor';
    b.window.financeCompassProtectPendingChanges = protectedBy === 'write';
    b.window.emit('pageshow', {persisted: true}); b.advance();
    assert.equal(b.document.getElementById('finance-recovery'), null);
    assert.deepEqual(b.navigations, []);
    b.window.financeCompassHasOpenEditor = () => false;
    b.window.financeCompassProtectPendingChanges = false;
    b.visible('hidden'); b.visible('visible'); b.advance(32);
    b.window.emit('pageshow', {persisted: true}); b.advance();
    assert.deepEqual(b.navigations, [b.window.location.href]);
    assert.equal(browser({ storage, now: 800000 }).config.canvasKitForceCpuOnly, false);
  }
});

test('manual CPU choice stays put on warm return; a newly opened editor cancels a pending GPU return', () => {
  const cpu = browser({ url: 'https://example.test/?cpu=1' });
  cpu.advance(900000); cpu.visible('hidden'); cpu.visible('visible'); cpu.advance();
  assert.deepEqual(cpu.navigations, []);
  const storage = new Map([['finance-compass-cpu-fallback', '100000']]);
  const b = browser({storage});
  storage.clear();
  b.window.emit('pageshow', {persisted: true});
  assert.ok(b.document.getElementById('finance-recovery'));
  b.window.financeCompassHasOpenEditor = () => true;
  b.advance(); assert.deepEqual(b.navigations, []);
  assert.equal(b.document.getElementById('finance-recovery'), null);
});

test('storage denial alone uses the CPU URL escape hatch', () => {
  const url = 'https://example.test/subpath/?account=x#detail';
  const b = browser({ url, blocked: true }), c = b.offscreen();
  assert.equal(b.config.canvasKitForceCpuOnly, false);
  c.getGL(); c.lose(); b.advance();
  assert.deepEqual(b.navigations, [url.replace('#', '&cpu=1#')]);
  const reopened = browser({ url: b.navigations[0], blocked: true });
  assert.equal(reopened.config.canvasKitForceCpuOnly, true);
});

test('a background loss uses a shorter grace, then paints a branded cover before reload', () => {
  const b = browser(), c = b.html();
  c.getGL(); b.visible('hidden'); c.lose(); b.advance();
  b.visible('visible'); b.advance(349);
  assert.equal(b.document.getElementById('finance-recovery'), null);
  b.advance(1);
  const overlay = b.document.getElementById('finance-recovery');
  assert.ok(overlay?.textContent);
  assert.deepEqual(b.navigations, []);
  b.advance(16); assert.deepEqual(b.navigations, []);
  b.advance(16); assert.deepEqual(b.navigations, [b.window.location.href]);
});

test('BFCache restore speeds up an outstanding probe and a delayed native loss keeps its deadline', () => {
  const b = browser(), c = b.html(); c.getGL();
  b.window.emit('pageshow'); b.advance(20);
  c.context.lost = true;
  b.window.emit('pageshow', {persisted: true}); b.advance(300);
  c.lose(); b.advance(49);
  assert.equal(b.document.getElementById('finance-recovery'), null);
  b.advance(1);
  assert.ok(b.document.getElementById('finance-recovery'));
});

test('a different surface losing context during the cover paint gets its own full grace', () => {
  const b = browser(), first = b.html(), second = b.offscreen();
  first.getGL(); second.getGL(); first.lose(); b.advance(900);
  assert.ok(b.document.getElementById('finance-recovery'));
  first.restore(); second.lose(); b.advance(32);
  assert.deepEqual(b.navigations, []);
  assert.equal(b.document.getElementById('finance-recovery'), null);
  second.restore(); b.advance(1000);
  assert.deepEqual(b.navigations, []);
});

test('a foreground loss receives 900ms, and recovery or protected state during paint cancels navigation', () => {
  for (const change of ['restored', 'saving', 'hidden', 'new-editor']) {
    const b = browser(), c = b.html();
    b.window.emit('flutter-first-frame');
    c.getGL(); c.lose(); b.advance(899);
    assert.equal(b.document.getElementById('finance-recovery'), null);
    b.advance(1); assert.ok(b.document.getElementById('finance-recovery'));
    if (change === 'restored') c.restore();
    if (change === 'saving') b.window.financeCompassProtectPendingChanges = true;
    if (change === 'hidden') b.visible('hidden');
    if (change === 'new-editor') {
      b.window.financeCompassHasOpenEditor = () => true;
      b.window.confirm = () => false;
    }
    b.advance(2000);
    assert.deepEqual(b.navigations, []);
    assert.equal(b.document.getElementById('finance-recovery'), null);
  }
});

test('HTML canvas engines with registration-order AT_TARGET dispatch retire the exact replaced surface', () => {
  const b = browser({htmlRegistrationOrder: true}), c = b.html();
  c.addEventListener('webglcontextlost', () => b.html().getGL());
  c.getGL(); c.lose(); b.advance();
  assert.ok(b.repaints() > 0); assert.deepEqual(b.navigations, []);
});

test('persistent explicit GPU override cannot automatically cycle through repeated reloads', () => {
  const storage = new Map(), url = 'https://example.test/?gpu=1';
  const first = browser({ storage, url }), c = first.html();
  c.getGL(); c.lose(); first.advance();
  assert.deepEqual(first.navigations, [url]);
  const again = browser({ storage, url, now: 102000 }), d = again.html();
  let prompts = 0;
  again.window.confirm = () => { prompts++; return false; };
  d.getGL(); d.lose(); again.advance(5000);
  assert.equal(prompts, 1); assert.deepEqual(again.navigations, []);
  assert.equal(again.document.getElementById('finance-recovery'), null);
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
