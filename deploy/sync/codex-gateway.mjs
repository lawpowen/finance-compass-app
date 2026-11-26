import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { chmod, lstat, mkdir, unlink } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createConnection } from 'node:net';
import { dirname, isAbsolute } from 'node:path';

// The private bridge accepts only prompts and schemas produced by this release
// of Finance. The integration test builds requests with the actual chat module.
const gateDigest = '89aa84d8dbd09b054d61d54e21a1d36c378a4f235920a99583f7d4c808baea90';
const answerDigest = '977585dafb7ba9af374f895c13ad755ab5c06de0d7ba49e7411fd0973a66ee3e';
const toolsDigest = '4e574e1fd9099bebc5d4310d621465c48d89379519e22078d1c8d3bcae38f119';
const financeTools = new Set(['get_monthly_overview', 'get_category_breakdown', 'search_transactions',
  'get_credit_card_statements', 'get_loan_and_goals_status']);
const maxRequestBytes = 512 * 1024;
const digest = text => createHash('sha256').update(text).digest('hex');
const requestError = status => Object.assign(new Error('Invalid Finance request'), { status });
const string = (value, limit) => typeof value === 'string' && value.length > 0 && value.length <= limit;
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const only = (value, keys) => object(value) && Object.keys(value).every(key => keys.includes(key));

function validToolCall(call) {
  return only(call, ['type', 'id', 'function']) && call.type === 'function' &&
    typeof call.id === 'string' && /^[\w-]{1,128}$/.test(call.id) &&
    only(call.function, ['name', 'arguments']) && financeTools.has(call.function.name) &&
    string(call.function.arguments, 4096);
}

function envelope(content) {
  return string(content, 48 * 1024) && content.startsWith('<user_ledger_data>') &&
    content.endsWith('</user_ledger_data>');
}

function userMessage(item) {
  return only(item, ['role', 'content']) && item.role === 'user' && string(item.content, 48 * 1024);
}

function validConversation(messages) {
  if (messages.length < 3 || messages.length > 9 || !userMessage(messages[1]) ||
      !envelope(messages[1].content) || !userMessage(messages[2])) return false;
  const pending = new Set(), seen = new Set();
  for (const message of messages.slice(3)) {
    if (message?.role === 'assistant') {
      if (pending.size || !only(message, ['role', 'content', 'tool_calls']) ||
          !(message.content === null || string(message.content, 32768)) ||
          !Array.isArray(message.tool_calls) || !message.tool_calls.length) return false;
      for (const call of message.tool_calls) {
        if (!validToolCall(call) || seen.has(call.id) || seen.size >= 3) return false;
        pending.add(call.id);
        seen.add(call.id);
      }
    } else if (!only(message, ['role', 'tool_call_id', 'content']) || message.role !== 'tool' ||
               !pending.delete(message.tool_call_id) || !envelope(message.content)) return false;
  }
  return pending.size === 0;
}

function turnInput(body, model) {
  if (!only(body, ['model', 'messages', 'stream', 'response_format', 'tools']) || body.model !== model ||
      typeof body.stream !== 'boolean' || !Array.isArray(body.messages)) throw requestError(400);
  const [instructions] = body.messages;
  if (!only(instructions, ['role', 'content']) || instructions.role !== 'system' ||
      !string(instructions.content, 4096)) throw requestError(400);
  const gate = !body.stream;
  if (digest(instructions.content) !== (gate ? gateDigest : answerDigest)) throw requestError(400);
  if (gate) {
    if (body.messages.length !== 2 || !userMessage(body.messages[1]) || body.tools !== undefined ||
        !only(body.response_format, ['type']) || body.response_format.type !== 'json_object') throw requestError(400);
  } else if (body.response_format !== undefined || !validConversation(body.messages) ||
             (body.tools !== undefined && digest(JSON.stringify(body.tools)) !== toolsDigest)) {
    throw requestError(400);
  }
  return { model, messages: body.messages, tools: body.tools ?? [], gate };
}

async function readBody(request) {
  if (request.headers['content-type']?.split(';')[0].trim().toLowerCase() !== 'application/json') {
    throw requestError(415);
  }
  if (Number(request.headers['content-length']) > maxRequestBytes) throw requestError(413);
  const chunks = [];
  let size = 0;
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > maxRequestBytes) throw requestError(413);
    chunks.push(chunk);
  }
  try { return JSON.parse(new TextDecoder('utf8', { fatal: true }).decode(Buffer.concat(chunks))); }
  catch { throw requestError(400); }
}

