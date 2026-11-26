import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { PassThrough, Writable } from 'node:stream';
import test from 'node:test';
import { runCodexTurn } from '../deploy/sync/codex-turn.mjs';

const model = 'gpt-5.6-terra';
const messages = [{ role: 'system', content: '只读财务范围' }, { role: 'user', content: '测试账本本月预算' }];
const tool = { type: 'function', function: { name: 'get_monthly_overview', description: '月度预算',
  parameters: { type: 'object', properties: {}, additionalProperties: false } } };
const threadId = 'thread-test', turnId = 'turn-test';
const cwd = '/private/finance/empty-workspace';

function harness({ config = {}, mcp = [], turn, threadInventory = [] } = {}) {
  const child = new EventEmitter();
  child.stdout = new PassThrough();
  const requests = [];
  let kills = 0;
  child.kill = () => {
    kills++;
    child.stdout.end();
  };
  const emit = data => child.stdout.write(JSON.stringify(data) + '\n');
  const notice = (method, params) => emit({ method, params: { threadId, turnId, ...params } });
  child.stdin = new Writable({ write(chunk, _, callback) {
    const msg = JSON.parse(chunk.toString());
    requests.push(msg);
    switch (msg.method) {
      case 'initialize': emit({ id: msg.id, result: { userAgent: 'fixture' } }); break;
      case 'mcpServerStatus/list':
        emit({ id: msg.id, result: { data: msg.params.threadId ? threadInventory : mcp } }); break;
      case 'thread/start':
        emit({ id: msg.id, result: { cwd, model, modelProvider: 'openai', thread: {
          id: threadId, cliVersion: '0.145.0', ephemeral: true }, approvalPolicy: 'never',
          sandbox: { type: 'readOnly', networkAccess: false }, instructionSources: [], ...config } });
        break;
      case 'turn/start':
        emit({ id: msg.id, result: { turn: { id: turnId } } });
        queueMicrotask(() => turn?.(notice, emit));
    }
    callback();
  } });
  return {
    run: (opts = {}) => runCodexTurn({ model, messages, tools: [tool], ...opts }, { cwd, launch: () => child }),
    requests, get kills() { return kills; },
  };
}
const start = (notice, phase, id) => notice('item/started', { item: { type: 'agentMessage', id, phase } });
const delta = (notice, id, text) => notice('item/agentMessage/delta', { itemId: id, delta: text });
const finish = (notice, phase, id, text) =>
  notice('item/completed', { item: { type: 'agentMessage', id, phase, text } });
const done = notice => notice('turn/completed', { turn: { id: turnId, status: 'completed' } });

test('Terra emits live final-answer deltas, suppresses private phases and starts without environment access', async () => {
  const first = Promise.withResolvers(), release = Promise.withResolvers();
  const h = harness({ async turn(notice) {
    notice('item/reasoning/textDelta', { delta: 'PRIVATE' });
    start(notice, 'commentary', 'c'); delta(notice, 'c', 'COMMENTARY');
    finish(notice, 'commentary', 'c', 'COMMENTARY');
    start(notice, 'final_answer', 'f'); delta(notice, 'f', '预算');
    await release.promise;
    delta(notice, 'f', '充足'); finish(notice, 'final_answer', 'f', '预算充足'); done(notice);
  } });
  const pieces = [];
  const answer = h.run({ onDelta: part => { pieces.push(part); first.resolve(); } });
  await first.promise;
  assert.deepEqual(pieces, ['预算']);
  assert.equal(h.kills, 0);
  release.resolve();
  assert.deepEqual(await answer, { text: '预算充足' });
  assert.deepEqual(pieces, ['预算', '充足']);
  assert.equal(h.kills, 1);
  const thread = h.requests.find(r => r.method === 'thread/start').params;
  const turn = h.requests.find(r => r.method === 'turn/start').params;
  assert.equal(thread.allowProviderModelFallback, false);
  assert.equal(thread.cwd, cwd);
  assert.equal(thread.sandbox, 'read-only');
  assert.equal(thread.ephemeral, true);
  assert.deepEqual(thread.environments, []);
  assert.deepEqual(thread.selectedCapabilityRoots, []);
  assert.deepEqual(turn.environments, []);
  assert.equal(turn.approvalPolicy, 'never');
  assert.equal(thread.dynamicTools[0].name, tool.function.name);
  assert.deepEqual(JSON.parse(turn.input[0].text), messages.slice(1));
});

