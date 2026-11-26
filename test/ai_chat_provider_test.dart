import 'dart:async';

import 'package:finance_app/src/core/ai/ai_chat_client.dart';
import 'package:finance_app/src/core/providers/ai_chat_provider.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/sync/ledger_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Session extends LedgerSyncSession {
  _Session([String accountId = 'a'])
      : super(
          LedgerSyncApi(http.Client(), Uri.parse('https://example.invalid')),
          (
            accountId: accountId,
            username: accountId,
            revision: 3,
            snapshot: null
          ),
        );

  bool pending = false;
  int kicks = 0;

  @override
  bool get hasPending => pending;

  @override
  void kickBackgroundSync({bool immediate = false}) {
    if (immediate) kicks++;
  }

  void setPending(bool value) {
    pending = value;
    notifyListeners();
  }

  @override
  void dispose() {
    api.client.close();
    super.dispose();
  }
}

class _Request {
  _Request(this.accountId, this.message, this.history) {
    events = StreamController(
        sync: true,
        onCancel: () {
          cancelled = true;
        });
  }

  final String accountId;
  final String message;
  final List<Map<String, String>> history;
  late final StreamController<AiChatEvent> events;
  bool cancelled = false;

  void answer(String text) {
    events.add(AiChatEvent(AiChatEventType.delta, text: text));
    events.add(const AiChatEvent(AiChatEventType.done,
        revision: 7, asOf: '2026-11-26'));
  }
}

class _Client extends AiChatClient {
  final requests = <_Request>[];
  final accountsChecked = <String>[];
  Completer<AiChatStatus>? statusResponse;
  bool closed = false;

  @override
  Future<AiChatStatus> status(String accountId) {
    accountsChecked.add(accountId);
    return statusResponse?.future ??
        Future.value(const AiChatStatus(enabled: true));
  }

  @override
  Stream<AiChatEvent> chat(
      {required String accountId,
      required String message,
      List<Map<String, String>> history = const [],
      String? timezone}) {
    final request = _Request(accountId, message, history);
    requests.add(request);
    return request.events.stream;
  }

