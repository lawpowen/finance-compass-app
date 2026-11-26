import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_chat_transport.dart';

String localTimezone() => 'UTC';

AiChatRequest openAiChatRequest() => _NativeRequest();

class _NativeRequest implements AiChatRequest {
  final _client = http.Client();

  @override
  Future<AiChatResponse> send(
    String method,
    Uri uri,
    Map<String, String> headers, [
    String? body,
  ]) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers)
      ..headers['Origin'] = uri.origin;
    if (body != null) request.bodyBytes = utf8.encode(body);
    final response = await _client.send(request);
    return (
      statusCode: response.statusCode,
      contentType: response.headers['content-type'],
      body: response.stream,
    );
  }

  @override
  void abort() => _client.close();
}