test('gate requests strict JSON without Finance tools and renders a legacy unphased final answer only on completion', async () => {
  const json = '{"allowed":true,"reason":"finance"}';
  const h = harness({ turn(notice) {
    start(notice, null, '1'); delta(notice, '1', 'interim'); finish(notice, null, '1', 'interim');
    start(notice, null, '2'); delta(notice, '2', json); finish(notice, null, '2', json); done(notice);
  } });
  assert.deepEqual(await h.run({ gate: true, tools: [], onDelta: () => assert.fail() }), { text: json });
  const turn = h.requests.find(r => r.method === 'turn/start').params;
  assert.deepEqual(turn.outputSchema.required, ['allowed', 'reason']);
});

test('returns a Finance dynamic tool request to the sync service and closes that turn', async () => {
  const h = harness({ turn(_, emit) {
    emit({ id: 'tool-id', method: 'item/tool/call', params: {
      threadId, turnId, tool: 'get_monthly_overview', callId: 'call_1', arguments: { month_key: '2026-11' },
    } });
  } });
  assert.deepEqual(await h.run(), { text: '', toolCall: { id: 'call_1', name: 'get_monthly_overview',
    arguments: '{"month_key":"2026-11"}' } });
  assert.equal(h.kills, 1);
});

test('rejects version drift, wrong model, extra capabilities or a writable thread before submitting ledger data', async () => {
  for (const overrides of [
    { config: { thread: { id: threadId, cliVersion: '0.146.0', ephemeral: true } } },
    { config: { model: 'unrequested-model' } }, { config: { approvalPolicy: 'on-request' } },
    { config: { cwd: '/tmp' } },
    { config: { sandbox: { type: 'workspaceWrite' } } }, { config: { instructionSources: ['/other'] } },
    { mcp: [{ name: 'other' }] }, { threadInventory: [{ name: 'other' }] },
  ]) {
    const h = harness(overrides);
    await assert.rejects(h.run(), /受限 Codex/);
    assert.equal(h.requests.some(r => r.method === 'turn/start'), false);
    assert.equal(h.kills, 1);
  }
});

test('a mid-turn model reroute or unexpected thread settings never yield a successful Terra answer', async () => {
  for (const method of ['model/rerouted', 'thread/settings/updated']) {
    const h = harness({ turn(notice) {
      notice(method, { fromModel: model, toModel: 'different-model', threadSettings: { model: 'different-model' } });
      start(notice, 'final_answer', 'item'); delta(notice, 'item', 'WRONG MODEL'); done(notice);
    } });
    const output = [];
    await assert.rejects(h.run({ onDelta: value => output.push(value) }), /受限 Codex/);
    assert.deepEqual(output, []);
  }
});

test('rejects unexpected tool requests and terminates the process on client abort', async () => {
  const bad = harness({ turn(_, emit) {
    emit({ id: 11, method: 'item/tool/requestUserInput', params: { threadId, turnId } });
  } });
  await assert.rejects(bad.run(), /受限 Codex/);
  const waiting = new EventEmitter(), controller = new AbortController();
  const started = once(waiting, 'start');
  const h = harness({ turn() { waiting.emit('start'); } });
  const answer = h.run({ signal: controller.signal });
  await started;
  controller.abort();
  await assert.rejects(answer, /受限 Codex/);
  assert.ok(h.kills >= 1);
});
