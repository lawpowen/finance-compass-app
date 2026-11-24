import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/finance_repository.dart';
import '../utils/currency_formatter.dart';
import 'ledger_outbox.dart';

final class SyncException implements Exception {
  const SyncException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;

  @override
  String toString() => message;
}

class LedgerSyncApi {
  LedgerSyncApi(this.client, this.origin);

  final http.Client client;
  final Uri origin;

  Future<LedgerRevision> read({String? accountId}) async {
    final response = await _send('GET', 'ledger', accountId: accountId);
    if (response.statusCode != 200) _check(response);
    final payload = _decode(response);
    return (
      accountId: payload['accountId'] as String,
      username: payload['username'] as String,
      revision: payload['revision'] as int,
      snapshot: payload['snapshot'] as Map<String, dynamic>?,
    );
  }

  Future<int> readRevision({required String accountId}) async {
    final response =
        await _send('GET', 'ledger/revision', accountId: accountId);
    if (response.statusCode != 200) _check(response);
    final payload = _decode(response);
    if (payload['accountId'] != accountId) throw _accountChanged;
    return payload['revision'] as int;
  }

  Future<void> login(String username, String password,
      {String? accountId}) async {
    final response = await _send(
      'POST',
      'login',
      accountId: accountId,
      body: {'username': username, 'password': password},
    );
    if (response.statusCode != 204) _check(response);
  }

  Future<void> register(String username, String password) async {
    final response = await _send(
      'POST',
      'register',
      body: {'username': username, 'password': password},
    );
    if (response.statusCode != 204) _check(response);
  }

  Future<void> logout({required String accountId}) async {
    final response = await _send('POST', 'logout', accountId: accountId);
    if (response.statusCode != 204) _check(response);
  }

  Future<int> write({
    required String accountId,
    required int baseRevision,
    required String operationId,
    required Map<String, dynamic> snapshot,
  }) async {
    final response = await _send('PUT', 'ledger', accountId: accountId, body: {
      'baseRevision': baseRevision,
      'operationId': operationId,
      'snapshot': snapshot,
    });
    if (response.statusCode != 200) _check(response);
    return _decode(response)['revision'] as int;
  }

  Map<String, dynamic> _decode(http.Response response) {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<http.Response> _send(
    String method,
    String endpoint, {
    String? accountId,
    Map<String, dynamic>? body,
  }) async {
    try {
      final request =
          http.Request(method, origin.resolve('/api/sync/v1/$endpoint'))
            ..headers['Accept'] = 'application/json';
      if (accountId != null) request.headers['X-Finance-Account'] = accountId;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.bodyBytes = utf8.encode(jsonEncode(body));
      }
      return await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const SyncException('连接超时，请检查网络后重试。');
    } on http.ClientException {
      throw const SyncException('无法连接同步服务，请检查网络后重试。');
    }
  }

  Never _check(http.Response response) {
    final status = response.statusCode;
    String? code;
    try {
      final value = _decode(response)['error'];
      if (value is String) code = value;
    } on FormatException {
      // A reverse proxy can return a non-JSON error page.
    } on TypeError {
      // Only a JSON object can contain the API error code.
    }
    final message = switch (code) {
      'username_taken' => '这个账号名已被使用，请选择其他名称。',
      'account_changed' => _accountChanged.message,
      'invalid_credentials' ||
      'invalid_registration' when status == 400 =>
        '账号名或密码不符合注册要求。',
      'registration_unavailable' => '暂时无法注册新账号，请联系服务管理员。',
      _ => switch (status) {
          401 => '登录失败或会话已过期。',
          403 => '同步服务拒绝了此网址的请求。',
          409 => '其他设备已更新账本，请下载本次更改并刷新。',
          413 => '账本超过服务端允许的大小。',
          429 => '尝试次数过多，请稍后重试。',
          _ => '同步服务暂时无法完成请求（$status）。',
        },
    };
    throw SyncException(message, status: status, code: code);
  }
}

