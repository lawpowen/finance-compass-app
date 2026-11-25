import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const browserCode = readFileSync(new URL('../web/pwa_bootstrap.js', import.meta.url), 'utf8');
const workerCode = readFileSync(new URL('../web/service-worker.js', import.meta.url), 'utf8');
const endpoint = 'https://example.invalid/device';

function page() {
  const state = { timezone: 'Asia/Kuala_Lumpur', offline: false, refuseUnsubscribe: false, signedIn: '1' };
  let record = JSON.stringify({ accountId: '1', endpoint, confirmed: true, timezone: state.timezone });
  const calls = [];
  const closed = [];
  const subscription = {
    endpoint, unsubscribe: async () => {
      if (state.refuseUnsubscribe) throw new Error('provider unavailable');
      state.subscription = null;
      return true;
    },
  };
  state.subscription = subscription;
  const registration = {
    pushManager: { getSubscription: async () => state.subscription },
    getNotifications: async () => ['1', '2'].map(id => ({ data: { accountId: id }, close: () => closed.push(id) })),
  };
  const serviceWorker = { ready: Promise.resolve(registration), getRegistration: async () => registration,
    addEventListener() {} };
  const window = { isSecureContext: true, PushManager: {}, Notification: { permission: 'granted' }, addEventListener() {} };
  const context = {
    window, navigator: { serviceWorker }, document: { readyState: 'loading' }, Notification: window.Notification,
    Intl: { DateTimeFormat: () => ({ resolvedOptions: () => ({ timeZone: state.timezone }) }) },
    localStorage: { getItem: () => record, setItem: (_, value) => { record = value; }, removeItem: () => { record = null; } },
    AbortSignal,
    fetch: async (path, init) => {
      if (path.endsWith('/revision')) {
        return { ok: !state.offline && init.headers['X-Finance-Account'] === state.signedIn,
          json: async () => ({ accountId: state.signedIn }) };
      }
      calls.push({ method: init.method, owner: init.headers['X-Finance-Account'], ...JSON.parse(init.body) });
      if (state.offline) throw new Error('offline');
      return { status: 204 };
    },
  };
  runInNewContext(browserCode, context);
  return { state, calls, closed, bridge: window.FinanceCompassPush, device: () => JSON.parse(record) };
}

test('browser timezone is registered only after a change and retries after reconnect', async () => {
  const { state, calls, bridge, device } = page();
  await bridge.reconcile('1');
  assert.equal(calls.length, 0);
  state.timezone = 'America/New_York';
  state.offline = true;
  await assert.rejects(bridge.refreshTimezone('1'), /offline/);
  assert.equal(device().timezone, 'Asia/Kuala_Lumpur');
  state.offline = false;
  await Promise.all([bridge.refreshTimezone('1'), bridge.refreshTimezone('1')]);
  await bridge.inspect('1');
  await bridge.refreshTimezone('2');
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1], { method: 'PATCH', owner: '1', endpoint, timezone: 'America/New_York' });
  assert.equal(device().timezone, 'America/New_York');
});

test('provider unsubscribe failure cannot prevent server revocation or transfer ownership', async () => {
  const { state, calls, closed, bridge, device } = page();
  state.refuseUnsubscribe = true;
  await bridge.unsubscribe('1');
  assert.deepEqual(calls, [{ method: 'DELETE', owner: '1', endpoint }]);
  assert.deepEqual(closed, ['1']);
  assert.equal(device().confirmed, false);
  state.signedIn = '2';
  await assert.rejects(bridge.reconcile('2'), /provider unavailable/);
  assert.equal(JSON.parse(await bridge.inspect('2')).enabled, false);
  assert.equal(device().accountId, '1');
});

test('a stale tab cannot detach another signed-in account on resume', async () => {
  const { state, bridge, device } = page();
  await bridge.reconcile('2');
  assert.equal(device().accountId, '1');
  assert.equal(state.subscription.endpoint, endpoint);
  state.signedIn = '2';
  await bridge.reconcile('2');
  assert.equal(device(), null);
  assert.equal(state.subscription, null);
});

test('a verified account switch closes old displayed details even when removal is offline', async () => {
  const { state, closed, bridge } = page();
  state.signedIn = '2';
  state.offline = true;
  await bridge.reconcile('2', true);
  assert.deepEqual(closed, ['1']);
});

test('worker displays private notification text only for a verified session and endpoint', async () => {
  const handlers = {};
  const shown = [];
  const checks = [];
  let verify = async () => ({ status: 204 });
  const scope = 'https://finance.example.test/';
  const self = {
    addEventListener: (type, handler) => { handlers[type] = handler; },
    registration: { scope, pushManager: { getSubscription: async () => ({ endpoint }) },
      showNotification: async (title, options) => shown.push({ title, ...options }) },
  };
  runInNewContext(workerCode, { self, URL, fetch: async (url, init) => {
    checks.push({ url: url.href, method: init.method, owner: init.headers['X-Finance-Account'],
      credentials: init.credentials, endpoint: JSON.parse(init.body).endpoint });
    return verify();
  } });
  const payload = { accountId: '1', notification: { title: 'Test statement', body: 'Private account name', tag: 'card-today' } };
  function deliver(data = payload) {
    let done;
    handlers.push({ data: { json: () => data }, waitUntil: (promise) => { done = promise; } });
    return done;
  }
  await deliver();
  assert.deepEqual(checks[0], { url: scope + 'api/sync/v1/push/verify-delivery', method: 'POST',
    owner: '1', credentials: 'same-origin', endpoint });
  assert.equal(shown[0].body, 'Private account name');
  assert.equal(shown[0].data.accountId, '1');
  for (const status of [401, 404, 409]) {
    verify = async () => ({ status });
    await deliver();
  }
  verify = async () => { throw new Error('offline'); };
  await deliver();
  await deliver({ title: 'Legacy payload', body: 'Private text' });
  let respond;
  let requestStarted;
  const requested = new Promise(resolve => { requestStarted = resolve; });
  verify = () => { requestStarted(); return new Promise(resolve => { respond = resolve; }); };
  const stale = deliver();
  await requested;
  handlers.message({ source: { type: 'window', url: scope }, data: { type: 'finance-compass-push-transition' } });
  respond({ status: 204 });
  await stale;
  assert.equal(shown.length, 1);
});
