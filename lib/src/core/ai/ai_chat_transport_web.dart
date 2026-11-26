import 'dart:js_interop';

import 'ai_chat_transport.dart';

@JS('window.fetch')
external JSPromise<_Response> _fetch(JSString url, _RequestInit options);

@JS()
extension type _RequestInit._(JSObject _) implements JSObject {
  external factory _RequestInit({
    required String method,
    required String mode,
    required String credentials,
    required String redirect,
    required String cache,
    required JSObject headers,
    required JSObject signal,
    JSString? body,
  });
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external _Headers get headers;
  external _ReadableStream? get body;
}

extension type _Headers._(JSObject _) implements JSObject {
  external String? get(String key);
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external void releaseLock();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array get value;
}

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _DateTimeOptions resolvedOptions();
}

extension type _DateTimeOptions._(JSObject _) implements JSObject {
  external String? get timeZone;
}

String localTimezone() {
  try {
    return _DateTimeFormat().resolvedOptions().timeZone ?? 'UTC';
  } catch (_) {
    return 'UTC';
  }
}

AiChatRequest openAiChatRequest() => _BrowserRequest();

class _BrowserRequest implements AiChatRequest {
  final _controller = _AbortController();

  @override
  Future<AiChatResponse> send(
    String method,
    Uri uri,
    Map<String, String> headers, [
    String? body,
  ]) async {
    final options = _RequestInit(
      method: method,
      mode: 'same-origin',
      credentials: 'same-origin',
      redirect: 'error',
      cache: 'no-store',
      headers: headers.jsify() as JSObject,
      signal: _controller.signal,
      body: body?.toJS,
    );
    final response = await _fetch(uri.toString().toJS, options).toDart;
    return (
      statusCode: response.status,
      contentType: response.headers.get('content-type'),
      body: _read(response.body),
    );
  }

  Stream<List<int>> _read(_ReadableStream? body) async* {
    if (body == null) return;
    final reader = body.getReader();
    try {
      while (true) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        yield chunk.value.toDart;
      }
    } finally {
      reader.releaseLock();
    }
  }

  @override
  void abort() => _controller.abort();
}
