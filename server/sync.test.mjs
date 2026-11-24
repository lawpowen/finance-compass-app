import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash, scryptSync } from 'node:crypto';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { request as httpRequest } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { openStore } from './store.mjs';
import { createSyncServer } from './sync.mjs';

const origin = 'https://finance.example.test';
const password = 'synthetic-test-password';
const username = 'ledger-owner';
const account = {
  id: 'local-cash', name: '测试现金', account_type: 'cash', report_group: 'cash',
  currency: 'MYR', initial_balance: 100, current_balance: 83.5,
};
const fixture = {
  format_version: 3,
  app_version: '0.8.0',
  schema_version: 9,
  transaction_date_semantics: 'occurrence_date',
  exported_at: '2026-11-23T18:43:08.281635',
  meta: { local_profile_id: 'original-local-ledger' },
  accounts: [account],
  categories: [{ id: 'groceries', name: '日用品', type: 'expense' }],
  budgets: [{ id: 'month-budget', category_id: 'groceries', month_key: '2026-11', amount: 90 }],
  transactions: [{
    id: 'first-expense', type: 'expense', account_id: account.id, category_id: 'groceries',
    amount: 16.5, currency: 'MYR', transaction_date: '2026-11-23T00:00:00.000',
    status: 'actual', recurring_rule_id: 'previously-deleted-recurring-rule',
  }],
  asset_snapshots: [{
    id: 'opening-snapshot', account_id: account.id, snapshot_date: '2026-11-01T00:00:00.000',
    market_value: 100, cost_basis: 100, cash_balance: 100, unrealized_pnl: 0,
  }],
  transaction_templates: [{
    id: 'template', name: '周末采购', type: 'expense', account_id: account.id, amount: 16.5,
  }],
  recurring_transaction_rules: [{
    id: 'active-recurring-rule', name: '月度采购', type: 'expense', account_id: account.id,
    amount: 16.5, start_date: '2026-11-23T00:00:00.000', generated_month_keys: ['2026-12'],
  }],
};

async function createHarness(t, store) {
  const server = createSyncServer({ store, origin });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => {
    server.closeAllConnections();
    server.close();
    store.close();
  });
  const url = `http://127.0.0.1:${server.address().port}/api/sync/v1`;
  function request(path, {
    method = 'GET', cookie, body, requestOrigin = origin, clientIp, rawBody,
    accountId = method === 'PUT' ? '1' : null,
  } = {}) {
    const headers = { Origin: requestOrigin };
    if (cookie) headers.Cookie = cookie;
    if (clientIp) headers['X-Finance-Client-IP'] = clientIp;
    if (accountId !== null) headers['X-Finance-Account'] = accountId;
    if (body !== undefined || rawBody !== undefined) headers['Content-Type'] = 'application/json';
    return fetch(url + path, {
      method, headers, body: rawBody ?? (body === undefined ? undefined : JSON.stringify(body)),
    });
  }
  request.oversizedStatus = (cookie) => new Promise((resolve, reject) => {
    const attempt = httpRequest(url + '/ledger', {
      method: 'PUT',
      headers: {
        Origin: origin,
        Cookie: cookie,
        'X-Finance-Account': '1',
        'Content-Type': 'application/json',
        'Content-Length': 16 * 1024 * 1024 + 1,
      },
    }, (response) => {
      response.resume();
      resolve(response.statusCode);
    });
    attempt.on('error', reject);
    // Only send headers, so the server can reject without receiving the body.
    attempt.end();
  });
  return request;
}

async function signIn(request, clientIp) {
  const login = await request('/login', {
    method: 'POST', clientIp, body: { username, password },
  });
  assert.equal(login.status, 204);
  const setCookie = login.headers.get('set-cookie');
  assert.match(setCookie, /^__Host-finance_session=[\w-]+; Max-Age=604800; Path=\/; HttpOnly; Secure; SameSite=Strict$/);
  assert.equal(login.headers.get('cache-control'), 'no-store');
  return setCookie.split(';', 1)[0];
}

