import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/sync/ledger_outbox.dart';
import 'package:finance_app/src/core/sync/ledger_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('an older JSON export with deleted recurring rule history syncs',
      () async {
    var source = await _emptyRepository();
    source = await source.addAccount(_account('cash'));
    source = await source.addTransaction(FinanceTransaction(
      id: 'historic',
      type: TransactionType.expense,
      accountId: 'cash',
      amount: 12,
      currency: 'MYR',
      transactionDate: DateTime(2026, 9, 4),
      recurringRuleId: 'rule-deleted-in-0.10.1',
    ));
    final backup = await source.buildJsonSnapshotPayload();
    expect(backup['format_version'], 3);

    final server = _LedgerServer();
    final first = server.newSession();
    final second = server.newSession();
    final firstLocal = await _emptyRepository();
    final secondLocal = await _emptyRepository();
    await first.mutate(
        firstLocal, (repo) => repo.restoreSyncedSnapshot(backup));
    await _until(() => !first.hasPending);

    final loaded = await second.refresh(secondLocal);
    expect(loaded.accounts.single.currentBalance, 88);
    expect(
        loaded.transactions.single.recurringRuleId, 'rule-deleted-in-0.10.1');
    expect((await firstLocal.refresh()).accounts.single.id, 'cash');
    expect((await source.refresh()).transactions.single.id, 'historic');
    expect(second.revision, 1);
  });

  test('a stalled upload does not block later saves, and the tail coalesces',
      () async {
    final release = Completer<void>();
    final server = _LedgerServer()..holdNextWrite = release;
    final store = MemoryLedgerOutboxStore();
    final session = server.newSession(outboxStore: store);
    final local = await _emptyRepository();

    final first = await session.mutate(
      local,
      (repo) => repo.addAccount(_account('first')),
    );
    await _until(() => server.operationIds.length == 1);
    expect(first!.accounts.single.id, 'first');
    expect(session.busy, isFalse);
    expect(session.needsRecovery, isFalse);
    expect(server.revision, 0);

    final second = session.mutate(local, (repo) async {
      expect(repo.accounts.single.id, 'first');
      return repo.addAccount(_account('second'));
    });
    final third = session.mutate(local, (repo) async {
      expect(repo.accounts.map((item) => item.id), ['first', 'second']);
      return repo.addAccount(_account('third'));
    });
    final results = await Future.wait([second, third]);
    expect(results.last!.accounts.map((item) => item.id),
        ['first', 'second', 'third']);
    final durable = (await store.read('1', 'first'))!;
    expect((durable.head.snapshot['accounts'] as List).length, 1);
    expect((durable.latest!.snapshot['accounts'] as List).length, 3);
    expect(server.operationIds, [durable.head.operationId]);
    release.complete();
    await _until(() => !session.hasPending);
    expect(server.operationIds,
        [durable.head.operationId, durable.latest!.operationId]);
    expect(server.revision, 2);
    expect((server.snapshot!['accounts'] as List).length, 3);
    expect(await store.read('1', 'first'), isNull);
  });

  test(
      'server conflict keeps local changes and explicit discard loads the server',
      () async {
    final server = _LedgerServer();
    final first = server.newSession();
    final second = server.newSession();
    final firstLocal = await _emptyRepository();
    final secondLocal = await _emptyRepository();

    await first.mutate(
        firstLocal, (repo) => repo.addAccount(_account('first')));
    await _until(() => !first.hasPending);
    final saved = await second.mutate(
        secondLocal, (repo) => repo.addAccount(_account('second')));
    expect(saved!.accounts.single.id, 'second');
    await _until(() => second.conflicted);
    expect(second.needsRecovery, isTrue);
    expect((await secondLocal.refresh()).accounts.single.id, 'second');
    expect(utf8.decode(second.pendingBackup()!), contains('"id": "second"'));
    expect((await second.refresh(secondLocal)).accounts.single.id, 'second');

    final refreshed = await second.refresh(secondLocal, discardPending: true);
    expect(refreshed.accounts.single.id, 'first');
    expect(second.pendingBackup(), isNull);
    expect(second.needsRecovery, isFalse);
    expect(server.revision, 1);
  });

  test('a retry after a lost acknowledgement preserves a newer revision',
      () async {
    final server = _LedgerServer()..dropNextAcknowledgement = true;
    final first = server.newSession();
    final second = server.newSession();
    final firstLocal = await _emptyRepository();
    final secondLocal = await _emptyRepository();
    await first.mutate(
        firstLocal, (repo) => repo.addAccount(_account('first')));
    await _until(() => first.message != null);
    final submittedId = server.operationIds.single;
    expect((await firstLocal.refresh()).accounts.single.id, 'first');
    expect(first.hasPending, isTrue);
    expect(first.needsRecovery, isFalse);
    expect(server.revision, 1);

    final refreshed = await second.refresh(secondLocal);
    await second.mutate(
        refreshed, (repo) => repo.addAccount(_account('second')));
    await _until(() => !second.hasPending);
    await first.retry(firstLocal);
    await _until(() => !first.hasPending);

    // The duplicate ACK matches revision 1. The normal pull will subsequently
    // bring in the additional committed edit instead of overwriting it.
    expect(first.revision, 1);
    final reconciled = await first.refresh(firstLocal);
    expect(reconciled.accounts.map((account) => account.id),
        containsAll(['first', 'second']));
    expect(server.operationIds.last, submittedId);
    expect(server.revision, 2);
    expect(first.revision, 2);
  });

  test(
      'a restored tail conflicts rather than overwriting a newer server ledger',
      () async {
    final server = _LedgerServer()..dropNextAcknowledgement = true;
    final store = MemoryLedgerOutboxStore();
    final first = server.newSession(outboxStore: store);
    final firstLocal = await _emptyRepository();
    await first.mutate(
        firstLocal, (repo) => repo.addAccount(_account('first')));
    await _until(() => first.message != null);
    await first.mutate(
        firstLocal, (repo) => repo.addAccount(_account('queued')));
    final durable = (await store.read('1', 'first'))!;
    await first.logout();

    final otherDevice = server.newSession();
    final otherLocal = await _emptyRepository();
    final remote = await otherDevice.refresh(otherLocal);
    await otherDevice.mutate(
        remote, (repo) => repo.addAccount(_account('elsewhere')));
    await _until(() => !otherDevice.hasPending);

    final restored = server.newSession(
      outboxStore: store,
      restored: durable,
      initialRevision: server.revision,
    );
    restored.kickBackgroundSync();
    await _until(() => restored.conflicted);
    expect(server.revision, 2);
    expect(server.operationIds.sublist(2),
        [durable.head.operationId, durable.latest!.operationId]);
    expect(utf8.decode(restored.pendingBackup()!), contains('"id": "queued"'));
    expect(utf8.decode(restored.pendingBackup()!),
        isNot(contains('"id": "elsewhere"')));
  });

  test('a stale pull completing after a local save does not replace it',
      () async {
    final pullGate = Completer<void>();
    final writeGate = Completer<void>();
    final server = _LedgerServer()
      ..holdNextRead = pullGate
      ..holdNextWrite = writeGate;
    final session = server.newSession();
    final local = await _emptyRepository();
    final pull = session.refresh(local);
    await _until(() => server.reads == 1);
    final saved = await session.mutate(
        local, (repo) => repo.addAccount(_account('local')));
    pullGate.complete();
    expect((await pull).accounts.single.id, saved!.accounts.single.id);
    expect(session.hasPending, isTrue);
    writeGate.complete();
    await _until(() => !session.hasPending);
  });

  test('a remote pull is deferred when an editor opens before it completes',
      () async {
    final server = _LedgerServer();
    final other = server.newSession();
    final session = server.newSession();
    final otherLocal = await _emptyRepository();
    final local = await _emptyRepository();
    await other.mutate(
        otherLocal, (repo) => repo.addAccount(_account('remote')));
    await _until(() => !other.hasPending);

    var editorOpen = false;
    final release = Completer<void>();
    server.holdNextRead = release;
    final refresh = session.refresh(local, canApply: () => !editorOpen);
    await _until(() => server.reads == 1);
    editorOpen = true;
    release.complete();
    expect((await refresh).accounts, isEmpty);
    expect(session.revision, 0);
    editorOpen = false;
    expect((await session.refresh(local)).accounts.single.id, 'remote');
  });

  test('another tab cannot overwrite the same durable outbox', () async {
    final hold = Completer<void>();
    final server = _LedgerServer()..holdNextWrite = hold;
    final storage = MemoryLedgerOutboxStore();
    final a = server.newSession(outboxStore: storage);
    final b = server.newSession(outboxStore: storage);
    final localA = await _emptyRepository();
    final localB = await _emptyRepository();
    await a.mutate(localA, (repo) => repo.addAccount(_account('a')));
    await expectLater(
      b.mutate(localB, (repo) => repo.addAccount(_account('b'))),
      throwsA(isA<SyncException>()),
    );
    expect(b.requiresRefresh, isTrue);
    expect((await localB.refresh()).accounts, isEmpty);
    expect((await storage.read('1', 'first'))!.head.snapshot['accounts'],
        contains(predicate((account) => (account as Map)['id'] == 'a')));
    hold.complete();
    await _until(() => !a.hasPending);
    expect((await b.refresh(localB)).accounts.single.id, 'a');
    expect(b.needsRecovery, isFalse);
  });

  test('an account switch blocks writes and keeps the pending draft', () async {
    final server = _LedgerServer();
    final session = server.newSession();
    final local = await _emptyRepository();
    server.activeAccountId = '2';
    await session.mutate(local, (repo) => repo.addAccount(_account('draft')));
    await _until(() => session.accountMismatch);
    expect((await local.refresh()).accounts.single.id, 'draft');
    expect(session.authenticationExpired, isTrue);
    expect(session.needsRecovery, isTrue);
    expect(session.conflicted, isFalse);
    expect(utf8.decode(session.pendingBackup()!), contains('"id": "draft"'));
    await expectLater(
      session.mutate(local, (repo) => repo.addAccount(_account('wrong'))),
      throwsA(isA<SyncException>()),
    );
    await expectLater(
      session.refresh(local, available: (
        accountId: '2',
        username: 'second',
        revision: 4,
        snapshot: null,
      )),
      throwsA(isA<SyncException>()
          .having((error) => error.code, 'code', 'account_changed')),
    );
    expect(server.revision, 0);

    await expectLater(
      session.renewAuthentication(
        'test-password',
        beforeResume: () async => throw StateError('Could not detach old push'),
      ),
      throwsStateError,
    );
    expect(session.authenticationExpired, isTrue);
    expect(session.accountMismatch, isTrue);
    expect(session.hasPending, isTrue);

    await session.renewAuthentication('test-password');
    expect(session.authenticationExpired, isFalse);
    expect(session.accountMismatch, isFalse);
    await _until(() => !session.hasPending);
    expect((await session.refresh(local)).accounts.single.id, 'draft');
  });

  test('registration submits credentials and reports a duplicate username',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/sync/v1/register');
      expect(jsonDecode(request.body), {
        'username': 'new-account',
        'password': 'test-password',
      });
      return requests++ == 0
          ? http.Response('', 204)
          : http.Response('{"error":"username_taken"}', 409);
    });
    addTearDown(client.close);
    final api = LedgerSyncApi(client, Uri.https('finance.local'));
    await api.register('new-account', 'test-password');
    await expectLater(
      api.register('new-account', 'test-password'),
      throwsA(isA<SyncException>()
          .having((error) => error.code, 'code', 'username_taken')),
    );
  });
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The asynchronous synchronization condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<FinanceRepository> _emptyRepository() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return FinanceRepository.load(database);
}

