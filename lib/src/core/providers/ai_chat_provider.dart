import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_chat_client.dart';
import '../sync/ledger_sync.dart';
import 'repository_provider.dart';

enum AiChatAvailability { offline, checking, disabled, ready, unavailable }

enum AiChatRole { user, assistant }

class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.text,
    this.refusalReason,
  });

  final AiChatRole role;
  final String text;
  final String? refusalReason;
}

class AiChatState {
  const AiChatState({
    this.availability = AiChatAvailability.offline,
    this.messages = const [],
    this.generating = false,
    this.statusText,
    this.errorText,
    this.hasPending = false,
    this.revision,
    this.asOf,
  });

  final AiChatAvailability availability;
  final List<AiChatMessage> messages;
  final bool generating;
  final String? statusText;
  final String? errorText;
  final bool hasPending;
  final int? revision;
  final String? asOf;

  AiChatState _update({
    AiChatAvailability? availability,
    List<AiChatMessage>? messages,
    bool? generating,
    String? statusText,
    String? errorText,
    bool clearFeedback = false,
    bool? hasPending,
    int? revision,
    String? asOf,
  }) =>
      AiChatState(
        availability: availability ?? this.availability,
        messages:
            messages == null ? this.messages : List.unmodifiable(messages),
        generating: generating ?? this.generating,
        statusText: statusText ?? (clearFeedback ? null : this.statusText),
        errorText: errorText ?? (clearFeedback ? null : this.errorText),
        hasPending: hasPending ?? this.hasPending,
        revision: revision ?? this.revision,
        asOf: asOf ?? this.asOf,
      );
}

final aiChatClientFactoryProvider = Provider<AiChatClient Function(Uri)>(
  (ref) => (origin) => AiChatClient(baseUri: origin),
);

// Keep history across navigation, scoped to this particular hosted login.
final aiChatProvider = NotifierProvider<AiChatController, AiChatState>(
  AiChatController.new,
  dependencies: [ledgerSyncSessionProvider, aiChatClientFactoryProvider],
);

class AiChatController extends Notifier<AiChatState> {
  LedgerSyncSession? _session;
  AiChatClient? _client;
  _ChatRequest? _active;
  int _statusAttempt = 0;
  bool _expired = false;
  final _completedTurns = <({String question, String answer})>[];

  @override
  AiChatState build() {
    final session = ref.watch(ledgerSyncSessionProvider);
    if (session == null) return const AiChatState();
    final client = ref.watch(aiChatClientFactoryProvider)(session.api.origin);
    _client = client;
    _session = session;
    _expired = session.authenticationExpired || session.accountMismatch;
    session.addListener(_sessionChanged);
    ref.onDispose(() {
      _session = null;
      _client = null;
      _statusAttempt++;
      _finishRequest();
      _completedTurns.clear();
      session.removeListener(_sessionChanged);
      client.close();
    });
    if (_expired) return _expiredState(session);
    scheduleMicrotask(() {
      if (identical(_client, client)) unawaited(retryStatus());
    });
    return AiChatState(
      availability: AiChatAvailability.checking,
      hasPending: session.hasPending,
    );
  }

  static AiChatState _expiredState(LedgerSyncSession session) => AiChatState(
        availability: AiChatAvailability.unavailable,
        errorText:
            session.accountMismatch ? '登录账号已切换，请重新打开账本。' : '登录已过期，请重新登录。',
      );

  void _sessionChanged() {
    final session = _session;
    if (session == null) return;
    if (session.authenticationExpired || session.accountMismatch) {
      if (!_expired) {
        _expired = true;
        _statusAttempt++;
        _finishRequest();
        _completedTurns.clear();
        state = _expiredState(session);
      }
      return;
    }
    if (_expired) {
      _expired = false;
      unawaited(retryStatus());
    }
    if (state.hasPending != session.hasPending) {
      state = state._update(hasPending: session.hasPending);
    }
    if (!session.hasPending || session.needsRecovery) _active?.endSyncWait();
  }

  Future<void> retryStatus() async {
    final session = _session;
    final client = _client;
    if (session == null || client == null || _expired || state.generating) {
      return;
    }
    final attempt = ++_statusAttempt;
    state = state._update(
        availability: AiChatAvailability.checking, clearFeedback: true);
    try {
      final status = await client.status(session.accountId);
      if (attempt != _statusAttempt) return;
      state = state._update(
          availability: status.enabled
              ? AiChatAvailability.ready
              : AiChatAvailability.disabled);
    } catch (error) {
      if (attempt != _statusAttempt || _handleAuthError(error, session)) return;
      state = state._update(
          availability: AiChatAvailability.unavailable,
          errorText: '暂时无法连接理财助手，请重试。');
    }
  }

  bool _handleAuthError(Object error, LedgerSyncSession session) {
    if (error is! AiChatException) return false;
    final status = switch (error.code) {
      'unauthorized' => 401,
      'account_changed' => 409,
      _ => error.statusCode,
    };
    if (status != 401 && status != 409) return false;
    session.markAuthenticationExpired(SyncException(error.message,
        status: status, code: status == 409 ? 'account_changed' : error.code));
    return true;
  }

