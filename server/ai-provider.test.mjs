import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setImmediate as nextTurn } from 'node:timers/promises';
import test from 'node:test';

import { createAiProvider } from './ai-provider.mjs';
import { createSyncServer } from './sync.mjs';
import { openStore } from './store.mjs';

async function gateway(t, handler, socketPath) {
  const server = createServer((req, res) => {
    void (async () => {
      let raw = '';
      for await (const part of req) raw += part;
      await handler(req, res, JSON.parse(raw));
    })().catch(error => res.destroy(error));
  });
  if (socketPath) server.listen(socketPath);
  else server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => {
    server.close(resolve);
    server.closeAllConnections();
  }));
  return socketPath ?? `http://127.0.0.1:${server.address().port}`;
}

const gateJson = '{"allowed":true,"reason":"in_scope"}';
const messages = [{ role: 'user', content: '本月支出？' }];
const tool = { type: 'function', function: { name: 'list_accounts', parameters: { type: 'object' } } };

function provider(url, env) {
  return createAiProvider({ FINANCE_AI_BASE_URL: url, FINANCE_AI_MODEL: 'chat-main', ...env });
}

function gateReply(res) {
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ choices: [{ message: { content: gateJson }, finish_reason: 'stop' }] }));
}

function event(delta, finish = null) {
  const data = JSON.stringify({ choices: [{ index: 0, delta, finish_reason: finish }] });
  return `data: ${data}\r\n\r\n`;
}

test('AI provider disables incomplete or unsafe configuration without exposing its settings', () => {
  assert.equal(createAiProvider({}), null);
  for (const url of ['file:///secret', 'ftp://proxy', 'https://user:pass@proxy/v1',
    'https://proxy/?token=x', 'http://proxy/#key', 'https://proxy/\npath']) {
    assert.equal(provider(url), null);
  }
  assert.equal(provider('http://proxy', { FINANCE_AI_MODEL: '' }), null);
  assert.equal(provider('http://proxy', { FINANCE_AI_PROVIDER: 'unsupported' }), null);
  assert.equal(provider('http://proxy', { FINANCE_AI_API_KEY: 'a\r\nb' }), null);
  assert.equal(provider('http://proxy', { FINANCE_AI_TIMEOUT_MS: 'NaN' }).timeoutMs, 90000);
  assert.equal(provider('http://proxy', { FINANCE_AI_TIMEOUT_MS: '900000' }).timeoutMs, 120000);
  assert.deepEqual(JSON.parse(JSON.stringify(provider('http://internal', { FINANCE_AI_API_KEY: 'mock-key' }))),
    { name: 'openai_compatible', timeoutMs: 90000 });
});

test('gate uses root, prefix, v1 and full completion URLs, optional credentials and independent model', async t => {
  const requests = [];
  const url = await gateway(t, (req, res, body) => {
    requests.push({ path: req.url, headers: req.headers, method: req.method, body });
    gateReply(res);
  });
  for (const path of ['', '/proxy', '/proxy/v1/', '/v1/chat/completions/']) {
    const config = path ? {} : { FINANCE_AI_GATE_MODEL: 'fast-gate', FINANCE_AI_API_KEY: 'mock-key' };
    assert.equal(await provider(url + path, config).gate({ messages }), gateJson);
  }
  assert.deepEqual(requests.map(r => r.path), [
    '/v1/chat/completions', '/proxy/v1/chat/completions', '/proxy/v1/chat/completions', '/v1/chat/completions',
  ]);
  for (const [index, request] of requests.entries()) {
    assert.equal(request.method, 'POST');
    assert.equal(request.headers.authorization, index ? undefined : 'Bearer mock-key');
    assert.deepEqual(request.body, {
      model: index ? 'chat-main' : 'fast-gate', messages, stream: false,
      response_format: { type: 'json_object' },
    });
  }
});

test('stream emits split UTF-8 text before completion and reconstructs interleaved tool calls', async t => {
  let release;
  const waiting = new Promise(resolve => { release = resolve; });
  t.after(release);
  let observed;
  const url = await gateway(t, async (req, res, body) => {
    observed = { body, accept: req.headers.accept };
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    const first = Buffer.from(': comment\r\n\r\n' + event({ content: '账本' }));
    const index = first.indexOf(Buffer.from('账')) + 1;
    res.write(first.subarray(0, index));
    await nextTurn();
    res.write(first.subarray(index, -1));
    await nextTurn();
    res.write(first.subarray(-1));
    await waiting;
    res.write(event({ tool_calls: [
      { index: 1, id: 'call:b', type: 'function', function: { name: 'list_', arguments: '{' } },
      { index: 0, id: 'call:', type: 'function', function: { name: 'search_', arguments: '{"text":' } },
    ] }));
    res.write(event({ tool_calls: [
      { index: 0, id: 'a', function: { name: 'transactions', arguments: '"午餐"}' } },
      { index: 1, function: { name: 'accounts', arguments: '}' } },
    ] }, 'tool_calls'));
    res.end('data: {"choices":[],\ndata: "usage":{}}\n\ndata: [DONE]\n\n');
  });
  const stream = provider(url).stream({ messages, tools: [tool] });
  const first = await stream.next();
  assert.deepEqual(first.value, { type: 'text', text: '账本' });
  release();
  assert.deepEqual(await Array.fromAsync(stream), [{ type: 'tool_calls', calls: [
    { id: 'call:a', name: 'search_transactions', arguments: '{"text":"午餐"}' },
    { id: 'call:b', name: 'list_accounts', arguments: '{}' },
  ] }]);
  assert.deepEqual(observed.body, { model: 'chat-main', messages, stream: true, tools: [tool] });
  assert.equal(observed.accept, 'text/event-stream');
});

