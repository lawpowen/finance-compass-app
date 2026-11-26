import { createServer } from 'node:http';
import { once } from 'node:events';
import { isIP } from 'node:net';
import { pathToFileURL } from 'node:url';
import { databasePath, openStore, passwordValid, sessionLifetime, usernameValid } from './store.mjs';
import { openPushService } from './push.mjs';
import { reminderEvents } from './reminder-events.mjs';
import { validSnapshot } from './snapshot.mjs';
import { createAiProvider } from './ai-provider.mjs';
import { runAiChat, validateChatBody } from './ai-chat.mjs';

const api = '/api/sync/v1';
const sessionCookie = '__Host-finance_session';
const maxLedgerBytes = 16 * 1024 * 1024;
const operationIdPattern = /^[a-zA-Z0-9_-]{16,128}$/;
const cookieDirectives = 'Path=/; HttpOnly; Secure; SameSite=Strict';
const utf8 = new TextDecoder('utf-8', { fatal: true });

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

function send(response, status, body) {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.statusCode = status;
  if (body === undefined) return response.end();
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  return response.end(JSON.stringify(body));
}

async function jsonBody(request, maxBytes) {
  const contentType = request.headers['content-type']?.split(';', 1)[0].trim().toLowerCase();
  if (contentType !== 'application/json') throw new HttpError(415, 'json_required');
  if (Number(request.headers['content-length']) > maxBytes) {
    throw new HttpError(413, 'payload_too_large');
  }
  const chunks = [];
  let bytes = 0;
  // Preserve the connection long enough to report HTTP 413 if a chunked body
  // reaches the bound. The caller then returns Connection: close.
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    bytes += chunk.length;
    if (bytes > maxBytes) throw new HttpError(413, 'payload_too_large');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(utf8.decode(Buffer.concat(chunks, bytes)));
  } catch {
    throw new HttpError(400, 'invalid_json');
  }
}

function getSession(request) {
  for (const cookie of (request.headers.cookie || '').split(';')) {
    const [name, token] = cookie.trim().split('=');
    if (name === sessionCookie && /^[\w-]{43}$/.test(token ?? '')) return token;
  }
  return null;
}

function clientAddress(request) {
  const forwarded = request.headers['x-finance-client-ip'];
  return typeof forwarded === 'string' && isIP(forwarded) ? forwarded : request.socket.remoteAddress;
}

function authLimits() {
  let active = 0;
  const minute = 60 * 1000;
  const window = 10 * minute;

  function limiter({ perMinute, perIp, error, clearOnSuccess = false }) {
    let interval = 0;
    let total = 0;
    const attemptsByIp = new Map();
    return async (request, verify) => {
      const client = clientAddress(request);
      const now = Date.now();
      if (now >= interval) {
        interval = now + minute;
        total = 0;
        for (const [ip, attempts] of attemptsByIp) {
          if (attempts.until <= now) attemptsByIp.delete(ip);
        }
      }
      const entry = attemptsByIp.get(client);
      const attempts = entry && entry.until > now ? entry : { count: 0, until: now + window };
      if (active >= 2 || total >= perMinute || attempts.count >= perIp) {
        throw new HttpError(429, error);
      }
      total += 1;
      active += 1;
      attempts.count += 1;
      attemptsByIp.set(client, attempts);
      try {
        const result = await verify();
        if (clearOnSuccess && result.token) attemptsByIp.delete(client);
        return result;
      } finally {
        active -= 1;
      }
    };
  }

  return {
    login: limiter({ perMinute: 48, perIp: 12, error: 'too_many_login_attempts', clearOnSuccess: true }),
    register: limiter({ perMinute: 12, perIp: 4, error: 'too_many_registration_attempts' }),
  };
}

function setSessionCookie(response, token) {
  response.setHeader('Set-Cookie', `${sessionCookie}=${token}; Max-Age=${sessionLifetime}; ${cookieDirectives}`);
}

