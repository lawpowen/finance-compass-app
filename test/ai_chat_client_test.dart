import 'dart:async';
import 'dart:convert';

import 'package:finance_app/src/core/ai/ai_chat_client.dart';
import 'package:finance_app/src/core/ai/ai_chat_transport.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Captured = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  String? body
});

class _Request implements AiChatRequest {
  final recorded = Completer<_Captured>();
  final response = Completer<AiChatResponse>();
  bool aborted = false;

  @override
  Future<AiChatResponse> send(
      String method, Uri uri, Map<String, String> headers,
      [String? body]) {
    recorded.complete((method: method, uri: uri, headers: headers, body: body));
    return response.future;
  }

  @override
  void abort() => aborted = true;
}

AiChatResponse _response(String content, String body, {int status = 200}) => (
      statusCode: status,
      contentType: content,
      body: Stream.value(utf8.encode(body)),
    );

const _done =
    'event: done\ndata: {"revision":34,"asOf":"2026-11-26","toolsUsed":["search_transactions"]}\n\n';
const _sse = 'text/event-stream; charset=utf-8';

void main() {
  test(
      'SSE carries Chinese/emoji UTF-8 and CRLF over arbitrary byte boundaries',
      () async {
    const wire =
        '\uFEFF: heartbeat\r\nevent: status\r\ndata: {"text":"查询…"}\r\n\r\n'
        'event: delta\ndata: {"text":\ndata: "金额🎯"}\n\n'
        'event: future\ndata: ignored\n\n'
        '$_done';
    final bytes = Stream.fromIterable(utf8.encode(wire).map((byte) => [byte]));
    final events = await parseAiChatEvents(bytes).toList();
    expect(events.map((e) => e.type),
        [AiChatEventType.status, AiChatEventType.delta, AiChatEventType.done]);
    expect(events.map((e) => e.text), ['查询…', '金额🎯', '']);
    expect(events.last.revision, 34);
    expect(events.last.asOf, '2026-11-26');
    expect(events.last.toolsUsed, ['search_transactions']);
  });

  test('coalesced refused and done events allow a ledger-free refusal',
      () async {
    const wire =
        'event: refused\ndata: {"reason":"off_topic","text":"仅限理财"}\n\n'
        'event: done\ndata: {"revision":null,"asOf":"2026-11-26","toolsUsed":[]}\n\n';
    final events =
        await parseAiChatEvents(Stream.value(utf8.encode(wire))).toList();
    expect(events.first.type, AiChatEventType.refused);
    expect(events.first.reason, 'off_topic');
    expect(events.first.text, '仅限理财');
    expect(events.last.revision, isNull);
  });

  test('SSE error is terminal and an interrupted reply never counts as done',
      () async {
    final events = await parseAiChatEvents(Stream.value(utf8.encode(
      'event: error\ndata: {"code":"upstream","message":"请稍后重试"}\n\n$_done',
    ))).toList();
    expect(events.single.type, AiChatEventType.error);
    expect(events.single.code, 'upstream');
    expect(events.single.text, '请稍后重试');
    await expectLater(
      parseAiChatEvents(
          Stream.value(utf8.encode('event: delta\ndata: {"text":"半句"}\n\n'))),
      emitsInOrder([
        isA<AiChatEvent>().having((e) => e.text, 'text', '半句'),
        emitsError(
            isA<AiChatException>().having((e) => e.code, 'code', 'incomplete')),
        emitsDone,
      ]),
    );
  });

  test('deliver the first delta while the upstream HTTP body is still open',
      () async {
    final request = _Request();
    final client = AiChatClient(
        baseUri: Uri.parse('https://finance.example/path'),
        openRequest: () => request);
    addTearDown(client.close);
    final input = StreamController<List<int>>();
    final first = Completer<AiChatEvent>();
    final done = Completer<void>();
    client
        .chat(
      accountId: 'account-a',
      message: '账单',
      history: const [
        {'role': 'user', 'content': '上月'}
      ],
      timezone: 'Asia/Kuala_Lumpur',
    )
        .listen((event) {
      if (!first.isCompleted) first.complete(event);
    }, onDone: done.complete);
    final recorded = await request.recorded.future;
    expect(
        recorded.uri, Uri.parse('https://finance.example/api/sync/v1/ai/chat'));
    expect(recorded.method, 'POST');
    expect(recorded.headers['X-Finance-Account'], 'account-a');
    expect(jsonDecode(recorded.body!), {
      'message': '账单',
      'history': [
        {'role': 'user', 'content': '上月'}
      ],
      'timezone': 'Asia/Kuala_Lumpur',
    });
    request.response
        .complete((statusCode: 200, contentType: _sse, body: input.stream));
    input.add(utf8.encode('event: delta\ndata: {"text":"首字"}\n\n'));
    expect((await first.future.timeout(const Duration(seconds: 2))).text, '首字');
    expect(done.isCompleted, isFalse);
    input.add(utf8.encode(_done));
    await done.future.timeout(const Duration(seconds: 2));
    expect(request.aborted, isTrue);
    await input.close();
  });

  for (final status in [401, 409]) {
    test('HTTP $status survives as a typed session error with safe text',
        () async {
      final request = _Request();
      final client = AiChatClient(openRequest: () => request);
      final result = client.chat(accountId: 'a', message: '账单').drain<void>();
      request.response
          .complete(_response('text/html', 'internal detail', status: status));
      await expectLater(
          result,
          throwsA(isA<AiChatException>()
              .having((e) => e.statusCode, 'status', status)
              .having((e) => e.message, 'message',
                  isNot(contains('internal detail')))));
      expect(request.aborted, isTrue);
    });
  }

  test('stopping initiates abort synchronously before HTTP headers arrive',
      () async {
    final request = _Request();
    final client = AiChatClient(openRequest: () => request);
    final subscription = client
        .chat(accountId: 'a', message: '账单')
        .listen((_) => fail('late token'));
    await request.recorded.future;
    final result = subscription.cancel();
    expect(request.aborted, isTrue);
    request.response.complete(_response(_sse, _done));
    await result;
  });

  test('client timeout actively aborts pending HTTP request', () async {
    final request = _Request();
    final client = AiChatClient(
        openRequest: () => request,
        chatTimeout: const Duration(milliseconds: 20));
    await expectLater(
      client.chat(accountId: 'a', message: '账单').drain<void>(),
      throwsA(isA<AiChatException>().having((e) => e.code, 'code', 'timeout')),
    );
    expect(request.aborted, isTrue);
    request.response.complete(_response(_sse, _done));
  });

  test('disabled status is valid and sends only the scoped same-origin GET',
      () async {
    final request = _Request();
    final client = AiChatClient(
        baseUri: Uri.parse('https://finance.example/#/'),
        openRequest: () => request);
    final pending = client.status('account-b');
    final call = await request.recorded.future;
    expect(
        call.uri.toString(), 'https://finance.example/api/sync/v1/ai/status');
    expect(call.headers['X-Finance-Account'], 'account-b');
    expect(call.method, 'GET');
    expect(call.body, isNull);
    request.response
        .complete(_response('application/json', '{"enabled":false}'));
    expect((await pending).enabled, isFalse);
    expect(request.aborted, isTrue);
  });

  test(
      'malformed JSON and unexpected content types never disclose a response body',
      () async {
    for (final response in [
      _response('text/html', '<html>server detail</html>'),
      _response(_sse, 'event: delta\ndata: server detail\n\n'),
    ]) {
      final request = _Request();
      final client = AiChatClient(openRequest: () => request);
      final pending = client.chat(accountId: 'a', message: '状态').toList();
      request.response.complete(response);
      await expectLater(
          pending,
          throwsA(isA<AiChatException>()
              .having((e) => e.code, 'code', 'invalid_response')));
    }
  });
}