test('public health, session authentication, Origin enforcement and credential rotation', async (t) => {
  const store = openStore(':memory:');
  await store.provision(username, password);
  const request = await createHarness(t, store);
  assert.deepEqual(await (await request('/health')).json(), { status: 'ok' });
  assert.equal((await request('/ledger')).status, 401);
  const wrongOrigin = await request('/login', {
    method: 'POST', requestOrigin: 'https://foreign.example.test', body: { username, password },
  });
  assert.equal(wrongOrigin.status, 403);
  assert.equal(wrongOrigin.headers.get('access-control-allow-origin'), null);
  assert.equal((await request('/login', {
    method: 'POST', body: { username, password: 'another-long-password' },
  })).status, 401);
  const cookie = await signIn(request);
  const session = await request('/ledger', { cookie });
  assert.equal(session.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await session.json(), { accountId: '1', username, revision: 0, snapshot: null });
  assert.equal((await request('/logout', {
    method: 'POST', cookie, requestOrigin: 'https://foreign.example.test',
  })).status, 403);
  const logout = await request('/logout', { method: 'POST', cookie });
  assert.equal(logout.status, 204);
  assert.match(logout.headers.get('set-cookie'), /Max-Age=0; Path=\/; HttpOnly; Secure; SameSite=Strict/);
  assert.equal((await request('/ledger', { cookie })).status, 401);
  const activeCookie = await signIn(request);
  await store.provision(username, 'rotated-test-password');
  assert.equal((await request('/ledger', { cookie: activeCookie })).status, 401);
});

test('compatible 0.10.1 ledger sync preserves conflicts and idempotency across sessions and database reopen', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'finance-sync-test-'));
  const filename = join(directory, 'ledger.sqlite3');
  const store = openStore(filename);
  await store.provision(username, password);
  const request = await createHarness(t, store);
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const cookieA = await signIn(request, '192.0.2.1');
  const cookieB = await signIn(request, '192.0.2.2');
  const ledger = (cookie) => request('/ledger', { cookie });
  const write = (cookie, body) => request('/ledger', { method: 'PUT', cookie, body });
  const first = { baseRevision: 0, operationId: 'import-operation-001', snapshot: fixture };
  assert.equal((await write(null, first)).status, 401);
  assert.deepEqual(await (await write(cookieA, first)).json(), { revision: 1 });
  assert.deepEqual(await (await ledger(cookieB)).json(), { accountId: '1', username, revision: 1, snapshot: fixture });
  const revision = await request('/ledger/revision', { cookie: cookieB, accountId: '1' });
  assert.equal(revision.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await revision.json(), { accountId: '1', username, revision: 1 });
  assert.equal((await request('/ledger/revision')).status, 401);
  assert.equal((await request('/ledger/revision', { cookie: cookieB, accountId: '2' })).status, 409);
  assert.deepEqual(await (await write(cookieA, first)).json(), { revision: 1 });
  const choose = (name) => ({ ...fixture, accounts: [{ ...account, name }] });
  const changeA = { baseRevision: 1, operationId: 'concurrent-update-a', snapshot: choose('Device A') };
  const changeB = { baseRevision: 1, operationId: 'concurrent-update-b', snapshot: choose('Device B') };
  const [writeA, writeB] = await Promise.all([write(cookieA, changeA), write(cookieB, changeB)]);
  assert.deepEqual([writeA.status, writeB.status].sort(), [200, 409]);
  const [winner, loser, conflict] = writeA.ok ? [changeA, changeB, writeB] : [changeB, changeA, writeA];
  assert.deepEqual(await conflict.json(), { error: 'revision_conflict', revision: 2 });
  const invalid = { ...winner, snapshot: loser.snapshot };
  assert.deepEqual(await (await write(cookieA, invalid)).json(), { error: 'operation_reused' });
  const reopened = openStore(filename);
  try {
    const token = cookieB.split('=', 2)[1];
    assert.deepEqual(reopened.readLedger(token), { accountId: '1', username, revision: 2, snapshot: winner.snapshot });
    assert.deepEqual(reopened.writeLedger(token, '1', winner), { revision: 2 });
  } finally {
    reopened.close();
  }
});