function aiAdmission() {
  const active = new Set();
  const attempts = new Map();
  const windowMs = 600_000;
  let nextSweep = 0;
  return (account, ip) => {
    const now = Date.now();
    const cutoff = now - windowMs;
    if (now >= nextSweep) {
      nextSweep = now + 60_000;
      for (const [key, times] of attempts) {
        if (times.at(-1) <= cutoff) attempts.delete(key);
      }
    }
    if (active.has(account)) throw new HttpError(429, 'ai_chat_active');
    const keys = ['account:' + account, 'ip:' + ip];
    const recent = keys.map((key) => (attempts.get(key) ?? []).filter((time) => time > cutoff));
    if (recent.some((times) => times.length >= 20)) throw new HttpError(429, 'ai_rate_limited');
    keys.forEach((key, i) => attempts.set(key, [...recent[i], now]));
    active.add(account);
    return () => active.delete(account);
  };
}

async function streamChat(request, response, { provider, input, readLedger, authorize }) {
  const controller = new AbortController();
  const { signal } = controller;
  const deadline = () => controller.abort(new Error('ai_timeout'));
  const disconnected = () => controller.abort(new Error('client_disconnected'));
  const closedRequest = () => { if (!request.complete) disconnected(); };
  const timer = setTimeout(deadline, 120_000).unref();
  request.once('aborted', disconnected);
  request.once('close', closedRequest);
  response.once('close', disconnected);
  response.setTimeout(120_000, deadline);
  const frame = (type, data) => 'event: ' + type + '\ndata: ' + JSON.stringify(data) + '\n\n';
  try {
    if (response.destroyed) return;
    response.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'X-Accel-Buffering': 'no',
    });
    response.flushHeaders();
    let nextAuthCheck = 0;
    const emit = async (type, data) => {
      signal.throwIfAborted();
      if (type !== 'delta' || Date.now() >= nextAuthCheck) {
        authorize();
        nextAuthCheck = Date.now() + 1_000;
      }
      if (!response.write(frame(type, data))) await once(response, 'drain', { signal });
    };
    // The response owns the lifetime of the stream. A normally consumed POST
    // body also fires request.close, often before the first model token.
    await Promise.race([
      once(signal, 'abort').then(() => { throw signal.reason; }),
      runAiChat({ provider, input, readLedger, emit, signal }),
    ]);
  } catch (error) {
    if (!response.destroyed && response.headersSent && !response.writableEnded) {
      const expired = error instanceof HttpError && [401, 409].includes(error.status);
      const timeout = signal.reason?.message === 'ai_timeout';
      const code = expired ? error.message : timeout ? 'ai_timeout' : 'ai_unavailable';
      const message = expired ? '登录状态已变更，请重新打开账本。'
        : timeout ? '回答超时，请缩小问题范围后重试。' : '理财助手暂时无法完成回答，请稍后重试。';
      response.write(frame('error', { code, message }));
    }
  } finally {
    controller.abort();
    clearTimeout(timer);
    response.setTimeout(0);
    response.off('timeout', deadline);
    request.off('aborted', disconnected);
    request.off('close', closedRequest);
    response.off('close', disconnected);
    if (!response.destroyed && !response.writableEnded) response.end();
  }
}