typedef LedgerRevision = ({
  String accountId,
  String username,
  int revision,
  Map<String, dynamic>? snapshot,
});

const _accountChanged = SyncException(
  '其他标签页已切换账号。请重新登录当前账本，或退出后打开另一个账号。',
  status: 409,
  code: 'account_changed',
);

class LedgerSyncSession extends ChangeNotifier {
  LedgerSyncSession(
    this.api,
    LedgerRevision initial, {
    LedgerOutboxStore? outboxStore,
    LedgerOutboxState? restored,
  })  : accountId = initial.accountId,
        username = initial.username,
        _revision = initial.revision,
        _outboxStore = outboxStore ?? MemoryLedgerOutboxStore(),
        _pending = restored;

  final LedgerSyncApi api;
  final String accountId;
  final String username;
  final LedgerOutboxStore _outboxStore;
  int _revision;
  bool _busy = false;
  bool _requiresRefresh = false;
  bool _conflicted = false;
  bool _authenticationExpired = false;
  bool _accountMismatch = false;
  bool _blockedByServer = false;
  bool _sending = false;
  bool _paused = false;
  bool _signedOut = false;
  bool _disposed = false;
  String? _message;
  LedgerOutboxState? _pending;
  FinanceRepository? _localRepository;
  Future<void> _localTail = Future.value();
  Timer? _retryTimer;
  int _retryCount = 0;

  bool get busy => _busy;
  bool get requiresRefresh => _requiresRefresh;
  bool get conflicted => _conflicted;
  bool get authenticationExpired => _authenticationExpired;
  bool get accountMismatch => _accountMismatch;
  bool get hasPending => _pending != null;
  bool get needsRecovery =>
      _requiresRefresh ||
      _conflicted ||
      _authenticationExpired ||
      _blockedByServer;
  String? get message => _message;
  int get revision => _revision;

  bool get _canDrain =>
      !_disposed && !_signedOut && !_paused && !needsRecovery && hasPending;

  Future<FinanceRepository?> mutate(
    FinanceRepository repository,
    Future<FinanceRepository?> Function(FinanceRepository) action, {
    void Function(FinanceRepository)? onLocalCommit,
  }) =>
      _serializeLocal(() => _foreground(() async {
            if (needsRecovery) {
              throw const SyncException('请先处理尚未同步的账本更改。');
            }
            final current = _localRepository ?? repository;
            final previous = _pending;
            LedgerOutboxState? persisted;
            final FinanceRepository? updated;
            try {
              updated = await current.database.transaction(() async {
                final result = await action(current);
                if (result == null) return null;
                final snapshot = await result.buildJsonSnapshotPayload();
                final operation = (
                  baseRevision: _revision,
                  operationId: _newOperationId(),
                  snapshot: snapshot,
                );
                final next = previous == null
                    ? LedgerOutboxState(head: operation)
                    : LedgerOutboxState(head: previous.head, latest: operation);
                await _replace(previous, next);
                persisted = next;
                return result;
              });
            } catch (_) {
              setActiveBaseCurrency(current.baseCurrency);
              if (persisted != null) {
                // The durable snapshot is authoritative if the in-memory
                // database fails while committing its transaction.
                _pending = persisted;
                _requireRefresh('更改已保留，请重新加载账本后继续。');
              }
              rethrow;
            }
            if (updated == null) return null;
            _pending = persisted;
            _localRepository = updated;
            if (!_disposed) onLocalCommit?.call(updated);
            kickBackgroundSync();
            return updated;
          }));

