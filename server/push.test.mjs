import assert from 'node:assert/strict';
import { createECDH, randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { openPushService, validPushEndpoint } from './push.mjs';
import { reminderEvents } from './reminder-events.mjs';
import { openStore } from './store.mjs';
import { createSyncServer } from './sync.mjs';

const origin = 'https://finance.example.test';
const password = 'synthetic-example-password';
const browser = 'https://fcm.googleapis.com/fcm/send/browser-A:opaque-token';

function subscription(endpoint = browser, timezone = 'Asia/Kuala_Lumpur') {
  return {
    timezone,
    subscription: {
      endpoint,
      keys: {
        p256dh: createECDH('prime256v1').generateKeys().toString('base64url'),
        auth: randomBytes(16).toString('base64url'),
      },
    },
  };
}

function setup(t, options) {
  const directory = mkdtempSync(join(tmpdir(), 'finance-compass-push-'));
  const filename = join(directory, 'ledger.sqlite3');
  const store = openStore(filename);
  const push = openPushService({ filename, subject: origin, reminderEvents, ...options });
  t.after(async () => {
    await push.close();
    store.close();
    rmSync(directory, { recursive: true, force: true });
  });
  return { filename, store, push };
}

test('push endpoint validation allows approved vendor routes and rejects arbitrary routing', () => {
  for (const value of [
    browser,
    'https://updates.push.services.mozilla.com/wpush/v2/opaque_token',
    'https://web.push.apple.com/opaque_endpoint_token_12345',
    'https://bn1.notify.windows.com/w/?token=opaque%2Ftoken%3D',
  ]) assert.equal(validPushEndpoint(value), true, value);
  for (const value of [
    'http://fcm.googleapis.com/fcm/send/test',
    'https://127.0.0.1/fcm/send/test',
    'https://169.254.169.254/latest/meta-data',
    'https://fcm.googleapis.com.example.test/fcm/send/test',
    'https://x:fcm.googleapis.com@localhost/fcm/send/test',
    'https://user@fcm.googleapis.com/fcm/send/test',
    'https://fcm.googleapis.com:8080/fcm/send/test',
    'https://fcm.googleapis.com/fcm/send/test?redirect=https://example.test',
    'https://fcm.googleapis.com/fcm/send/..%2F..%2Foauth2',
    'https://fcm.googleapis.com/fcm/send/../oauth2',
    'https://fcm.googleapis.com/fcm/send/test#fragment',
    'https://bn1.notify.windows.com/w/?token=test&redirect=https://example.test',
  ]) assert.equal(validPushEndpoint(value), false, value);
});

test('push API binds the session, origin and delivery to a single account and device', async (t) => {
  const calls = [];
  const { store, push } = setup(t, {
    transport: async (...args) => { calls.push(args); },
  });
  const { token: tokenA } = await store.register('owner-a', password);
  const { token: tokenB } = await store.register('owner-b', password);
  const server = createSyncServer({ origin, store, push });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });

  function request(path, { method = 'GET', accountId = '1', token = tokenA, data, from = origin } = {}) {
    const headers = { Origin: from };
    if (token) headers.Cookie = `__Host-finance_session=${token}`;
    if (accountId) headers['X-Finance-Account'] = accountId;
    if (data) headers['Content-Type'] = 'application/json';
    return fetch(`http://127.0.0.1:${server.address().port}/api/sync/v1/push/${path}`, {
      method, headers, body: data ? JSON.stringify(data) : undefined,
    });
  }

  assert.equal((await request('config', { token: null })).status, 401);
  assert.equal((await request('config', { accountId: null })).status, 409);
  const config = await request('config');
  assert.equal(config.status, 200);
  assert.equal(config.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await config.json(), { publicKey: push.publicKey });

  const valid = subscription();
  assert.equal((await request('subscription', {
    method: 'PUT', data: valid, from: 'https://foreign.example.test',
  })).status, 403);
  assert.equal((await request('subscription', {
    method: 'PUT', accountId: '2', data: valid,
  })).status, 409);
  assert.equal((await request('subscription', {
    method: 'PUT', data: subscription(browser, 'Mars/Base'),
  })).status, 400);
  assert.equal((await request('subscription', {
    method: 'PUT', data: subscription('https://localhost/push'),
  })).status, 400);
  assert.equal((await request('subscription', { method: 'PUT', data: valid })).status, 204);
  assert.equal((await request('subscription', {
    method: 'PUT', token: tokenB, accountId: '2', data: valid,
  })).status, 409);

  for (const [path, method] of [['test', 'POST'], ['subscription', 'DELETE']]) {
    assert.equal((await request(path, {
      method, token: tokenB, accountId: '2', data: { endpoint: browser },
    })).status, 404);
  }
  assert.equal(calls.length, 0);
  assert.equal((await request('test', { method: 'POST', data: { endpoint: browser } })).status, 204);
  assert.equal((await request('test', { method: 'POST', data: { endpoint: browser } })).status, 429);
  assert.deepEqual(calls[0][0], valid.subscription);
  assert.equal((await request('subscription', {
    method: 'DELETE', data: { endpoint: browser },
  })).status, 204);
  assert.equal((await request('test', { method: 'POST', data: { endpoint: browser } })).status, 404);
  assert.equal(calls.length, 1);
});

