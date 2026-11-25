import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, realpath, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

// This function runs inside the browser, using real non-composed GL events.
async function probe() {
  const result = [];
  try {
    const input = document.querySelector('input');
    input.value = 'unsaved ledger entry';
    const shadow = document.querySelector('main').attachShadow({mode: 'closed'});
    const factories = [
      () => new OffscreenCanvas(128, 128),
      () => shadow.appendChild(document.createElement('canvas')),
    ];
    let repaints = 0;
    window.addEventListener('finance-compass-repaint', () => repaints++);
    for (const createCanvas of factories) {
      const oldCanvas = createCanvas(), initialRepaints = repaints;
      const options = {majorVersion: 2};
      // Flutter 3.44 CanvasProvider installs this before CanvasKit calls getContext.
      const replaced = new Promise(resolve => {
        oldCanvas.addEventListener('webglcontextlost', () => {
          resolve(createCanvas().getContext('webgl2', options));
        });
      });
      const original = oldCanvas.getContext('webgl2', options);
      original.getExtension('WEBGL_lose_context').loseContext();
      const replacement = await replaced;
      // Allow both the foreground probe and its recovery grace period to expire.
      await new Promise(resolve => setTimeout(resolve, 2200));
      result.push(original.isContextLost() && !replacement.isContextLost() &&
        repaints > initialRepaints && input.value === 'unsaved ledger entry');
    }
  } catch (error) {
    result.push(String(error));
  }
  await fetch('/result?' + new URLSearchParams({checks: JSON.stringify(result)}));
}

// Each visit runs with Chrome's real sessionStorage and location. Keep the
// observations across navigations so the last document can report the result.
async function probePersistentLoss() {
  const key = 'probe.visits';
  const visits = JSON.parse(sessionStorage.getItem(key) ?? '[]');
  const current = {
    url: location.pathname + location.search + location.hash,
    software: window.financeCompassCpuRendering,
    loaderSoftware: window.probeLoaderSoftware,
    coverVisibleInFrame: false,
  };
  visits.push(current);
  sessionStorage.setItem(key, JSON.stringify(visits));
  if (visits.length <= 2) {
    const canvas = document.body.appendChild(document.createElement('canvas'));
    const gl = canvas.getContext('webgl2', {majorVersion: 2});
    let coveredFrames = 0;
    // Two animation ticks give the browser a paint opportunity between them.
    // Record at navigation start, independent of the next HTTP response time.
    window.navigation.addEventListener('navigate', () => {
      current.coverVisibleInFrame = coveredFrames >= 2;
      sessionStorage.setItem(key, JSON.stringify(visits));
    }, {once: true});
    function observeFrame() {
      const cover = document.getElementById('finance-recovery');
      if (cover) {
        const rect = cover.getBoundingClientRect();
        const style = getComputedStyle(cover);
        const covering =
          rect.left <= 0 && rect.top <= 0 &&
          rect.right >= innerWidth && rect.bottom >= innerHeight &&
          style.backgroundColor === 'rgb(18, 59, 58)' &&
          style.visibility === 'visible' && style.opacity === '1' &&
          cover.contains(document.elementFromPoint(innerWidth / 2, innerHeight / 2)) &&
          cover.textContent.trim().length > 0;
        coveredFrames = covering ? coveredFrames + 1 : 0;
      }
      if (coveredFrames < 2) requestAnimationFrame(observeFrame);
    }
    requestAnimationFrame(observeFrame);
    gl.getExtension('WEBGL_lose_context').loseContext();
    return;
  }
  if (visits.length === 3 || visits.length === 4) {
    const next = new URL(location.href);
    if (visits.length === 3) next.searchParams.set('gpu', '1');
    else next.searchParams.delete('gpu');
    location.assign(next);
    return;
  }
  await fetch('/result?' + new URLSearchParams({checks: JSON.stringify(visits)}));
}

const chromeRequired = {
  skip: !process.env.CHROME_EXECUTABLE && 'Set CHROME_EXECUTABLE to the local Chrome executable',
};

