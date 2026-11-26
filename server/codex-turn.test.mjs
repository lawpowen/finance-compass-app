import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { PassThrough, Writable } from 'node:stream';
import test from 'node:test';
import { runCodexTurn } from '../deploy/sync/codex-turn.mjs';

const model = 'gpt-6.1-terra';
const history = [{ role: 'assistant', content: '过去的对话提及 MYR 99.99' }];
const messages = [
  { role: 'system', content: '只读财务范围' },
  { role: 'user', content: '<user_ledger_data>{"base_currency":"MYR"}</user_ledger_data>' },
  { role: 'user', content: JSON.stringify({ question: '测试账本本月预算', untrustedHistory: history }) },
];
const tool = { type: 'function', function: { name: 'get_monthly_overview', description: '月度预算',
  parameters: { type: 'object', properties: { month_key: { type: 'string' } },
    required: ['month_key'], additionalProperties: false } } };
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
          id: threadId, cliVersion: '0.172.0', ephemeral: true }, approvalPolicy: 'never',
          sandbox: { type: 'readOnly', networkAccess: false }, instructionSources: [], ...config } });
        break;
      case 'turn/start':
        emit({ id: msg.id, result: { turn: { id: turnId } } });
        queueMicrotask(() => turn?.(notice, emit));
    }
    callback();
  } });
  return {
    launch: () => child,
    run: (opts = {}) => runCodexTurn({ model, messages, ...opts }, { cwd, launch: () => child }),
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
  assert.deepEqual(thread.dynamicTools, []);
  assert.deepEqual(JSON.parse(turn.input[0].text), {
    question: '测试账本本月预算', untrustedHistory: history, ledgerSummary: { base_currency: 'MYR' },
    currentQueryResults: [],
  });
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

function finalText(text) {
  return notice => {
    start(notice, 'final_answer', 'f'); delta(notice, 'f', text); finish(notice, 'final_answer', 'f', text);
    done(notice);
  };
}

test('private structured selection dispatches only a declared ledger query, with a server-issued ID', async () => {
  const h = harness({ turn: finalText(JSON.stringify({
    operation: 'get_monthly_overview', arguments: '{"month_key":"2026-11"}',
  })) });
  const result = await h.run({ tools: [tool], onDelta: () => assert.fail('private plan was exposed') });
  assert.equal(result.text, '');
  assert.match(result.toolCall.id, /^[0-9a-f-]{36}$/);
  assert.equal(result.toolCall.name, 'get_monthly_overview');
  assert.equal(result.toolCall.arguments, '{"month_key":"2026-11"}');
  const selection = h.requests.find(r => r.method === 'turn/start').params.outputSchema;
  assert.deepEqual(selection.properties.operation.enum, ['answer', 'get_monthly_overview']);
  assert.deepEqual(h.requests.find(r => r.method === 'thread/start').params.dynamicTools, []);
});

test('a completed ledger query lets Terra stream a normal final answer without showing the selection', async () => {
  const planner = harness({ turn: finalText('{"operation":"answer","arguments":"{}"}') });
  const answer = harness({ turn: finalText('MYR 23.48') });
  const children = [planner, answer], chunks = [];
  const result = await runCodexTurn({ model, messages: [...messages,
    { role: 'assistant', tool_calls: [{ id: 'current-query', function: { name: 'get_monthly_overview', arguments: '{"month_key":"2026-11"}' } }] },
    { role: 'tool', tool_call_id: 'current-query', content: '<user_ledger_data>{"amount":23.48}</user_ledger_data>' }],
    tools: [tool], onDelta: chunk => chunks.push(chunk) }, { cwd, launch: () => children.shift().launch() });
  assert.equal(result.text, 'MYR 23.48');
  assert.deepEqual(chunks, ['MYR 23.48']);
  assert.equal(answer.requests.find(r => r.method === 'turn/start').params.outputSchema, undefined);
  for (const child of [planner, answer]) {
    const input = JSON.parse(child.requests.find(r => r.method === 'turn/start').params.input[0].text);
    assert.deepEqual(input.currentQueryResults, [{ operation: 'get_monthly_overview',
      parameters: {month_key: '2026-11'}, result: { amount: 23.48 } }]);
    assert.deepEqual(input.untrustedHistory, history);
  }
});

test('invalid planner JSON, an undeclared operation, and invalid argument keys never reach a ledger tool', async () => {
  for (const text of ['garbage', '{"operation":"other","arguments":"{}"}',
    '{"operation":"get_monthly_overview","arguments":"{}"}',
    '{"operation":"get_monthly_overview","arguments":"{\\"accountId\\":\\"x\\"}"}']) {
    const h = harness({ turn: finalText(text) });
    await assert.rejects(h.run({ tools: [tool], onDelta: () => assert.fail() }), /受限 Codex/);
  }
});

test('rejects version drift, wrong model, extra capabilities or a writable thread before submitting ledger data', async () => {
  for (const overrides of [
    { config: { thread: { id: threadId, cliVersion: '0.145.0', ephemeral: true } } },
    { config: { model: 'gpt-5.6-terra' } }, { config: { runtimeWorkspaceRoots: ['/unrelated'] } },
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

test('a request for any model other than gpt-6.1-terra is rejected before launching the CLI', async () => {
  for (const other of ['gpt-5.6-terra', 'gpt-6.2-terra', 'latest']) {
    const h = harness();
    await assert.rejects(h.run({ model: other }), /受限 Codex/);
    assert.deepEqual(h.requests, []);
    assert.equal(h.kills, 0);
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