Account _account(String id) => Account(
      id: id,
      name: id,
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    );

class _LedgerServer {
  String activeAccountId = '1';
  int revision = 0;
  Map<String, dynamic>? snapshot;
  bool dropNextAcknowledgement = false;
  Completer<void>? holdNextWrite;
  Completer<void>? holdNextRead;
  int reads = 0;
  final operationIds = <String>[];
  final _savedOperations = <String, int>{};

  LedgerSyncSession newSession({
    LedgerOutboxStore? outboxStore,
    LedgerOutboxState? restored,
    int initialRevision = 0,
  }) {
    final client = MockClient((request) async {
      expect(request.headers['X-Finance-Account'], '1');
      if (request.url.path == '/api/sync/v1/login') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'username': 'first',
          'password': 'test-password',
        });
        activeAccountId = '1';
        return http.Response('', 204);
      }
      if (request.url.path == '/api/sync/v1/logout') {
        return http.Response('', 204);
      }
      expect(request.url.path, '/api/sync/v1/ledger');
      if (activeAccountId != '1') {
        return http.Response('{"error":"account_changed"}', 409);
      }
      if (request.method == 'GET') {
        final reply = jsonEncode({
          'revision': revision,
          'snapshot': snapshot,
          'accountId': '1',
          'username': 'first',
        });
        reads += 1;
        final hold = holdNextRead;
        holdNextRead = null;
        await hold?.future;
        return http.Response(reply, 200);
      }
      expect(request.method, 'PUT');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final operationId = payload['operationId'] as String;
      operationIds.add(operationId);
      final hold = holdNextWrite;
      holdNextWrite = null;
      await hold?.future;
      if (_savedOperations[operationId] case final savedRevision?) {
        return http.Response(jsonEncode({'revision': savedRevision}), 200);
      }
      if (payload['baseRevision'] != revision) return http.Response('', 409);
      snapshot = payload['snapshot'] as Map<String, dynamic>;
      _savedOperations[operationId] = ++revision;
      if (dropNextAcknowledgement) {
        dropNextAcknowledgement = false;
        return http.Response('', 503);
      }
      return http.Response(jsonEncode({'revision': revision}), 200);
    });
    final session = LedgerSyncSession(
      LedgerSyncApi(client, Uri.https('finance.local')),
      (
        accountId: '1',
        username: 'first',
        revision: initialRevision,
        snapshot: null
      ),
      outboxStore: outboxStore,
      restored: restored,
    );
    addTearDown(session.dispose);
    addTearDown(client.close);
    return session;
  }
}
