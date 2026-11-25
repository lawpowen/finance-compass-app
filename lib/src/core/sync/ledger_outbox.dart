import 'dart:convert';

import 'ledger_outbox_browser_stub.dart'
    if (dart.library.js_interop) 'ledger_outbox_browser_web.dart' as browser;

typedef LedgerPendingWrite = ({
  int baseRevision,
  String operationId,
  Map<String, dynamic> snapshot,
});

/// The head stays unchanged until acknowledged. The latest snapshot can be
/// replaced while the head is being sent.
final class LedgerOutboxState {
  const LedgerOutboxState(
      {required this.head, this.latest, this.rejectedBytes});

  final LedgerPendingWrite head;
  final LedgerPendingWrite? latest;

  /// A definitive HTTP 413 for this head. A proxy may enforce a lower
  /// limit than the application, so don't resend this size after reopening.
  final int? rejectedBytes;

  Map<String, dynamic> get snapshot => latest?.snapshot ?? head.snapshot;
}

final class LedgerOutboxConflict implements Exception {
  const LedgerOutboxConflict();

  @override
  String toString() => '此设备的待同步账本已被其他页面更改。请重新打开账本。';
}

final class LedgerOutboxStorageException implements Exception {
  const LedgerOutboxStorageException([
    this.message = '无法在此设备保存待同步账本，请检查浏览器储存后重试。',
  ]);

  final String message;

  @override
  String toString() => message;
}

abstract interface class LedgerOutboxStore {
  Future<LedgerOutboxState?> read(String accountId, String username);

  /// Replaces the queue only if the stored operation identities still match
  /// [expected]. A null [next] removes the acknowledged queue.
  Future<void> replace(
    String accountId,
    String username,
    LedgerOutboxState? expected,
    LedgerOutboxState? next,
  );
}

LedgerOutboxStore openLedgerOutboxStore() => const _BrowserLedgerOutboxStore();

final class _BrowserLedgerOutboxStore implements LedgerOutboxStore {
  const _BrowserLedgerOutboxStore();

  @override
  Future<LedgerOutboxState?> read(String accountId, String username) async {
    final ({bool conflict, String? payload, String? identity}) result;
    try {
      result = await browser.readOutbox(accountId, username.toLowerCase());
    } catch (_) {
      throw const LedgerOutboxStorageException();
    }
    if (result.conflict) throw const LedgerOutboxConflict();
    if (result.payload == null) return null;
    return _decodeState(result.payload!, result.identity);
  }

  @override
  Future<void> replace(
    String accountId,
    String username,
    LedgerOutboxState? expected,
    LedgerOutboxState? next,
  ) async {
    final bool replaced;
    try {
      replaced = await browser.replaceOutbox(
        accountId,
        username.toLowerCase(),
        _identity(expected),
        _identity(next),
        next == null ? null : _encodeState(next),
      );
    } catch (_) {
      throw const LedgerOutboxStorageException();
    }
    if (!replaced) throw const LedgerOutboxConflict();
  }
}

/// Shares the browser store's replace, ownership and snapshot-copy semantics
/// without depending on a browser runtime.
final class MemoryLedgerOutboxStore implements LedgerOutboxStore {
  final _records =
      <String, ({String username, String identity, String payload})>{};

  @override
  Future<LedgerOutboxState?> read(String accountId, String username) async {
    final stored = _records[accountId];
    if (stored == null) return null;
    if (stored.username != username.toLowerCase()) {
      throw const LedgerOutboxConflict();
    }
    return _decodeState(stored.payload, stored.identity);
  }

  @override
  Future<void> replace(
    String accountId,
    String username,
    LedgerOutboxState? expected,
    LedgerOutboxState? next,
  ) async {
    final owner = username.toLowerCase();
    final stored = _records[accountId];
    if ((stored != null && stored.username != owner) ||
        stored?.identity != _identity(expected)) {
      throw const LedgerOutboxConflict();
    }
    if (next == null) {
      _records.remove(accountId);
    } else {
      _records[accountId] = (
        username: owner,
        identity: _identity(next)!,
        payload: _encodeState(next),
      );
    }
  }
}

String? _identity(LedgerOutboxState? state) {
  if (state == null) return null;
  return jsonEncode([
    state.head.baseRevision,
    state.head.operationId,
    state.latest?.baseRevision,
    state.latest?.operationId,
    if (state.rejectedBytes != null) state.rejectedBytes,
  ]);
}

String _encodeState(LedgerOutboxState state) => jsonEncode({
      'version': 1,
      'head': ledgerWriteEnvelope(state.head),
      if (state.latest case final latest?)
        'latest': ledgerWriteEnvelope(latest),
      if (state.rejectedBytes != null) 'rejectedBytes': state.rejectedBytes,
    });

Map<String, dynamic> ledgerWriteEnvelope(LedgerPendingWrite write) => {
      'baseRevision': write.baseRevision,
      'operationId': write.operationId,
      'snapshot': write.snapshot,
    };

LedgerOutboxState _decodeState(String raw, String? identity) {
  const invalidState = LedgerOutboxStorageException('无法读取此设备的待同步账本。');
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw invalidState;
    }
    final latest = json['latest'];
    final rejected = json['rejectedBytes'];
    if (rejected != null && (rejected is! int || rejected < 1)) {
      throw invalidState;
    }
    final state = LedgerOutboxState(
      head: _decodeWrite(json['head']),
      latest: latest == null ? null : _decodeWrite(latest),
      rejectedBytes: rejected as int?,
    );
    if (_identity(state) != identity ||
        state.head.operationId == state.latest?.operationId) {
      throw invalidState;
    }
    return state;
  } on FormatException {
    throw invalidState;
  }
}

LedgerPendingWrite _decodeWrite(Object? value) {
  if (value
      case {
        'baseRevision': final int baseRevision,
        'operationId': final String operationId,
        'snapshot': final Map<String, dynamic> snapshot,
      } when baseRevision >= 0 && operationId.isNotEmpty) {
    return (
      baseRevision: baseRevision,
      operationId: operationId,
      snapshot: snapshot,
    );
  }
  throw const LedgerOutboxStorageException('无法读取此设备的待同步更改。');
}
