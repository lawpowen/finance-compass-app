import 'package:finance_app/src/core/sync/ledger_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPendingWrite _write(int revision, String operationId, String note) => (
      baseRevision: revision,
      operationId: operationId,
      snapshot: {
        'transactions': [
          {'note': note},
        ],
      },
    );

void main() {
  test('outbox state retains both snapshots and isolates their serializations',
      () async {
    final store = MemoryLedgerOutboxStore();
    final first = _write(7, 'first', '帳本草稿');
    final latest = _write(7, 'latest', '下一筆');
    final state = LedgerOutboxState(head: first, latest: latest);
    await store.replace('1', 'Owner', null, state);
    latest.snapshot.clear();

    final read = (await store.read('1', 'owner'))!;
    expect(read.head.operationId, 'first');
    expect(read.latest!.operationId, 'latest');
    expect(read.snapshot['transactions'], [
      {'note': '下一筆'},
    ]);
    read.head.snapshot.clear();
    expect((await store.read('1', 'owner'))!.head.snapshot['transactions'], [
      {'note': '帳本草稿'},
    ]);
  });

  test('stale tabs cannot replace or clear a newer queue', () async {
    final store = MemoryLedgerOutboxStore();
    final first = LedgerOutboxState(head: _write(4, 'first', 'first'));
    await store.replace('1', 'owner', null, first);
    final readFromOtherTab = await store.read('1', 'owner');

    final latest =
        LedgerOutboxState(head: first.head, latest: _write(4, 'second', 'new'));
    await store.replace('1', 'owner', first, latest);
    await expectLater(
      store.replace('1', 'owner', readFromOtherTab, first),
      throwsA(isA<LedgerOutboxConflict>()),
    );
    await expectLater(
      store.replace('1', 'owner', readFromOtherTab, null),
      throwsA(isA<LedgerOutboxConflict>()),
    );
    expect((await store.read('1', 'owner'))!.latest!.operationId, 'second');

    final promoted = LedgerOutboxState(head: _write(5, 'second', 'new'));
    await store.replace('1', 'owner', latest, promoted);
    await store.replace('1', 'owner', promoted, null);
    expect(await store.read('1', 'owner'), isNull);
  });

  test('account mismatches cannot read or remove a retained queue', () async {
    final store = MemoryLedgerOutboxStore();
    final first = LedgerOutboxState(head: _write(0, 'first', 'private'));
    await store.replace('1', 'owner', null, first);

    expect(await store.read('2', 'different'), isNull);
    await expectLater(
      store.read('1', 'different'),
      throwsA(isA<LedgerOutboxConflict>()),
    );
    await expectLater(
      store.replace('1', 'different', first, null),
      throwsA(isA<LedgerOutboxConflict>()),
    );
    expect((await store.read('1', 'OWNER'))!.head.operationId, 'first');
  });
}
