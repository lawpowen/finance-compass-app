import 'dart:async';
import 'dart:convert';

import 'ai_chat_transport.dart';
import 'ai_chat_transport_native.dart'
    if (dart.library.js_interop) 'ai_chat_transport_web.dart' as platform;

class AiChatStatus {
  const AiChatStatus({required this.enabled, this.provider});
  final bool enabled;
  final String? provider;
}

enum AiChatEventType { status, delta, refused, done, error }

class AiChatEvent {
  const AiChatEvent(
    this.type, {
    this.text = '',
    this.reason,
    this.code,
    this.revision,
    this.asOf,
    this.toolsUsed = const [],
  });

  final AiChatEventType type;
  final String text;
  final String? reason;
  final String? code;
  final int? revision;
  final String? asOf;
  final List<String> toolsUsed;
}

class AiChatException implements Exception {
  const AiChatException(this.code, this.message, {this.statusCode});
  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

const _invalidResponse = AiChatException('invalid_response', '助手响应格式异常，请重试。');
const _timeout = AiChatException('timeout', '助手响应超时，请重试。');
const _closed = AiChatException('closed', '助手会话已关闭。');
const _network = AiChatException('network', '无法连接理财助手，请检查网络后重试。');

class AiChatClient {
  AiChatClient({
    Uri? baseUri,
    AiChatRequest Function()? openRequest,
    Duration statusTimeout = const Duration(seconds: 12),
    Duration chatTimeout = const Duration(seconds: 125),
  })  : _baseUri = baseUri ?? Uri.base,
        _openRequest = openRequest ?? platform.openAiChatRequest,
        _statusTimeout = statusTimeout,
        _chatTimeout = chatTimeout;

  final Uri _baseUri;
  final AiChatRequest Function() _openRequest;
  final Duration _statusTimeout;
  final Duration _chatTimeout;
  final Set<void Function()> _active = {};
  bool _isClosed = false;

  Future<AiChatStatus> status(String accountId) async {
    if (_isClosed) throw _closed;
    final request = _openRequest();
    final abort = request.abort;
    _active.add(abort);
    try {
      return await _loadStatus(request, accountId).timeout(_statusTimeout);
    } on TimeoutException {
      throw _timeout;
    } on FormatException {
      throw _invalidResponse;
    } on AiChatException {
      rethrow;
    } catch (_) {
      throw _isClosed ? _closed : _network;
    } finally {
      if (_active.remove(abort)) abort();
    }
  }

  Future<AiChatStatus> _loadStatus(
      AiChatRequest request, String accountId) async {
    final response = await request.send(
      'GET',
      _baseUri.resolve('/api/sync/v1/ai/status'),
      {'Accept': 'application/json', 'X-Finance-Account': accountId},
    );
    _checkResponse(response, 'application/json');
    final bytes = <int>[];
    await for (final chunk in response.body) {
      if (bytes.length + chunk.length > 8192) throw _invalidResponse;
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data case {'enabled': false}) return const AiChatStatus(enabled: false);
    if (data
        case {
          'enabled': true,
          'streaming': true,
          'provider': String provider
        }) {
      return AiChatStatus(enabled: true, provider: provider);
    }
    throw _invalidResponse;
  }