test('invalid payloads and repeated attempts do not modify a ledger', async (t) => {
  const store = openStore(':memory:');
  await store.provision(username, password);
  const request = await createHarness(t, store);
  const cookie = await signIn(request);
  const write = (body) => request('/ledger', { method: 'PUT', cookie, body });
  const body = { baseRevision: 0, operationId: 'reject-operation-001', snapshot: fixture };
  assert.equal((await request('/ledger', { method: 'PUT', cookie, rawBody: '{broken' })).status, 400);
  assert.equal(await request.oversizedStatus(cookie), 413);
  assert.equal((await write({ ...body, snapshot: { ...fixture, format_version: 99 } })).status, 400);
  assert.equal((await write({
    ...body, snapshot: { ...fixture, transactions: [{ ...fixture.transactions[0], account_id: 'missing' }] },
  })).status, 400);
  assert.equal((await write({ ...body, snapshot: { ...fixture, accounts: [account, account] } })).status, 400);
  assert.equal((await write({ ...body, snapshot: { ...fixture, meta: { value: 42 } } })).status, 400);
  const attempted = () => request('/login', {
    method: 'POST', clientIp: '192.0.2.123', body: { username, password: 'invalid-test-password' },
  });
  // Separate simultaneous expensive hashes from the per-IP attempt limit.
  for (let index = 0; index < 12; index++) assert.equal((await attempted()).status, 401);
  const limited = await attempted();
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get('retry-after'), '600');
  assert.deepEqual(await (await request('/ledger', { cookie })).json(), {
    accountId: '1', username, revision: 0, snapshot: null,
  });
});

test('CLI provisions via stdin and creates a consistent, non-overwriting SQLite backup', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'finance-sync-cli-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const env = { ...process.env, FINANCE_SYNC_DB: join(directory, 'live.sqlite3') };
  const run = (script, args, input) => spawnSync(process.execPath, [
    fileURLToPath(new URL(script, import.meta.url)), ...args,
  ], { env, input, encoding: 'utf8' });
  const provision = run('./provision.mjs', [username], password + '\n');
  assert.equal(provision.status, 0, provision.stderr);
  assert.doesNotMatch(provision.stdout, /synthetic-test-password/);
  const store = openStore(env.FINANCE_SYNC_DB);
  try {
    const { token } = await store.login(username, password);
    assert.ok(token);
    store.writeLedger(token, '1', { baseRevision: 0, operationId: 'backup-fixture-write', snapshot: fixture });
    const output = join(directory, 'backups', 'snapshot.sqlite3');
    const result = run('./backup.mjs', [output]);
    assert.equal(result.status, 0, result.stderr);
    const copy = new DatabaseSync(output, { readOnly: true });
    try {
      const saved = copy.prepare('SELECT revision, snapshot FROM ledger').get();
      assert.equal(saved.revision, 1);
      assert.deepEqual(JSON.parse(saved.snapshot), fixture);
    } finally {
      copy.close();
    }
    assert.equal(run('./backup.mjs', [output]).status, 1);
    assert.deepEqual(store.readLedger(token), { accountId: '1', username, revision: 1, snapshot: fixture });
  } finally {
    store.close();
  }
});

