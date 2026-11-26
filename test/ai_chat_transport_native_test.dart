@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/src/core/ai/ai_chat_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'native transport consumes a flushed token before the HTTP response finishes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final uri = Uri.http('127.0.0.1:${server.port}', '/');
    final client = AiChatClient(baseUri: uri);
    addTearDown(client.close);
    final release = Completer<void>();
    final request = server.first.then((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(request.uri.path, '/api/sync/v1/ai/chat');
      expect(request.headers.value('X-Finance-Account'), 'demo');
      expect(request.headers.value('Origin'), uri.origin);
      expect(body['message'], '本期预算');
      expect(body['timezone'], 'UTC');
      request.response
        ..bufferOutput = false
        ..headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8')
        ..write('event: delta\ndata: {"text":"第一笔"}\n\n');
      await request.response.flush();
      await release.future;
      request.response.write(
          'event: done\ndata: {"revision":1,"asOf":"2026-11-26","toolsUsed":[]}\n\n');
      await request.response.close();
    });
    final received = <AiChatEvent>[];
    await for (final event in client.chat(accountId: 'demo', message: '本期预算')) {
      received.add(event);
      if (event.type == AiChatEventType.delta) release.complete();
    }
    await request;
    expect(received.map((e) => e.type),
        [AiChatEventType.delta, AiChatEventType.done]);
    expect(received.first.text, '第一笔');
  });
}
