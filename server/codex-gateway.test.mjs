import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { chmod, lstat, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { request } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';
import { createFinanceGateway, listenPrivate } from '../deploy/sync/codex-gateway.mjs';
import { runAiChat } from './ai-chat.mjs';

const model = 'gpt-5.6-terra';
const allowed = '{"allowed":true,"reason":"finance"}';
const toolCall = { id: 'finance_1', name: 'get_monthly_overview', arguments: '{"month_key":"2026-11"}' };

// Build fixtures through Finance's real prompts/tool registry, including the
// additional role:tool messages used in a later model turn.
async function financeRequests() {
  const frames = [];
  const provider = {
    async gate({ messages }) {
      frames.push({ model, messages, stream: false, response_format: { type: 'json_object' } });
      return allowed;
    },
    async *stream({ messages, tools }) {
      frames.push(structuredClone({ model, messages, tools, stream: true }));
      if (frames.length === 2) yield { type: 'tool_calls', calls: [toolCall] };
      else yield { type: 'text', text: '本月支出为零。' };
    },
  };
  await runAiChat({ provider, input: { message: '我的预算情况如何？' },
    readLedger: () => ({ revision: 0, snapshot: null }), emit() {} });
  assert.equal(frames.length, 3);
  return frames;
}

async function fixture(t, runTurn, options = {}) {
  const { server, stop } = createFinanceGateway({ model, runTurn, ...options });
  let socketPath, dir;
  if (process.platform === 'win32') {
    socketPath = '\\\\.\\pipe\\finance-codex-' + randomUUID();
    server.listen(socketPath);
    await once(server, 'listening');
  } else {
    dir = await mkdtemp(join(tmpdir(), 'finance-codex-'));
    socketPath = join(dir, 'chat.sock');
    await listenPrivate(server, socketPath);
    assert.equal((await lstat(socketPath)).mode & 0o777, 0o600);
  }
  t.after(async () => {
    const closed = once(server, 'close');
    stop();
    await closed;
    if (dir) await rm(dir, { recursive: true, force: true });
  });
  const send = (body, settings = {}) => new Promise((resolve, reject) => {
    const req = request({ socketPath, path: '/v1/chat/completions', method: 'POST',
      headers: { 'content-type': 'application/json' }, agent: false, ...settings }, resolve);
    req.on('error', reject);
    req.end(JSON.stringify(body));
  });
  return send;
}

async function content(response) {
  const chunks = [];
  for await (const chunk of response) chunks.push(chunk);
  return Buffer.concat(chunks).toString();
}

test('private gateway forwards gate, ledger tools and true incremental reply slices', async t => {
  const [gate, first, next] = await financeRequests();
  const secondPart = Promise.withResolvers();
  t.after(() => secondPart.resolve());
  const send = await fixture(t, async ({ gate, messages, tools, onDelta }) => {
    if (gate) return { text: allowed };
    assert.equal(tools.length, 5);
    if (messages.at(-1).role !== 'tool') return { toolCall };
    await onDelta('账本');
    await secondPart.promise;
    await onDelta('余额。');
    return { text: '账本余额。' };
  });
  const decision = await send(gate);
  assert.equal(decision.statusCode, 200);
  assert.equal(JSON.parse(await content(decision)).choices[0].message.content, allowed);
  const toolReply = await send(first);
  assert.match(await content(toolReply), /"name":"get_monthly_overview".*\n\n[\s\S]*"finish_reason":"tool_calls"/);
  const response = await send(next);
  assert.equal(response.headers['cache-control'], 'no-store');
  const parts = response[Symbol.asyncIterator]();
  const early = (await parts.next()).value.toString();
  assert.match(early, /账本/);
  assert.doesNotMatch(early, /余额|DONE/);
  secondPart.resolve();
  let rest = '';
  for await (const chunk of parts) rest += chunk;
  assert.match(rest, /余额。/);
  assert.match(rest, /"finish_reason":"stop"[\s\S]*data: \[DONE\]/);
});

test('private gateway rejects unrecognized models, prompts, tool schemas and oversized bodies', async t => {
  const [gate, first, next] = await financeRequests();
  const send = await fixture(t, () => assert.fail('invalid request started a turn'));
  for (const body of [
    { ...gate, model: 'other' }, { ...gate, url: 'http://example.invalid/' },
    { ...gate, messages: [{ role: 'system', content: 'generic' }, gate.messages[1]] },
    { ...first, tools: [{ type: 'function', function: { name: 'unknown' } }] },
    { ...first, messages: [...first.messages, gate.messages[0]] },
    { ...next, messages: [...next.messages.slice(0, -1), { ...next.messages.at(-1), tool_call_id: 'other' }] },
  ]) {
    const response = await send(body);
    assert.equal(response.statusCode, 400);
    await content(response);
  }
  const tooLarge = await send({ message: 'x'.repeat(512 * 1024) });
  assert.equal(tooLarge.statusCode, 413);
  await content(tooLarge);
  const other = await send(gate, { path: '/v1/models' });
  assert.equal(other.statusCode, 404);
  await content(other);
});

test('gateway propagates transport cancellation and bounds simultaneous model calls', async t => {
  const [, first] = await financeRequests();
  const canceled = Promise.withResolvers();
  const send = await fixture(t, async ({ signal, onDelta }) => {
    await onDelta('开始');
    await once(signal, 'abort');
    canceled.resolve();
    throw new Error('private diagnostic');
  });
  const a = await send(first), b = await send(first);
  const limited = await send(first);
  assert.equal(limited.statusCode, 429);
  await content(limited);
  a.destroy();
  await canceled.promise;
  const next = await send(first);
  assert.equal(next.statusCode, 200);
  next.destroy();
  b.destroy();
});

test('gateway times out without exposing provider details or holding its slot', async t => {
  const [gate] = await financeRequests();
  let attempts = 0;
  const send = await fixture(t, async ({ signal }) => {
    if (++attempts === 1) {
      await once(signal, 'abort');
      await delay(5);
    }
    throw new Error('private diagnostic');
  }, { turnTimeoutMs: 50 });
  const timedOut = await send(gate);
  assert.equal(timedOut.statusCode, 504);
  assert.doesNotMatch(await content(timedOut), /private diagnostic/);
  const failed = await send(gate);
  assert.equal(failed.statusCode, 502);
  assert.doesNotMatch(await content(failed), /private diagnostic/);
});

test('private socket setup preserves unrelated files and an active peer', { skip: process.platform === 'win32' }, async t => {
  const dir = await mkdtemp(join(tmpdir(), 'finance-uds-'));
  const peer = createFinanceGateway({ model, runTurn() {} });
  const duplicate = createFinanceGateway({ model, runTurn() {} });
  const socketPath = join(dir, 'active.sock');
  await listenPrivate(peer.server, socketPath);
  t.after(async () => {
    const closed = once(peer.server, 'close');
    peer.stop();
    await closed;
    await rm(dir, { recursive: true, force: true });
  });
  await assert.rejects(listenPrivate(duplicate.server, socketPath), /already in use/);
  const regular = join(dir, 'regular');
  await writeFile(regular, 'preserve');
  await assert.rejects(listenPrivate(duplicate.server, regular), /Unexpected socket path/);
  await mkdir(join(dir, 'shared'), { mode: 0o755 });
  await chmod(join(dir, 'shared'), 0o755);
  await assert.rejects(listenPrivate(duplicate.server, join(dir, 'shared', 'chat.sock')), /must be private/);
});