test('upstream errors, redirects and malformed gate results fail closed without leaking their content', async t => {
  let mode = 'redirect';
  let followed = false;
  const url = await gateway(t, (req, res) => {
    if (req.url.includes('/secret-destination')) followed = true;
    if (mode === 'redirect') {
      res.writeHead(307, { location: '/secret-destination' });
      res.end();
    } else if (mode === 'error') {
      res.writeHead(403);
      res.end('mock-private-error');
    } else if (mode === 'oversize') {
      res.end('x'.repeat(33 * 1024));
    } else {
      res.end(JSON.stringify({ choices: [{ finish_reason: 'length', message: { content: gateJson } }] }));
    }
  });
  for (mode of ['redirect', 'error', 'oversize', 'truncated']) {
    await assert.rejects(provider(url).gate({ messages }), { message: 'AI 网关暂不可用。' });
  }
  assert.equal(followed, false);
});

test('invalid and oversized tool identity, duplicate IDs, broken JSON and truncated streams fail safely', async t => {
  let body;
  const url = await gateway(t, (_req, res) => res.end(body));
  const call = (id, index) => ({ index, id, function: { name: 'search', arguments: '{}' } });
  for (body of [
    event({ content: 'part' }),
    'data: {"error":{"message":"mock-private-error"}}\n\n',
    'data: not-json\n\n',
    event({}, 'length'),
    event({ tool_calls: [call('a', 0), call('a', 1)] }, 'tool_calls'),
    event({ tool_calls: [call('a'.repeat(129), 0)] }, 'tool_calls'),
    event({ tool_calls: [call('a\nb', 0)] }, 'tool_calls'),
    event({ tool_calls: [call('a', 1)] }, 'tool_calls'),
  ]) {
    await assert.rejects(Array.fromAsync(provider(url).stream({ messages })), { message: 'AI 网关暂不可用。' });
  }
});

test('deadline aborts blocked gate; interrupted stream closes upstream and exposes no abort reason', async t => {
  let onDisconnect;
  const disconnected = new Promise(resolve => { onDisconnect = resolve; });
  const url = await gateway(t, (_req, res, body) => {
    if (body.stream) {
      res.on('close', onDisconnect);
      res.write(event({ content: '一' }));
    }
  });
  const client = provider(url, { FINANCE_AI_TIMEOUT_MS: '100' });
  await assert.rejects(client.gate({ messages }), { message: 'AI 请求已取消或超时。' });
  const controller = new AbortController();
  const stream = provider(url).stream({ messages, signal: controller.signal });
  assert.equal((await stream.next()).value.text, '一');
  const pending = stream.next();
  controller.abort('mock-private-reason');
  await assert.rejects(pending, { message: 'AI 请求已取消或超时。' });
  await disconnected;
});

function uniqueSocket() {
  const name = 'finance-terra-' + randomUUID();
  return process.platform === 'win32' ? '\\\\.\\pipe\\' + name : join(tmpdir(), name + '.sock');
}

function terra(socketPath, options) {
  return createAiProvider({
    FINANCE_AI_PROVIDER: 'codex_terra', FINANCE_AI_MODEL: 'gpt-5.6-terra',
    FINANCE_AI_CODEX_SOCKET: socketPath,
    FINANCE_AI_BASE_URL: 'http://unused.invalid', FINANCE_AI_API_KEY: 'unused-test-key',
  }, options);
}

test('Codex uses its private socket for gate and live deltas and cancels a stalled upstream', { timeout: 15_000 }, async t => {
  const disconnected = Promise.withResolvers();
  const received = [];
  const path = await gateway(t, (req, res, body) => {
    received.push({ path: req.url, method: req.method, authorization: req.headers.authorization, body });
    if (!body.stream) return gateReply(res);
    res.on('close', disconnected.resolve);
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(event({ content: '第一段' }));
  }, uniqueSocket());
  const client = terra(path);
  assert.equal(await client.gate({ messages }), gateJson);
  const controller = new AbortController();
  const stream = client.stream({ messages, tools: [tool], signal: controller.signal });
  assert.deepEqual((await stream.next()).value, { type: 'text', text: '第一段' });
  const pending = stream.next();
  controller.abort();
  await assert.rejects(pending, { message: 'AI 请求已取消或超时。' });
  await disconnected.promise;
  assert.equal(received.length, 2);
  for (const request of received) {
    assert.equal(request.body.model, 'gpt-5.6-terra');
    assert.equal(request.path, '/v1/chat/completions');
    assert.equal(request.method, 'POST');
    assert.equal(request.authorization, undefined);
  }
  assert.deepEqual(received[1].body.tools, [tool]);
});

test('Codex configuration and a missing private socket never fall back to TCP', async () => {
  for (const invalid of [undefined, '', 'relative/run.sock', 'http://host/run.sock', '//remote/share']) {
    assert.equal(terra(invalid), null);
  }
  const client = terra(uniqueSocket(), { fetchImpl() { assert.fail('Unexpected external transport'); } });
  await assert.rejects(client.gate({ messages }), { message: 'AI 网关暂不可用。' });
});

test('authenticated AI status identifies Terra with only its public adapter name', async t => {
  const store = openStore(':memory:');
  const session = await store.register('test-terra-owner', 'test-terra-owner-password');
  const server = createSyncServer({ store, aiProvider: terra(uniqueSocket()), origin: 'https://example.test' });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => {
    server.closeAllConnections();
    server.close();
    store.close();
  });
  const response = await fetch(`http://127.0.0.1:${server.address().port}/api/sync/v1/ai/status`, {
    headers: { Cookie: '__Host-finance_session=' + session.token, 'X-Finance-Account': '1' },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { enabled: true, streaming: true, provider: 'codex_terra' });
});