async function runBrowser(t, scenario, maxVisits) {
  const [source, index, caddy] = await Promise.all([
    '../web/flutter_bootstrap.js', '../web/index.html', '../deploy/sync/Caddyfile',
  ].map(name => readFile(new URL(name, import.meta.url), 'utf8')));
  const bootstrap = source.replace('{{flutter_js}}',
    'window._flutter = {loader: {load({config}) { window.probeLoaderSoftware = config.canvasKitForceCpuOnly; }}};')
    .replace('{{flutter_build_config}}', '');
  const bootStyle = index.match(/<style>[\s\S]*?<\/style>/)[0];
  const csp = caddy.match(/Content-Security-Policy\s+"([^"]+)"/)[1];
  let visits = 0;
  const result = Promise.withResolvers();
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/ledger') {
      visits++;
      res.setHeader('content-type', 'text/html');
      res.setHeader('content-security-policy', csp);
      if (visits > maxVisits) result.reject(new Error('Unexpected navigation during WebGL recovery'));
      res.end(`<!doctype html><meta charset="utf-8">${bootStyle}
        <body><div id="finance-boot" role="status">正在打开 Finance Compass…</div>
        <input><main></main><script src="/bootstrap.js"></script><script src="/probe.js"></script>`);
    } else if (url.pathname === '/bootstrap.js') {
      res.setHeader('content-type', 'text/javascript');
      res.end(bootstrap);
    } else if (url.pathname === '/probe.js') {
      res.setHeader('content-type', 'text/javascript');
      res.end(`window.dispatchEvent(new Event('flutter-first-frame'));
        (${scenario})().catch(error => fetch('/result?' + new URLSearchParams({checks: JSON.stringify(String(error))})));`);
    } else if (url.pathname === '/result') {
      result.resolve(url.searchParams.get('checks'));
      res.end();
    } else {
      res.writeHead(404).end();
    }
  });
  const temp = await realpath(tmpdir());
  const profile = await mkdtemp(path.join(temp, 'finance-webgl-test-'));
  t.after(async () => {
    server.closeAllConnections();
    server.close();
    const actual = await realpath(profile);
    assert.equal(path.dirname(actual), temp);
    assert.ok(path.basename(actual).startsWith('finance-webgl-test-'));
    await rm(actual, {recursive: true, force: true, maxRetries: 5, retryDelay: 200});
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject).listen(0, '127.0.0.1', resolve);
  });
  const chrome = spawn(process.env.CHROME_EXECUTABLE, [
    '--headless=new', '--remote-debugging-pipe', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--disable-extensions',
    '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--user-data-dir=' + profile, 'http://127.0.0.1:' + server.address().port + '/ledger?account=a#form',
  ], {windowsHide: true, stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe']});
  const exited = once(chrome, 'close');
  const timeout = setTimeout(() => result.reject(new Error('Timed out waiting for WebGL recovery')), 90000);
  try {
    const checks = await Promise.race([result.promise, exited.then(() => {
      throw new Error('Chrome closed before the WebGL check completed');
    })]);
    return JSON.parse(checks);
  } finally {
    clearTimeout(timeout);
    if (chrome.pid && chrome.exitCode === null) {
      // A single pipe command closes the isolated browser and its GPU process.
      chrome.stdio[3].on('error', () => {});
      chrome.stdio[3].end(JSON.stringify({id: 1, method: 'Browser.close'}) + '\0');
      const stop = setTimeout(() => chrome.kill(), 3000);
      try { await exited; } finally { clearTimeout(stop); }
    }
  }
}

test('Chrome keeps an edited page after replacing real Offscreen and Shadow DOM GL surfaces', chromeRequired, async t => {
  const checks = await runBrowser(t, probe, 1);
  assert.deepEqual(checks, [true, true], 'both renderers should repaint and preserve the input');
});

test('Chrome displays the recovery shell, reloads the original URL and can leave temporary software mode', chromeRequired, async t => {
  const visits = await runBrowser(t, probePersistentLoss, 5);
  const original = '/ledger?account=a#form';
  assert.deepEqual(visits.map(v => v.url),
    [original, original, original, '/ledger?account=a&gpu=1#form', original]);
  assert.deepEqual(visits.map(v => v.software), [false, false, true, false, false]);
  assert.deepEqual(visits.map(v => v.loaderSoftware), visits.map(v => v.software));
  assert.deepEqual(visits.map(v => v.coverVisibleInFrame), [true, true, false, false, false]);
});