export function createFinanceGateway({ model, runTurn, turnTimeoutMs = 115_000 }) {
  const active = new Set();
  const server = createServer({ headersTimeout: 8000, requestTimeout: 12000, connectionsCheckingInterval: 1000 },
    async (request, response) => {
      const controller = new AbortController();
      const { signal } = controller;
      const closed = () => controller.abort();
      response.once('close', closed);
      let timer;
      try {
        response.setHeader('Cache-Control', 'no-store');
        if (request.method !== 'POST' || request.url !== '/v1/chat/completions') throw requestError(404);
        const input = turnInput(await readBody(request), model);
        if (active.size >= 2) throw requestError(429);
        active.add(controller);
        // Inbound transfer limits are independent of the model turn deadline.
        timer = setTimeout(() => controller.abort(), turnTimeoutMs).unref();
        signal.throwIfAborted();
        const sse = async (delta, finish_reason = null) => {
          signal.throwIfAborted();
          const data = { model, choices: [{ index: 0, delta, finish_reason }] };
          if (!response.write('data: ' + JSON.stringify(data) + '\n\n')) await once(response, 'drain', { signal });
        };
        if (!input.gate) {
          response.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'X-Accel-Buffering': 'no' });
          response.flushHeaders();
        }
        const onDelta = async text => {
          if (!input.gate && text) await sse({ content: text });
        };
        const result = await Promise.race([
          runTurn({ ...input, signal, onDelta }),
          once(signal, 'abort').then(() => { throw requestError(504); }),
        ]);
        signal.throwIfAborted();
        if (input.gate) {
          response.setHeader('Content-Type', 'application/json');
          response.end(JSON.stringify({ model, choices: [{ index: 0, finish_reason: 'stop',
            message: { role: 'assistant', content: result.text } }] }));
        } else {
          if (result.toolCall) {
            const { id, name, arguments: args } = result.toolCall;
            const call = { id, type: 'function', function: { name, arguments: args } };
            if (!input.tools.length || !validToolCall(call)) throw requestError(502);
            await sse({ tool_calls: [{ index: 0, ...call }] });
          }
          await sse({}, result.toolCall ? 'tool_calls' : 'stop');
          response.end('data: [DONE]\n\n');
        }
      } catch (err) {
        if (response.destroyed || response.writableEnded) return;
        const failure = JSON.stringify({ error: { message: 'Finance model request unavailable' } });
        if (response.headersSent) response.end('data: ' + failure + '\n\n');
        else {
          response.writeHead(err?.status ?? 502, { 'Content-Type': 'application/json', 'Connection': 'close' });
          response.end(failure);
        }
      } finally {
        clearTimeout(timer);
        response.off('close', closed);
        controller.abort();
        active.delete(controller);
      }
    });
  server.maxConnections = 16;
  const stop = () => {
    server.close();
    for (const controller of active) controller.abort();
    server.closeAllConnections();
  };
  return { server, stop };
}

export async function listenPrivate(server, socketPath) {
  if (!socketPath || !isAbsolute(socketPath) || Buffer.byteLength(socketPath) > 103) throw new Error('Invalid socket path');
  const directory = dirname(socketPath);
  await mkdir(directory, { mode: 0o700, recursive: true });
  const parent = await lstat(directory);
  if (!parent.isDirectory() || parent.uid !== process.getuid() || (parent.mode & 0o777) !== 0o700) {
    throw new Error('Socket directory must be private and owned by the service user');
  }
  const prior = await lstat(socketPath).catch(err => {
    if (err.code !== 'ENOENT') throw err;
    return null;
  });
  if (prior) {
    if (!prior.isSocket() || prior.uid !== parent.uid) throw new Error('Unexpected socket path');
    const client = createConnection(socketPath);
    try {
      await once(client, 'connect');
      throw new Error('Socket already in use');
    } catch (err) {
      if (err.code !== 'ECONNREFUSED') throw err;
      const stale = await lstat(socketPath);
      if (stale.ino !== prior.ino || stale.dev !== prior.dev) throw new Error('Socket path changed');
      await unlink(socketPath);
    } finally { client.destroy(); }
  }
  server.listen(socketPath);
  await once(server, 'listening');
  await chmod(socketPath, 0o600);
}

if (import.meta.main) {
  process.umask(0o077);
  const model = process.env.FINANCE_AI_MODEL;
  if (model !== 'gpt-6.1-terra') throw new Error('Finance requires gpt-6.1-terra');
  const { runCodexTurn } = await import('./codex-turn.mjs');
  const { server, stop } = createFinanceGateway({ model, runTurn: runCodexTurn });
  await listenPrivate(server, process.env.FINANCE_CODEX_SOCKET);
  for (const sig of ['SIGINT', 'SIGTERM']) process.once(sig, stop);
}