  Stream<AiChatEvent> chat({
    required String accountId,
    required String message,
    List<Map<String, String>> history = const [],
    String? timezone,
  }) {
    late final StreamController<AiChatEvent> output;
    AiChatRequest? request;
    Timer? deadline;
    bool finished = false;

    void finish([AiChatException? error]) {
      if (finished) return;
      finished = true;
      deadline?.cancel();
      request?.abort();
      _active.remove(finish);
      if (error != null) output.addError(error);
      unawaited(output.close());
    }

    Future<void> start() async {
      if (_isClosed) {
        finish(_closed);
        return;
      }
      try {
        request = _openRequest();
        _active.add(finish);
        deadline = Timer(_chatTimeout, () => finish(_timeout));
        final response = await request!.send(
          'POST',
          _baseUri.resolve('/api/sync/v1/ai/chat'),
          {
            'Accept': 'text/event-stream',
            'Content-Type': 'application/json; charset=utf-8',
            'X-Finance-Account': accountId,
          },
          jsonEncode({
            'message': message,
            'history': history,
            'timezone': timezone ?? platform.localTimezone(),
          }),
        );
        if (finished) return;
        _checkResponse(response, 'text/event-stream');
        await for (final event in parseAiChatEvents(response.body)) {
          if (finished) return;
          output.add(event);
        }
        finish();
      } on AiChatException catch (error) {
        finish(error);
      } on FormatException {
        finish(_invalidResponse);
      } catch (_) {
        finish(_network);
      }
    }

    // An async* generator cannot abort a pending fetch/read until its await
    // resolves. Calling the transport directly also covers stopping pre-headers.
    output = StreamController<AiChatEvent>(onListen: start, onCancel: finish);
    return output.stream;
  }

  void close() {
    _isClosed = true;
    for (final abort in _active.toList()) {
      abort();
    }
    _active.clear();
  }
}

void _checkResponse(AiChatResponse response, String expectedType) {
  if (response.statusCode != 200) {
    final (code, message) = switch (response.statusCode) {
      401 => ('unauthorized', '登录已过期，请重新登录。'),
      403 => ('forbidden', '当前请求未获授权。'),
      409 => ('account_changed', '账本账号已切换，请重新进入理财助手。'),
      400 || 413 => ('invalid_input', '消息或对话记录超出限制，请缩短后重试。'),
      429 => ('rate_limited', '当前请求较多，请稍后重试。'),
      503 => ('unavailable', '理财助手暂不可用。'),
      _ => ('http_error', '理财助手请求失败，请稍后重试。'),
    };
    throw AiChatException(code, message, statusCode: response.statusCode);
  }
  if (response.contentType?.split(';').first.trim().toLowerCase() !=
      expectedType) {
    throw _invalidResponse;
  }
}

/// The UTF-8 and line decoders keep incomplete characters and CRLF pairs across
/// chunks. Only a blank line dispatches an SSE event.
Stream<AiChatEvent> parseAiChatEvents(Stream<List<int>> bytes) async* {
  var size = 0;
  final bounded = bytes.map((chunk) {
    size += chunk.length;
    if (size > 1024 * 1024) throw _invalidResponse;
    return chunk;
  });
  var name = '';
  final data = <String>[];
  await for (final line
      in bounded.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      final type = _eventTypes[name];
      if (type != null && data.isNotEmpty) {
        final event = _decodeEvent(type, data.join('\n'));
        yield event;
        if (type == AiChatEventType.done || type == AiChatEventType.error) {
          return;
        }
      }
      name = '';
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') name = value;
    if (field == 'data') data.add(value);
  }
  throw const AiChatException('incomplete', '连接已中断，回复尚未完成。');
}

final _eventTypes = {
  for (final type in AiChatEventType.values) type.name: type
};

AiChatEvent _decodeEvent(AiChatEventType type, String json) {
  final data = jsonDecode(json);
  return switch ((type, data)) {
    (AiChatEventType.status || AiChatEventType.delta, {'text': String text}) =>
      AiChatEvent(type, text: text),
    (AiChatEventType.refused, {'reason': String reason, 'text': String text}) =>
      AiChatEvent(type, reason: reason, text: text),
    (AiChatEventType.error, {'code': String code, 'message': String message}) =>
      AiChatEvent(type, code: code, text: message),
    (
      AiChatEventType.done,
      {'revision': int? revision, 'asOf': String asOf, 'toolsUsed': List used}
    )
        when used.every((entry) => entry is String) =>
      AiChatEvent(type,
          revision: revision,
          asOf: asOf,
          toolsUsed: List<String>.unmodifiable(used)),
    _ => throw _invalidResponse,
  };
}