  @override
  void close() {
    closed = true;
    for (final request in requests) {
      unawaited(request.events.close());
    }
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _Session session;
  late ProviderContainer container;
  late List<_Client> clients;
  _Client client() => clients.last;
  AiChatState state() => container.read(aiChatProvider);
  AiChatController notifier() => container.read(aiChatProvider.notifier);

  void switchSession(LedgerSyncSession? next) {
    container.updateOverrides([
      ledgerSyncSessionProvider.overrideWithValue(next),
      aiChatClientFactoryProvider.overrideWithValue(
        container.read(aiChatClientFactoryProvider),
      ),
    ]);
  }

  setUp(() {
    session = _Session();
    clients = [];
    container = ProviderContainer(overrides: [
      ledgerSyncSessionProvider.overrideWithValue(session),
      aiChatClientFactoryProvider.overrideWithValue((_) {
        final client = _Client();
        clients.add(client);
        return client;
      }),
    ]);
  });
  tearDown(() {
    container.dispose();
    session.dispose();
  });

  Future<void> ready() async {
    expect(state().availability, AiChatAvailability.checking);
    await _tick();
    expect(state().availability, AiChatAvailability.ready);
    expect(client().accountsChecked, [session.accountId]);
  }

  test(
      'each delta is visible immediately; stop aborts and excludes the partial turn',
      () async {
    await ready();
    final send = notifier().send(' 本月预算 ');
    final request = client().requests.single;
    expect((request.accountId, request.message), ('a', '本月预算'));
    expect(request.history, isEmpty);
    request.events
        .add(const AiChatEvent(AiChatEventType.status, text: '正在查询预算'));
    expect(state().statusText, '正在查询预算');
    request.events.add(const AiChatEvent(AiChatEventType.delta, text: '本月'));
    expect(state().messages.last.text, '本月');
    request.events.add(const AiChatEvent(AiChatEventType.delta, text: '预算'));
    expect(state().messages.last.text, '本月预算');
    notifier().stop();
    expect(request.cancelled, isTrue);
    await send;
    request.events.add(const AiChatEvent(AiChatEventType.delta, text: '迟到'));
    expect(state().messages.last.text, '本月预算');
    final next = notifier().send('信用卡账单');
    expect(client().requests.last.history, isEmpty);
    client().requests.last.answer('摘要');
    await next;
    expect(state().revision, 7);
    expect(state().asOf, '2026-11-26');
    notifier().clear();
    expect(state().messages, isEmpty);
    expect(state().revision, isNull);
  });

  test(
      'pending upload gets one bounded opportunity; a stop during the wait is immediate',
      () async {
    await ready();
    session.setPending(true);
    final stopped = notifier().send('支出');
    expect(session.kicks, 1);
    expect(client().requests, isEmpty);
    notifier().stop();
    await stopped;
    expect(client().requests, isEmpty);
    final send = notifier().send('现金流');
    expect(session.kicks, 2);
    expect(client().requests, isEmpty);
    session.setPending(false);
    await _tick();
    expect(state().hasPending, isFalse);
    client().requests.single.answer('收入与支出');
    await send;
    session.setPending(true);
    final timeout = notifier().send('净资产');
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(session.kicks, 3);
    expect(client().requests.last.message, '净资产');
    expect(state().hasPending, isTrue);
    client().requests.last.answer('已同步的数据');
    await timeout;
  });

  test(
      'new login for the same id / another id / offline clears and aborts previous requests',
      () async {
    await ready();
    for (final nextId in ['a', 'b']) {
      final oldSession = session;
      final oldClient = client();
      final pending = notifier().send('旧账本');
      oldClient.requests.last.events
          .add(const AiChatEvent(AiChatEventType.delta, text: '余额'));
      session = _Session(nextId);
      switchSession(session);
      expect(state().messages, isEmpty);
      expect(oldClient.closed, isTrue);
      expect(oldClient.requests.last.cancelled, isTrue);
      await pending;
      await _tick();
      expect(client().accountsChecked, [nextId]);
      oldSession.dispose();
    }
    final oldClient = client();
    final pending = notifier().send('旧账本');
    switchSession(null);
    expect(state().availability, AiChatAvailability.offline);
    expect(state().messages, isEmpty);
    expect(oldClient.closed, isTrue);
    await pending;
    await notifier().send('离线问题');
    expect(oldClient.requests.length, 1);
  });

  test('a stale status request cannot re-enable a replaced or offline login',
      () async {
    state();
    final old = client();
    final response = old.statusResponse = Completer<AiChatStatus>();
    await _tick();
    switchSession(null);
    expect(state().availability, AiChatAvailability.offline);
    response.complete(const AiChatStatus(enabled: true));
    await _tick();
    expect(old.closed, isTrue);
    expect(state().availability, AiChatAvailability.offline);
  });

  for (final (status, code) in [
    (401, 'unauthorized'),
    (409, 'account_changed')
  ]) {
    test('HTTP $status expires the login and clears account contents',
        () async {
      await ready();
      final sent = notifier().send('账本');
      client()
          .requests
          .single
          .events
          .addError(AiChatException(code, '会话失效', statusCode: status));
      await sent;
      expect(session.authenticationExpired, isTrue);
      expect(session.accountMismatch, status == 409);
      expect(state().availability, AiChatAvailability.unavailable);
      expect(state().messages, isEmpty);
      expect(state().errorText, isNotEmpty);
    });
    test(
        'SSE $code erases the partial reply and invalidates the ledger session',
        () async {
      await ready();
      final sent = notifier().send('预算');
      final request = client().requests.single;
      request.events
          .add(const AiChatEvent(AiChatEventType.delta, text: '旧会话余额'));
      request.events
          .add(AiChatEvent(AiChatEventType.error, text: '会话失效', code: code));
      expect(state().messages, isEmpty);
      expect(request.cancelled, isTrue);
      expect(session.authenticationExpired, isTrue);
      expect(session.accountMismatch, status == 409);
      await sent;
    });
  }

  test('offline / disabled status never opens a chat request', () async {
    state();
    client().statusResponse = Completer()
      ..complete(const AiChatStatus(enabled: false));
    await _tick();
    expect(state().availability, AiChatAvailability.disabled);
    await notifier().send('预计支出');
    expect(client().requests, isEmpty);
  });

  test(
      'outgoing history fits 8 pairs and shared Unicode character budget; refusals and errors stay local',
      () async {
    await ready();
    await notifier().send('  ');
    await notifier().send('🎯' * 1001);
    await notifier().send('本月\u0000支出');
    expect(client().requests, isEmpty);
    for (var index = 0; index < 10; index++) {
      final send = notifier().send('预算$index');
      client().requests.last.answer('净资产$index');
      await send;
    }
    final refused = notifier().send('离题');
    expect(client().requests.last.history, hasLength(16));
    expect(client().requests.last.history.first,
        {'role': 'user', 'content': '预算2'});
    client().requests.last.events.add(const AiChatEvent(AiChatEventType.refused,
        text: '请聊个人理财', reason: 'topic'));
    client().requests.last.events.add(const AiChatEvent(AiChatEventType.done));
    await refused;
    expect(state().messages.last.refusalReason, 'topic');
    final failed = notifier().send('失败');
    expect(client().requests.last.history, hasLength(16));
    expect(client().requests.last.history.last['content'], '净资产9');
    client()
        .requests
        .last
        .events
        .add(const AiChatEvent(AiChatEventType.error, text: '暂时无法回复'));
    await failed;
    expect(state().errorText, '暂时无法回复');
    for (var n = 0; n < 5; n++) {
      final send = notifier().send('🎯' * 1000);
      final history = client().requests.last.history;
      expect(history.expand((m) => m['content']!.runes).length + 1000,
          lessThanOrEqualTo(8000));
      expect(history.every((m) => m['content']!.runes.length <= 1500), isTrue);
      expect(history.map((m) => m['content']), isNot(contains('失败')));
      client().requests.last.answer('🧾' * 2000);
      await send;
    }
  });
}
