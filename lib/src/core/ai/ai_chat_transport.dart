typedef AiChatResponse = ({
  int statusCode,
  String? contentType,
  Stream<List<int>> body,
});

/// Each request owns its transport so stopping a chat cannot abort ledger sync.
abstract interface class AiChatRequest {
  Future<AiChatResponse> send(
    String method,
    Uri uri,
    Map<String, String> headers, [
    String? body,
  ]);
  void abort();
}
