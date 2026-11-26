@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:finance_app/src/core/ai/ai_chat_client.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('window.fetch')
external JSFunction get _fetch;
@JS('window.fetch')
external set _fetch(JSFunction value);

extension type _Options(JSObject _) implements JSObject {
  external String get credentials;
  external String get mode;
  external String get redirect;
  external _Signal get signal;
  external String get body;
}

extension type _Signal(JSObject _) implements JSObject {
  external bool get aborted;
}

@JS('TransformStream')
extension type _Pipe._(JSObject _) implements JSObject {
  external factory _Pipe();
  external JSObject get readable;
  external _Writable get writable;
}

extension type _Writable(JSObject _) implements JSObject {
  external _Writer getWriter();
}

extension type _Writer(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array value);
  external JSPromise<JSAny?> close();
}

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSObject body, JSObject init);
}

void main() {
  test(
      'browser fetch uses the signed-in origin, streams before EOF and carries a live AbortSignal',
      () async {
    final original = _fetch;
    addTearDown(() => _fetch = original);
    final pipe = _Pipe();
    final writer = pipe.writable.getWriter();
    final response = _Response(
        pipe.readable,
        {
          'headers': {'Content-Type': 'text/event-stream; charset=utf-8'},
        }.jsify() as JSObject);
    final options = Completer<_Options>();
    _fetch = ((JSString url, _Options request) {
      expect(Uri.parse(url.toDart).path, '/api/sync/v1/ai/chat');
      options.complete(request);
      return Future.value(response).toJS;
    }).toJS;
    final client = AiChatClient();
    addTearDown(client.close);
    final token = Completer<AiChatEvent>();
    final subscription =
        client.chat(accountId: 'fixture', message: '预算').listen(token.complete);
    final request = await options.future;
    expect(request.credentials, 'same-origin');
    expect(request.mode, 'same-origin');
    expect(request.redirect, 'error');
    expect(
        jsonDecode(request.body)['timezone'],
        isA<String>()
            .having((s) => s.isNotEmpty, 'nonempty IANA timezone', true));
    final bytes = utf8.encode('event: delta\ndata: {"text":"茶"}\n\n');
    for (final byte in bytes) {
      await writer.write(Uint8List.fromList([byte]).toJS).toDart;
    }
    expect((await token.future.timeout(const Duration(seconds: 3))).text, '茶');
    expect(request.signal.aborted, isFalse);
    final stopped = subscription.cancel();
    expect(request.signal.aborted, isTrue);
    await writer.close().toDart;
    await stopped;
  });
}