  Future<FinanceRepository> refresh(
    FinanceRepository repository, {
    LedgerRevision? available,
    bool discardPending = false,
    bool Function()? canApply,
    void Function(FinanceRepository)? onLocalCommit,
  }) async {
    _checkActive();
    if (available != null) _checkIdentity(available);
    if (hasPending && !discardPending && !requiresRefresh) {
      kickBackgroundSync(immediate: true);
      return _localRepository ?? repository;
    }
    final previous = _pending;
    if (discardPending && _sending) {
      throw const SyncException('请等当前上传结束后再处理账本。');
    }

    // Fetch outside the local write queue. A slow pull must never block an edit.
    final LedgerRevision remote;
    try {
      remote = available ?? await readRemote();
    } on SyncException catch (error) {
      markAuthenticationExpired(error);
      rethrow;
    }

    return _serializeLocal(() async {
      final current = _localRepository ?? repository;
      if (canApply?.call() == false) return current;
      if (discardPending && (_sending || !identical(previous, _pending))) {
        throw const SyncException('账本状态已更改，请重试。');
      }
      if (!needsRecovery &&
          !discardPending &&
          (hasPending || remote.revision <= _revision)) {
        return current;
      }
      if (hasPending && !discardPending && !requiresRefresh) return current;

      // A CAS change may belong to another browser tab. Load its durable
      // snapshot before replacing this tab's stale in-memory working copy.
      final recovered =
          requiresRefresh ? await _outboxStore.read(accountId, username) : null;
      final snapshot = recovered == null
          ? remote.snapshot
          : (recovered.latest ?? recovered.head).snapshot;
      final FinanceRepository updated;
      try {
        updated = await current.database.transaction(() async {
          final result = await _apply(current, snapshot);
          if (discardPending && !requiresRefresh && previous != null) {
            await _replace(previous, null);
          }
          return result;
        });
      } catch (_) {
        setActiveBaseCurrency(current.baseCurrency);
        rethrow;
      }
      _revision = remote.revision;
      _pending = recovered;
      _requiresRefresh = false;
      _conflicted = false;
      _blockedByServer = false;
      _message = null;
      _retryCount = 0;
      _localRepository = updated;
      if (!_disposed) onLocalCommit?.call(updated);
      _changed();
      kickBackgroundSync(immediate: true);
      return updated;
    });
  }

  Future<FinanceRepository> retry(FinanceRepository repository) async {
    _checkActive();
    _blockedByServer = false;
    if (!needsRecovery) _message = null;
    _changed();
    kickBackgroundSync(immediate: true);
    return _localRepository ?? repository;
  }

  void kickBackgroundSync({bool immediate = false}) {
    if (!_canDrain || _sending) return;
    if (_retryTimer != null && !immediate) return;
    _scheduleDrain(Duration.zero);
  }

  void _scheduleDrain(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (!_canDrain || _sending) return;
    _sending = true;
    Duration? retryAfter;
    try {
      while (_canDrain) {
        final head = _pending!.head;
        final acknowledged = await _submit(head);
        if (_disposed || _signedOut) return;
        await _serializeLocal(() async {
          final previous = _pending;
          if (previous == null ||
              previous.head.operationId != head.operationId) {
            return;
          }
          final tail = previous.latest;
          final next = tail == null
              ? null
              : LedgerOutboxState(head: (
                  baseRevision: acknowledged,
                  operationId: tail.operationId,
                  snapshot: tail.snapshot,
                ));
          await _replace(previous, next);
          // An idempotent retry may acknowledge an older server revision.
          // Advance the tail only against that exact acknowledged version.
          _revision = acknowledged;
          _pending = next;
          _retryCount = 0;
          _message = null;
          _changed();
        });
      }
    } on SyncException catch (error) {
      if (_disposed || _signedOut) return;
      _recordAuthenticationError(error);
      if (!_authenticationExpired && !_requiresRefresh) {
        if (error.status == 409) {
          _conflicted = true;
          _message = '其他设备已更新账本。本机更改已保留，可下载后核对。';
        } else if (_isTransient(error.status)) {
          _message = '本机更改已保存，连接恢复后会继续同步。';
          retryAfter = _nextRetry();
        } else {
          _blockedByServer = true;
          _message = error.message;
        }
      }
    } catch (_) {
      if (!_disposed && !_signedOut && !_requiresRefresh) {
        _message = '本机更改已保留，稍后会重试同步。';
        retryAfter = _nextRetry();
      }
    } finally {
      _sending = false;
      _changed();
      if (_canDrain) _scheduleDrain(retryAfter ?? Duration.zero);
    }
  }

