import { request as requestHttp } from 'node:http';
import { Readable } from 'node:stream';

const defaultTimeoutMs = 90_000;
const maxStreamBytes = 2 * 1024 * 1024;
const maxEventChars = 64 * 1024;

function completionEndpoint(base) {
  if (!base || /[\s\\?#]/.test(base)) return null;
  try {
    const url = new URL(base);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
    const path = url.pathname.replace(/\/+$/, '');
    if (!path.endsWith('/v1/chat/completions')) {
      url.pathname = path + (path.endsWith('/v1') ? '' : '/v1') + '/chat/completions';
    } else {
      url.pathname = path;
    }
    return url;
  } catch {
    return null;
  }
}

async function* decodedChunks(response, limit) {
  if (!response.body) throw new Error('Missing upstream body');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let bytes = 0;
  for await (const chunk of response.body) {
    bytes += chunk.byteLength;
    if (bytes > limit) throw new Error('Upstream response too large');
    yield decoder.decode(chunk, { stream: true });
  }
  yield decoder.decode();
}

async function* eventData(response) {
  let pending = '';
  let data = [];
  let size = 0;
  let skipLf = false;
  for await (let chunk of decodedChunks(response, maxStreamBytes)) {
    if (!chunk) continue;
    if (skipLf && chunk.startsWith('\n')) chunk = chunk.slice(1);
    skipLf = false;
    if (!chunk) continue;
    skipLf = chunk.endsWith('\r');
    const lines = chunk.split(/\r\n|\r|\n/);
    lines[0] = pending + lines[0];
    pending = lines.pop();
    if (pending.length > maxEventChars) throw new Error('Upstream line too large');
    for (const line of lines) {
      if (line === '') {
        if (data.length) yield data.join('\n');
        data = [];
        size = 0;
      } else if (line === 'data' || line.startsWith('data:')) {
        const field = line.slice(5).replace(/^ /, '');
        size += field.length + 1;
        if (size > maxEventChars) throw new Error('Upstream event too large');
        data.push(field);
      }
    }
  }
}

function addToolDelta(calls, delta) {
  if (!Number.isInteger(delta.index) || delta.index < 0 || delta.index >= 16 ||
      (delta.type != null && delta.type !== 'function')) {
    throw new Error('Invalid tool call');
  }
  const call = calls.get(delta.index) ?? { id: '', name: '', arguments: '' };
  for (const [key, part, limit] of [
    ['id', delta.id, 128], ['name', delta.function?.name, 64],
    ['arguments', delta.function?.arguments, 16 * 1024],
  ]) {
    if (part == null) continue;
    if (typeof part !== 'string' || call[key].length + part.length > limit) {
      throw new Error('Invalid tool delta');
    }
    call[key] += part;
  }
  calls.set(delta.index, call);
}

function completedCalls(calls) {
  const result = [];
  const ids = new Set();
  for (let i = 0; i < calls.size; i++) {
    const call = calls.get(i);
    if (!call || !/^[\x21-\x7e]{1,128}$/.test(call.id) ||
        !/^[A-Za-z0-9_-]{1,64}$/.test(call.name) || ids.has(call.id)) {
      throw new Error('Invalid tool call identity');
    }
    ids.add(call.id);
    result.push(call);
  }
  return result;
}

function upstreamError(signal) {
  return new Error(signal.aborted ? 'AI 请求已取消或超时。' : 'AI 网关暂不可用。');
}

function localSocketPath(value) {
  if (typeof value !== 'string' || /[\x00-\x1f\x7f]/.test(value)) return null;
  if (process.platform === 'win32') {
    return /^\\\\\.\\pipe\\[\w.-]+$/.test(value) ? value : null;
  }
  return /^\/(?!\/)/.test(value) && !value.split('/').includes('..') ? value : null;
}

// The host adapter owns the Codex login. Finance connects only to its mounted
// socket and never follows redirects or forwards the HTTP provider's API key.
function postToSocket(socketPath, { headers, body, signal }) {
  return new Promise((resolve, reject) => {
    const request = requestHttp({
      socketPath, path: '/v1/chat/completions', method: 'POST', headers, signal, agent: false,
    }, incoming => {
      if (incoming.statusCode !== 200) {
        incoming.destroy();
        reject(new Error('Codex gateway unavailable'));
        return;
      }
      const stream = Readable.toWeb(incoming, {
        strategy: { highWaterMark: 64 * 1024, size: chunk => chunk.byteLength },
      });
      resolve(new Response(stream));
    });
    request.on('error', reject);
    request.end(body);
  });
}

// A provider exposes a text-only scope gate and a chat stream. Adapters own
// transport details; account identity, ledger access and tool execution stay
// in the sync service.
export function createAiProvider(env = process.env, options = {}) {
  const name = env.FINANCE_AI_PROVIDER?.trim() || 'openai_compatible';
  const codex = name === 'codex_terra';
  if (!codex && name !== 'openai_compatible') return null;
  const endpoint = codex ? localSocketPath(env.FINANCE_AI_CODEX_SOCKET) :
    completionEndpoint(env.FINANCE_AI_BASE_URL?.trim());
  const model = env.FINANCE_AI_MODEL?.trim();
  const gateModel = env.FINANCE_AI_GATE_MODEL?.trim() || model;
  const validModel = value => value && value.length <= 256 && !/[\x00-\x1f\x7f]/.test(value);
  const token = codex ? undefined : env.FINANCE_AI_API_KEY?.trim();
  if (!endpoint || !validModel(model) ||
      !validModel(gateModel) || (token && !/^[\x21-\x7e]+$/.test(token))) return null;
  const timeout = Number(env.FINANCE_AI_TIMEOUT_MS);
  const timeoutMs = Number.isSafeInteger(timeout) && timeout > 0
    ? Math.min(timeout, 120_000) : defaultTimeoutMs;
  const post = codex ? postToSocket : options.fetchImpl ?? fetch;

  async function request(body, signal) {
    const response = await post(endpoint, {
      method: 'POST', redirect: 'error', signal,
      headers: {
        'Content-Type': 'application/json',
        Accept: body.stream ? 'text/event-stream' : 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error('Upstream request failed');
    }
    return response;
  }

  function requestScope(signal) {
    const controller = new AbortController();
    const signals = [controller.signal, AbortSignal.timeout(timeoutMs)];
    if (signal) signals.push(signal);
    return { controller, signal: AbortSignal.any(signals) };
  }

  return {
    name, timeoutMs,
    async gate({ messages, signal }) {
      const scope = requestScope(signal);
      try {
        const response = await request({
          model: gateModel, messages, stream: false,
          response_format: { type: 'json_object' },
        }, scope.signal);
        let json = '';
        for await (const chunk of decodedChunks(response, 32 * 1024)) json += chunk;
        const payload = JSON.parse(json);
        const choice = payload.choices?.[0];
        if (payload.error || !choice || (choice.finish_reason != null && choice.finish_reason !== 'stop') ||
            choice.message?.refusal || typeof choice.message?.content !== 'string') {
          throw new Error('Invalid gate response');
        }
        return choice.message.content;
      } catch {
        throw upstreamError(scope.signal);
      } finally {
        scope.controller.abort();
      }
    },
    async *stream({ messages, tools, signal }) {
      const scope = requestScope(signal);
      try {
        const response = await request({
          model, messages, stream: true, ...(tools?.length ? { tools } : {}),
        }, scope.signal);
        let complete = false;
        const calls = new Map();
        for await (const data of eventData(response)) {
          if (data.trim() === '[DONE]') {
            complete = true;
            break;
          }
          const payload = JSON.parse(data);
          if (payload.error || !Array.isArray(payload.choices)) throw new Error('Invalid chat stream');
          if (!payload.choices.length) continue; // Optional final usage event.
          const choice = payload.choices[0];
          if (complete || (choice.index != null && choice.index !== 0)) throw new Error('Unexpected choice');
          const delta = choice.delta;
          if (!delta || typeof delta !== 'object') throw new Error('Invalid chat delta');
          if (delta.content != null) {
            if (typeof delta.content !== 'string') throw new Error('Invalid text delta');
            if (delta.content) yield { type: 'text', text: delta.content };
          }
          for (const part of delta.tool_calls ?? []) addToolDelta(calls, part);
          if (choice.finish_reason != null) {
            if (!['stop', 'tool_calls'].includes(choice.finish_reason) ||
                (choice.finish_reason === 'tool_calls' && !calls.size)) {
              throw new Error('Incomplete completion');
            }
            complete = true;
          }
        }
        if (!complete) throw new Error('Truncated chat stream');
        if (calls.size) yield { type: 'tool_calls', calls: completedCalls(calls) };
      } catch {
        throw upstreamError(scope.signal);
      } finally {
        scope.controller.abort();
      }
    },
  };
}