test('public registration creates isolated sessions and ledgers and rejects stale tab credentials', async (t) => {
  const store = openStore(':memory:', { maxAccounts: 2 });
  const request = await createHarness(t, store);
  const register = (name, options = {}) => request('/register', {
    method: 'POST', body: { username: name, password }, ...options,
  });
  assert.equal((await register(username, { requestOrigin: 'https://foreign.example.test' })).status, 403);
  assert.equal((await register('invalid username')).status, 400);

  const registrations = await Promise.all([register(username.toUpperCase()), register(username)]);
  assert.deepEqual(registrations.map((response) => response.status).sort(), [204, 409]);
  const created = registrations.find((response) => response.ok);
  const duplicate = registrations.find((response) => !response.ok);
  assert.deepEqual(await duplicate.json(), { error: 'username_taken' });
  assert.equal(duplicate.headers.get('set-cookie'), null);
  const cookieA = created.headers.get('set-cookie').split(';', 1)[0];

  const secondName = 'second-owner';
  const second = await register(secondName);
  assert.equal(second.status, 204);
  const cookieB = second.headers.get('set-cookie').split(';', 1)[0];
  assert.notEqual(cookieA, cookieB);

  const read = async (cookie, accountId) => request('/ledger', { cookie, accountId });
  const a = await (await read(cookieA)).json();
  const b = await (await read(cookieB)).json();
  assert.equal(a.username.toLowerCase(), username);
  assert.equal(b.username, secondName);
  assert.notEqual(a.accountId, b.accountId);
  assert.equal(a.snapshot, null);
  assert.equal(b.snapshot, null);
  assert.equal(a.revision, 0);
  assert.equal(b.revision, 0);

  const put = (cookie, accountId, body) => request('/ledger', { method: 'PUT', cookie, accountId, body });
  const change = { baseRevision: 0, operationId: 'shared-operation-id', snapshot: fixture };
  for (const [cookie, accountId] of [[cookieB, a.accountId], [cookieA, null]]) {
    const stale = await put(cookie, accountId, change);
    assert.equal(stale.status, 409);
    assert.deepEqual(await stale.json(), { error: 'account_changed' });
  }
  const staleRead = await read(cookieB, a.accountId);
  assert.equal(staleRead.status, 409);
  assert.deepEqual(await staleRead.json(), { error: 'account_changed' });
  const staleLogout = await request('/logout', { method: 'POST', cookie: cookieB, accountId: a.accountId });
  assert.equal(staleLogout.status, 409);
  assert.equal(staleLogout.headers.get('set-cookie'), null);
  const mismatchedRenewal = await request('/login', {
    method: 'POST', accountId: a.accountId, body: { username: secondName, password },
  });
  assert.equal(mismatchedRenewal.status, 409);
  assert.deepEqual(await mismatchedRenewal.json(), { error: 'account_changed' });
  assert.equal(mismatchedRenewal.headers.get('set-cookie'), null);

  assert.deepEqual(await (await put(cookieA, a.accountId, change)).json(), { revision: 1 });
  assert.equal((await (await read(cookieB)).json()).snapshot, null);
  const secondSnapshot = { ...fixture, accounts: [{ ...account, name: 'Private for second owner' }] };
  assert.deepEqual(await (await put(cookieB, b.accountId, {
    ...change, snapshot: secondSnapshot,
  })).json(), { revision: 1 });
  assert.deepEqual((await (await read(cookieA)).json()).snapshot, fixture);
  assert.deepEqual((await (await read(cookieB)).json()).snapshot, secondSnapshot);

  const capacity = await register('third-owner');
  assert.equal(capacity.status, 503);
  assert.deepEqual(await capacity.json(), { error: 'registration_unavailable' });
  const rateLimited = await register('bounded-registration-attempt');
  assert.equal(rateLimited.status, 429);
  assert.deepEqual(await rateLimited.json(), { error: 'too_many_registration_attempts' });
  await store.provision(username, 'new-owner-only-password');
  assert.equal((await read(cookieA)).status, 401);
  assert.equal((await read(cookieB)).status, 200);
});

function createLegacyStore(filename) {
  const legacy = new DatabaseSync(filename);
  legacy.exec(`
    CREATE TABLE account (
      id INTEGER PRIMARY KEY CHECK (id = 1), username TEXT NOT NULL, salt BLOB NOT NULL, digest BLOB NOT NULL
    );
    CREATE TABLE sessions (token_hash TEXT PRIMARY KEY, expires INTEGER NOT NULL) WITHOUT ROWID;
    CREATE TABLE ledger (
      id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL, snapshot TEXT
    );
    INSERT INTO ledger (id, revision) VALUES (1, 0);
    CREATE TABLE operations (
      id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, revision INTEGER NOT NULL
    ) WITHOUT ROWID;
  `);
  return legacy;
}