  bool _isTransient(int? status) =>
      status == null || status >= 500 || const {408, 425, 429}.contains(status);

  Duration _nextRetry() {
    final delay = min(60, 2 << min(_retryCount, 5));
    _retryCount += 1;
    return Duration(seconds: delay);
  }

  Future<void> logout({Future<void> Function()? before}) =>
      _serializeLocal(() => _foreground(() async {
            _paused = true;
            _retryTimer?.cancel();
            _retryTimer = null;
            try {
              await before?.call();
              try {
                await api.logout(accountId: accountId);
              } on SyncException catch (error) {
                if (error.code != 'account_changed') rethrow;
              }
              _signedOut = true;
            } finally {
              _paused = false;
              kickBackgroundSync();
            }
          }));

  Future<LedgerRevision> readRemote() async {
    final remote = await api.read(accountId: accountId);
    _checkIdentity(remote);
    return remote;
  }

  void _checkIdentity(LedgerRevision remote) {
    if (remote.accountId != accountId ||
        remote.username.toLowerCase() != username.toLowerCase()) {
      throw _accountChanged;
    }
  }

  void markAuthenticationExpired(SyncException error) {
    _recordAuthenticationError(error);
    _changed();
  }

  void _recordAuthenticationError(SyncException error) {
    if (error.status != 401 && error.code != 'account_changed') return;
    _authenticationExpired = true;
    if (error.code == 'account_changed') {
      _accountMismatch = true;
      _message = error.message;
    }
  }

  Future<void> renewAuthentication(
    String password, {
    Future<void> Function()? beforeResume,
  }) =>
      _serializeLocal(() => _foreground(() async {
            await api.login(username, password, accountId: accountId);
            await readRemote();
            await beforeResume?.call();
            _authenticationExpired = false;
            _accountMismatch = false;
            if (_message == _accountChanged.message) _message = null;
            kickBackgroundSync(immediate: true);
          }));

  Uint8List? pendingBackup() {
    final pending = _pending;
    if (pending == null) return null;
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ')
          .convert((pending.latest ?? pending.head).snapshot)),
    );
  }

  static String _newOperationId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _replace(
      LedgerOutboxState? expected, LedgerOutboxState? next) async {
    try {
      await _outboxStore.replace(accountId, username, expected, next);
    } on LedgerOutboxConflict {
      const message = '这个浏览器的另一标签页已更新账本，请重新加载。';
      _requireRefresh(message);
      throw const SyncException(message);
    } on LedgerOutboxStorageException {
      throw const SyncException('无法保存设备上的待同步更改，请检查浏览器存储后重试。');
    }
  }

  void _requireRefresh(String message) {
    _requiresRefresh = true;
    _message = message;
    _changed();
  }

  Future<int> _submit(LedgerPendingWrite pending) => api.write(
        accountId: accountId,
        baseRevision: pending.baseRevision,
        operationId: pending.operationId,
        snapshot: pending.snapshot,
      );

  Future<FinanceRepository> _apply(
    FinanceRepository repository,
    Map<String, dynamic>? snapshot,
  ) {
    if (snapshot == null) return repository.clearAllData();
    return repository.restoreSyncedSnapshot(snapshot);
  }

  Future<T> _serializeLocal<T>(Future<T> Function() run) {
    final result = _localTail.then((_) {
      _checkActive();
      return run();
    });
    _localTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<T> _foreground<T>(Future<T> Function() run) async {
    _busy = true;
    _changed();
    try {
      return await run();
    } on SyncException catch (error) {
      _recordAuthenticationError(error);
      rethrow;
    } finally {
      _busy = false;
      _changed();
    }
  }

  void _checkActive() {
    if (_disposed || _signedOut) {
      throw const SyncException('这个账本已关闭，请重新打开。');
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