  Future<void> send(String input) async {
    final session = _session;
    final client = _client;
    if (session == null ||
        client == null ||
        state.availability != AiChatAvailability.ready ||
        _active != null) {
      return;
    }
    final question = input.trim();
    if (question.isEmpty || question.runes.length > 1000) {
      state =
          state._update(errorText: '问题长度需为 1 至 1000 个字符。', clearFeedback: true);
      return;
    }
    if (_invalidControls.hasMatch(question)) {
      state = state._update(errorText: '问题中含有无法发送的控制字符。', clearFeedback: true);
      return;
    }
    final request = _ChatRequest();
    _active = request;
    state = state._update(
      messages: [
        ...state.messages,
        AiChatMessage(role: AiChatRole.user, text: question),
        const AiChatMessage(role: AiChatRole.assistant, text: '')
      ],
      generating: true,
      clearFeedback: true,
      statusText: session.hasPending ? '正在尝试同步待上传记录…' : '正在读取已同步账本…',
    );
    try {
      if (session.hasPending) {
        session.kickBackgroundSync(immediate: true);
        if (session.hasPending &&
            !session.needsRecovery &&
            identical(_active, request)) {
          await request.waitForSync();
        }
      }
      if (!identical(_active, request)) return;
      state = state._update(
          hasPending: session.hasPending, statusText: '正在读取已同步账本…');
      final stream = client.chat(
          accountId: session.accountId,
          message: question,
          history: _historyFor(question));
      final subscription = stream.listen(
        (event) {
          if (!identical(_active, request)) return;
          final last = state.messages.last;
          switch (event.type) {
            case AiChatEventType.status:
              state = state._update(statusText: event.text);
            case AiChatEventType.delta:
              if (last.refusalReason == null) _reply(last.text + event.text);
            case AiChatEventType.refused:
              _reply(event.text, refusalReason: event.reason ?? 'refused');
            case AiChatEventType.done:
              final answer =
                  String.fromCharCodes(last.text.trim().runes.take(1500))
                      .trim();
              if (last.refusalReason == null &&
                  answer.isNotEmpty &&
                  !_invalidControls.hasMatch(answer)) {
                _completedTurns.add((question: question, answer: answer));
                if (_completedTurns.length > 8) _completedTurns.removeAt(0);
              }
              _finishRequest();
              state = state._update(
                  generating: false,
                  clearFeedback: true,
                  revision: event.revision,
                  asOf: event.asOf);
            case AiChatEventType.error:
              if (!_handleAuthError(
                  AiChatException(event.code ?? '', event.text), session)) {
                _fail(event.text);
              }
          }
        },
        onError: (Object error) {
          if (!identical(_active, request) ||
              _handleAuthError(error, session)) {
            return;
          }
          _fail(error is AiChatException ? error.message : '连接中断，请重新提问。');
        },
        onDone: () {
          if (identical(_active, request)) _fail('回复传输中断，请重新提问。');
        },
      );
      if (identical(_active, request)) {
        request.subscription = subscription;
      } else {
        unawaited(subscription.cancel());
      }
      await request.finished.future;
    } catch (error) {
      if (!identical(_active, request) || _handleAuthError(error, session)) {
        return;
      }
      _fail(error is AiChatException ? error.message : '连接中断，请重新提问。');
    }
  }

  static final _invalidControls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  // Include only intact, successful pairs and reserve room for the new question.
  List<Map<String, String>> _historyFor(String question) {
    var remaining = 8000 - question.runes.length;
    final turns = <({String question, String answer})>[];
    for (final turn in _completedTurns.reversed) {
      final length = turn.question.runes.length + turn.answer.runes.length;
      if (length > remaining) break;
      remaining -= length;
      turns.add(turn);
    }
    return [
      for (final turn in turns.reversed) ...[
        {'role': 'user', 'content': turn.question},
        {'role': 'assistant', 'content': turn.answer},
      ],
    ];
  }

  void _reply(String text, {String? refusalReason}) {
    final messages = [...state.messages];
    messages.last = AiChatMessage(
        role: AiChatRole.assistant, text: text, refusalReason: refusalReason);
    state = state._update(messages: messages, clearFeedback: true);
  }

  void _finishRequest() {
    final request = _active;
    _active = null;
    if (request == null) return;
    request.endSyncWait();
    unawaited(request.subscription?.cancel());
    request.finished.complete();
  }

  void _fail(String message) {
    _finishRequest();
    state = state._update(
        generating: false, clearFeedback: true, errorText: message);
  }

  void stop() {
    if (_active == null) return;
    _finishRequest();
    state = state._update(
        generating: false, clearFeedback: true, statusText: '已停止生成');
  }

  void clear() {
    _finishRequest();
    _completedTurns.clear();
    state = AiChatState(
        availability: state.availability,
        hasPending: state.hasPending,
        errorText: state.availability == AiChatAvailability.unavailable
            ? state.errorText
            : null);
  }
}

class _ChatRequest {
  final finished = Completer<void>();
  StreamSubscription<AiChatEvent>? subscription;
  Completer<void>? _syncWait;
  Timer? _deadline;

  Future<void> waitForSync() {
    final wait = _syncWait = Completer<void>();
    _deadline = Timer(const Duration(seconds: 1), endSyncWait);
    return wait.future;
  }

  void endSyncWait() {
    _deadline?.cancel();
    _syncWait?.complete();
    _syncWait = null;
  }
}