test('real ledger schedule uses local 09:00, retries a transient error, and persists delivery claims', async (t) => {
  let now = Date.parse('2026-11-23T00:59:00Z');
  const browserB = 'https://fcm.googleapis.com/fcm/send/browser-B:opaque-token';
  const calls = [];
  let scheduleCalculations = 0;
  const transport = async (target, payload, options) => {
    calls.push({ endpoint: target.endpoint, payload, options });
    const failure = target.endpoint === browserB ? 410 : calls.length === 1 ? 503 : null;
    if (failure) throw Object.assign(new Error('fixture failure'), { statusCode: failure });
  };
  const { filename, store, push } = setup(t, {
    clock: () => now,
    transport,
    reminderEvents(ledger, day) {
      scheduleCalculations += 1;
      return reminderEvents(ledger, day);
    },
  });
  const { token } = await store.register('loan-owner', password);
  const snapshot = {
    meta: {},
    accounts: [{
      id: 'my-loan', name: '车贷', account_type: 'loan', is_active: true,
      loan_payment_day: 23, loan_start_date: '2026-10-01',
      loan_term_months: 12, loan_principal: 1200, loan_annual_interest_rate: 0,
      loan_repayment_method: 'equalPrincipal', initial_balance: -1200, current_balance: -1200,
    }],
    transactions: [],
  };
  assert.deepEqual(store.writeLedger(token, '1', { snapshot, baseRevision: 0, operationId: 'fixture-update-1' }), {
    revision: 1,
  });
  assert.deepEqual(push.subscribe('1', subscription()), {});
  assert.deepEqual(push.subscribe('1', subscription(browserB)), {});

  await push.runDue();
  assert.equal(calls.length, 0);
  now = Date.parse('2026-11-23T01:00:00Z');
  await Promise.all([push.runDue(), push.runDue()]);
  assert.deepEqual(calls.map(({ endpoint }) => endpoint).sort(), [browser, browserB]);
  assert.match(calls[0].payload.body, /车贷/);
  assert.deepEqual(await push.test('1', browserB), { status: 404, error: 'push_subscription_not_found' });
  now = Date.parse('2026-11-23T01:04:00Z');
  await push.runDue();
  assert.equal(calls.length, 2);
  now = Date.parse('2026-11-23T01:05:00Z');
  await push.runDue();
  assert.deepEqual(calls[2], calls[0]);
  assert.equal(scheduleCalculations, 1);
  assert.deepEqual(store.writeLedger(token, '1', {
    snapshot: { ...snapshot, meta: { notifications_enabled: 'false' } },
    baseRevision: 1,
    operationId: 'fixture-update-2',
  }), { revision: 2 });
  await push.runDue();
  assert.equal(scheduleCalculations, 2);
  assert.equal(calls.length, 3);

  const restarted = openPushService({ filename, subject: origin, reminderEvents, clock: () => now, transport });
  try {
    assert.equal(restarted.publicKey, push.publicKey);
    await restarted.runDue();
    assert.equal(calls.length, 3);
  } finally {
    await restarted.close();
  }
});
