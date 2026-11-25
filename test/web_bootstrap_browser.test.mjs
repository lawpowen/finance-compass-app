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

test('Chrome keeps an edited page after replacing real Offscreen and Shadow DOM GL surfaces', {
  skip: !process.env.CHROME_EXECUTABLE && 'Set CHROME_EXECUTABLE to the local Chrome executable',
}, async t => {
  const source = await readFile(new URL('../web/flutter_bootstrap.js', import.meta.url), 'utf8');
  const bootstrap = source.replace('{{flutter_js}}', 'window._flutter = {loader: {load() {}}};')
    .replace('{{flutter_build_config}}', '');
  let visits = 0;
  const result = Promise.withResolvers();
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/') {
      visits++;
      res.setHeader('content-type', 'text/html');
      if (visits > 1) result.reject(new Error('A lost, replaced surface reloaded the edited document'));
      res.end(`<!doctype html><input><main></main>
        <script src="/bootstrap.js"></script><script>(${probe})()</script>`);
    } else if (url.pathname === '/bootstrap.js') {
      res.setHeader('content-type', 'text/javascript');
      res.end(bootstrap);
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
    '--user-data-dir=' + profile, 'http://127.0.0.1:' + server.address().port,
  ], {windowsHide: true, stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe']});
  const exited = once(chrome, 'close');
  const timeout = setTimeout(() => result.reject(new Error('Timed out waiting for WebGL recovery')), 90000);
  try {
    const checks = await Promise.race([result.promise, exited.then(() => {
      throw new Error('Chrome closed before the WebGL check completed');
    })]);
    assert.deepEqual(JSON.parse(checks), [true, true], 'both renderers should repaint and preserve the input');
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
});
