// Operator-invoked acceptance test. Uses a fresh in-memory sync service and a
// synthetic ledger; the only external connection is the configured Finance socket.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { createAiProvider } from '../server/ai-provider.mjs';
import { openStore } from '../server/store.mjs';
import { createSyncServer } from '../server/sync.mjs';

const provider = createAiProvider();
assert.equal(provider?.name, 'codex_terra', 'A configured Finance Codex/Terra socket is required');
assert.equal(process.env.FINANCE_AI_MODEL, 'gpt-6.1-terra');
const store = openStore(':memory:');
const origin = 'https://finance-acceptance.example.test';
const server = createSyncServer({ store, origin, aiProvider: provider });
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const base = 'http://127.0.0.1:' + server.address().port + '/api/sync/v1';
const headers = { Origin: origin, 'Content-Type': 'application/json' };
const post = (path, body, method = 'POST') => fetch(base + path, { method, headers, body: JSON.stringify(body) });

try {
  const registered = await post('/register', { username: 'finance-acceptance', password: randomBytes(24).toString('hex') });
  assert.equal(registered.status, 204);
  headers.Cookie = registered.headers.get('set-cookie').split(';', 1)[0];
  headers['X-Finance-Account'] = '1';
  assert.equal((await (await fetch(base + '/ai/status', { headers })).json()).provider, 'codex_terra');

  const expense = (id, date, merchant, amount) => ({
    id, type: 'expense', amount, currency: 'MYR', account_id: 'cash',
    merchant, status: 'actual', transaction_date: date + 'T12:00:00',
  });
  const transactions = [
    expense('jan-1', '2026-01-08', '青禾测试厨房', 31.47),
    expense('jan-2', '2026-01-19', '青禾测试厨房', 18.26),
    ...Array.from({ length: 32 }, (_, i) => expense('other-' + i, '2026-05-15', '另一家测试店', 1)),
  ];
  const snapshot = {
    format_version: 3, schema_version: 9, app_version: '0.10.1+45', meta: {},
    accounts: [{ id: 'cash', name: '测试现金', account_type: 'cash', report_group: 'cash',
      currency: 'MYR', initial_balance: 100, current_balance: 18.27 }],
    transactions, categories: [], budgets: [], asset_snapshots: [], transaction_templates: [],
    recurring_transaction_rules: [],
  };
  const write = await post('/ledger', { baseRevision: 0, operationId: 'finance-acceptance-0001', snapshot }, 'PUT');
  assert.equal(write.status, 200);
  const started = performance.now();
  const stream = await post('/ai/chat', { timezone: 'Asia/Kuala_Lumpur',
    message: '请用流水检索工具核对 2026 年 1 月商户“青禾测试厨房”的实际支出，共几笔、合计多少马币？用两句话说明。' });
  assert.equal(stream.status, 200);
  assert.match(stream.headers.get('content-type'), /^text\/event-stream/);
  let answer = '', pending = '', done, deltaCount = 0, firstMs, lastMs;
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for await (const bytes of stream.body) {
    pending += decoder.decode(bytes, { stream: true });
    let boundary;
    while ((boundary = pending.indexOf('\n\n')) >= 0) {
      const event = pending.slice(0, boundary);
      pending = pending.slice(boundary + 2);
      const type = /^event: (\w+)$/m.exec(event)?.[1];
      const data = JSON.parse(/^data: (.+)$/m.exec(event)[1]);
      assert.notEqual(type, 'refused', 'The finance question was refused');
      assert.notEqual(type, 'error', 'The stream failed (' + (data.code ?? 'unknown') + ')');
      if (type === 'delta' && data.text) {
        lastMs = Math.round(performance.now() - started);
        firstMs ??= lastMs;
        deltaCount++;
        answer += data.text;
      }
      if (type === 'done') done = data;
    }
  }
  assert.equal(done?.revision, 1);
  assert.ok(done.toolsUsed.includes('search_transactions'), 'The main model must query the synthetic ledger');
  assert.match(answer, /49\.73/);
  assert.match(answer, /[2两二]\s*笔/);
  assert.ok(deltaCount > 1 && lastMs > firstMs, 'Expected incremental model output before completion');
  console.log(JSON.stringify({ provider: provider.name, model: process.env.FINANCE_AI_MODEL,
    revision: done.revision, toolsUsed: done.toolsUsed, verifiedExpenses: 2, verifiedTotalMYR: 49.73,
    deltaCount, firstMs, lastMs, durationMs: Math.round(performance.now() - started) }));
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  store.close();
}