test('legacy sync store migrates existing credentials, sessions, ledger and operation replay atomically', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'finance-sync-migration-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const filename = join(directory, 'legacy.sqlite3');
  const legacy = createLegacyStore(filename);
  const salt = Buffer.alloc(16, 1);
  const digest = scryptSync(password, salt, 32, { N: 131072, r: 8, p: 1, maxmem: 160 * 1024 * 1024 });
  const token = 'migrated-synthetic-session-token';
  const operationId = 'migrated-operation-id';
  const snapshot = JSON.stringify(fixture);
  const sha256 = (value) => createHash('sha256').update(value).digest('hex');
  legacy.prepare('INSERT INTO account VALUES (1, ?, ?, ?)').run(username, salt, digest);
  legacy.prepare('INSERT INTO sessions VALUES (?, ?)').run(sha256(token), Math.floor(Date.now() / 1000) + 3600);
  legacy.prepare('UPDATE ledger SET revision = 1, snapshot = ? WHERE id = 1').run(snapshot);
  legacy.prepare('INSERT INTO operations VALUES (?, ?, 1)').run(operationId, sha256('0:' + snapshot));
  legacy.close();

  const migrated = openStore(filename);
  try {
    assert.deepEqual(migrated.readLedger(token), { accountId: '1', username, revision: 1, snapshot: fixture });
    assert.deepEqual(migrated.writeLedger(token, '1', { baseRevision: 0, operationId, snapshot: fixture }), {
      revision: 1,
    });
    const loggedIn = await migrated.login(username.toUpperCase(), password);
    assert.ok(loggedIn.token);
    assert.equal(migrated.readLedger(loggedIn.token).revision, 1);
    const registered = await migrated.register('new-after-migration', password);
    assert.deepEqual(migrated.readLedger(registered.token), {
      accountId: '2', username: 'new-after-migration', revision: 0, snapshot: null,
    });
  } finally {
    migrated.close();
  }
  const inspection = new DatabaseSync(filename, { readOnly: true });
  try {
    assert.equal(inspection.prepare('PRAGMA user_version').get().user_version, 1);
    assert.deepEqual(inspection.prepare('PRAGMA foreign_key_check').all(), []);
    assert.equal(inspection.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE name LIKE 'legacy_%'").get().n, 0);
  } finally {
    inspection.close();
  }
});

test('unclaimed legacy store can register its first user and a failed migration preserves original data', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'finance-sync-empty-migration-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const emptyPath = join(directory, 'empty.sqlite3');
  createLegacyStore(emptyPath).close();
  const empty = openStore(emptyPath);
  try {
    const { token } = await empty.register(username, password);
    assert.deepEqual(empty.readLedger(token), { accountId: '1', username, revision: 0, snapshot: null });
  } finally {
    empty.close();
  }

  const invalidPath = join(directory, 'invalid.sqlite3');
  const invalid = createLegacyStore(invalidPath);
  const payload = JSON.stringify(fixture);
  invalid.prepare('UPDATE ledger SET revision = 1, snapshot = ? WHERE id = 1').run(payload);
  invalid.close();
  assert.throws(() => openStore(invalidPath), /no account/);
  const unchanged = new DatabaseSync(invalidPath, { readOnly: true });
  try {
    assert.equal(unchanged.prepare('PRAGMA user_version').get().user_version, 0);
    assert.equal(unchanged.prepare('SELECT snapshot FROM ledger WHERE id=1').get().snapshot, payload);
    assert.equal(unchanged.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE name LIKE 'legacy_%'").get().n, 0);
  } finally {
    unchanged.close();
  }
});
