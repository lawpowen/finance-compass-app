import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const bootstrap = readFileSync(
  new URL('../web/flutter_bootstrap.js', import.meta.url),
  'utf8',
).replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

function browserBootstrap(search = '', navigator = {}) {
  let config;
  let reloads = 0;
  const windowEvents = new Map();
  const documentEvents = new Map();
  const timers = [];
  const document = {
    visibilityState: 'visible',
    addEventListener: (event, listener) => documentEvents.set(event, listener),
  };
  runInNewContext(bootstrap, {
    navigator,
    URLSearchParams,
    document,
    window: {
      location: { search, reload: () => reloads++ },
      addEventListener: (event, listener) => windowEvents.set(event, listener),
      setTimeout: (callback, delay) => timers.push({ callback, delay }),
    },
    _flutter: { loader: { load: (options) => { config = options.config; } } },
  });
  return { config, document, windowEvents, documentEvents, timers, reloads: () => reloads };
}

test('Android, desktop and iOS use WebGL by default with same-origin fonts', () => {
  for (const userAgent of [
    'Mozilla/5.0 (Linux; Android 14; Pixel) Chrome/143 Mobile',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/143',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) Mobile Safari',
  ]) {
    const { config } = browserBootstrap('', { userAgent });
    assert.equal(config.canvasKitForceCpuOnly, false);
    assert.equal(config.fontFallbackBaseUrl, 'fonts/');
  }
});

test('the cpu query parameter opts into software rendering', () => {
  assert.equal(browserBootstrap('?cpu=1').config.canvasKitForceCpuOnly, true);
});

test('foreground recovery retries only an unrestored lost WebGL context', () => {
  const state = browserBootstrap();
  let prevented = false;
  const lost = () => state.windowEvents.get('webglcontextlost')({
    preventDefault: () => { prevented = true; },
  });
  const visibilityChanged = () => state.documentEvents.get('visibilitychange')();

  lost();
  assert.equal(prevented, true);
  state.document.visibilityState = 'hidden';
  visibilityChanged();
  assert.equal(state.timers.length, 0);
  state.document.visibilityState = 'visible';
  visibilityChanged();
  const recovered = state.timers.shift();
  assert.equal(recovered.delay, 900);
  state.windowEvents.get('webglcontextrestored')();
  recovered.callback();
  assert.equal(state.reloads(), 0);

  lost();
  visibilityChanged();
  state.timers.shift().callback();
  assert.equal(state.reloads(), 1);
});