export function createSyncServer({ store, origin, push, aiProvider = null, allowLoopbackOrigin = false, onError = () => {} }) {
  const publicUrl = new URL(origin);
  const localTest = allowLoopbackOrigin && publicUrl.protocol === 'http:' &&
    ['localhost', '127.0.0.1', '[::1]'].includes(publicUrl.hostname);
  if ((!localTest && publicUrl.protocol !== 'https:') || publicUrl.origin !== origin) {
    throw new Error('FINANCE_SYNC_ORIGIN must be an exact HTTPS origin without a trailing slash.');
  }
  const limit = authLimits();
  const admitChat = aiAdmission();

  function authorizeAccount(request) {
    const accountId = request.headers['x-finance-account'];
    const result = store.authorize(getSession(request), accountId);
    if (result.error) throw new HttpError(result.error === 'account_changed' ? 409 : 401, result.error);
    return accountId;
  }

  function ledgerResponse(request, response, read) {
    const ledger = read(getSession(request), request.headers['x-finance-account']);
    if (ledger.error) throw new HttpError(ledger.error === 'account_changed' ? 409 : 401, ledger.error);
    send(response, 200, ledger);
  }

  function pushRoute(action) {
    return async (request, response) => {
      authorizeAccount(request);
      if (!push) throw new HttpError(503, 'push_unavailable');
      const payload = request.method === 'GET' ? undefined : await jsonBody(request, 8192);
      const accountId = authorizeAccount(request);
      const result = await action(accountId, payload);
      if (result.error) throw new HttpError(result.status, result.error);
      send(response, result.body === undefined ? 204 : 200, result.body);
    };
  }

  const handlers = {
    [`GET ${api}/ai/status`](request, response) {
      authorizeAccount(request);
      if (request.url.includes('?')) throw new HttpError(400, 'invalid_ai_request');
      send(response, 200, aiProvider ? { enabled: true, streaming: true, provider: aiProvider.name === 'codex_terra' ? 'codex_terra' : 'openai_compatible' } : { enabled: false });
    },
    async [`POST ${api}/ai/chat`](request, response) {
      const accountId = authorizeAccount(request);
      if (request.url.includes('?')) throw new HttpError(400, 'invalid_ai_request');
      if (!aiProvider) throw new HttpError(503, 'ai_unavailable');
      const raw = await jsonBody(request, 32 * 1024);
      authorizeAccount(request);
      let input;
      try {
        input = validateChatBody(raw);
      } catch {
        throw new HttpError(400, 'invalid_ai_request');
      }
      const release = admitChat(accountId, clientAddress(request));
      try {
        await streamChat(request, response, {
          provider: aiProvider, input, authorize: () => authorizeAccount(request),
          readLedger: () => {
            const ledger = store.readLedger(getSession(request), accountId);
            if (ledger.error) throw new HttpError(ledger.error === 'account_changed' ? 409 : 401, ledger.error);
            return ledger;
          },
        });
      } finally {
        release();
      }
    },
    [`GET ${api}/health`]: (_request, response) => send(response, 200, { status: 'ok' }),
    async [`POST ${api}/register`](request, response) {
      const credentials = await jsonBody(request, 4096);
      if (!usernameValid(credentials?.username) || !passwordValid(credentials?.password)) {
        throw new HttpError(400, 'invalid_credentials');
      }
      const result = await limit.register(request, () => store.register(credentials.username, credentials.password));
      if (result.error === 'username_taken') throw new HttpError(409, result.error);
      if (result.error) throw new HttpError(503, result.error);
      setSessionCookie(response, result.token);
      send(response, 204);
    },
    async [`POST ${api}/login`](request, response) {
      const credentials = await jsonBody(request, 4096);
      if (!usernameValid(credentials?.username) || !passwordValid(credentials?.password)) {
        throw new HttpError(401, 'invalid_credentials');
      }
      const result = await limit.login(request, () => store.login(
        credentials.username, credentials.password, request.headers['x-finance-account'],
      ));
      if (result.error) throw new HttpError(result.error === 'account_changed' ? 409 : 401, result.error);
      setSessionCookie(response, result.token);
      send(response, 204);
    },
    [`POST ${api}/logout`](request, response) {
      const result = store.logout(getSession(request), request.headers['x-finance-account']);
      if (result.error) throw new HttpError(409, result.error);
      response.setHeader('Set-Cookie', `${sessionCookie}=; Max-Age=0; ${cookieDirectives}`);
      send(response, 204);
    },
    [`GET ${api}/ledger`]: (request, response) => ledgerResponse(request, response, store.readLedger),
    [`GET ${api}/ledger/revision`]: (request, response) => ledgerResponse(request, response, store.readLedgerRevision),
    async [`PUT ${api}/ledger`](request, response) {
      const token = getSession(request);
      const expectedAccountId = authorizeAccount(request);
      const update = await jsonBody(request, maxLedgerBytes);
      if (!Number.isSafeInteger(update?.baseRevision) || update.baseRevision < 0 ||
          update.baseRevision >= Number.MAX_SAFE_INTEGER || typeof update.operationId !== 'string' ||
          !operationIdPattern.test(update.operationId) || !validSnapshot(update.snapshot)) {
        throw new HttpError(400, 'invalid_ledger');
      }
      const result = store.writeLedger(token, expectedAccountId, update);
      const status = result.error === 'unauthorized' ? 401 : result.error ? 409 : 200;
      send(response, status, result);
    },
    [`GET ${api}/push/config`]: pushRoute(() => ({ body: { publicKey: push.publicKey } })),
    [`PUT ${api}/push/subscription`]: pushRoute((accountId, payload) => push.subscribe(accountId, payload)),
    [`PATCH ${api}/push/subscription`]: pushRoute((accountId, payload) => push.updateTimezone(accountId, payload)),
    [`DELETE ${api}/push/subscription`]: pushRoute((accountId, payload) => push.unsubscribe(accountId, payload?.endpoint)),
    [`POST ${api}/push/test`]: pushRoute((accountId, payload) => push.test(accountId, payload?.endpoint)),
    [`POST ${api}/push/verify-delivery`]: pushRoute((accountId, payload) => push.verifyDelivery(accountId, payload?.endpoint)),
  };

  return createServer({ requestTimeout: 30_000, headersTimeout: 10_000 }, async (request, response) => {
    try {
      const path = request.url?.split('?', 1)[0];
      const handler = handlers[`${request.method} ${path}`];
      if (!handler) throw new HttpError(404, 'not_found');
      if (request.method !== 'GET' && request.headers.origin !== origin) {
        throw new HttpError(403, 'origin_rejected');
      }
      await handler(request, response);
    } catch (error) {
      if (request.socket.destroyed || response.writableEnded) return;
      if (error instanceof HttpError) {
        if (!request.complete) response.setHeader('Connection', 'close');
        if (error.status === 429) response.setHeader('Retry-After', error.code === 'ai_chat_active' ? '1' : '600');
        send(response, error.status, { error: error.message });
        return;
      }
      onError(error);
      send(response, 500, { error: 'internal_error' });
    }
  });
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  process.umask(0o077);
  const filename = databasePath();
  const store = openStore(filename);
  const origin = process.env.FINANCE_SYNC_ORIGIN;
  const push = openPushService({
    filename,
    subject: process.env.FINANCE_PUSH_SUBJECT ?? origin,
    reminderEvents,
    onError: (code, status) => console.error('Finance push failed:', code, Number.isInteger(status) ? status : ''),
  });
  const server = createSyncServer({
    store,
    origin,
    push,
    aiProvider: createAiProvider(),
    allowLoopbackOrigin: process.env.FINANCE_SYNC_ALLOW_INSECURE_LOOPBACK === '1',
    onError: (error) => console.error('Finance sync request failed:', error.code || error.name),
  });
  const port = Number(process.env.PORT || 8081);
  const host = process.env.HOST || '0.0.0.0';
  function runPush() {
    push.runDue().catch(() => console.error('Finance push schedule failed.'));
  }
  const pushTimer = setInterval(runPush, 60_000).unref();
  server.listen(port, host, () => {
    console.info('Finance sync listening on port', port);
    runPush();
  });
  let stopping = false;
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => {
      if (stopping) return;
      stopping = true;
      clearInterval(pushTimer);
      server.close(async () => {
        try {
          await push.close();
        } catch {
          console.error('Finance push shutdown failed.');
        } finally {
          store.close();
        }
      });
    });
  }
}
