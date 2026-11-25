import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = '${creditCardPostingMetaPrefix}transactions';
const _accounts = [
  Account(
      id: 'card',
      name: 'UOB',
      currency: 'MYR',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currentBalance: 0),
  Account(
      id: 'cash',
      name: 'Bank',
      currency: 'MYR',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currentBalance: 1000),
];

FinanceTransaction _entry(String id,
        {DateTime? posting, String from = 'card', bool transfer = false}) =>
    FinanceTransaction(
        id: id,
        accountId: from,
        type: transfer ? TransactionType.transfer : TransactionType.expense,
        amount: 20,
        currency: 'MYR',
        transactionDate: DateTime(2026, 11, 25, 23, 59),
        cardPostingDate: posting,
        toAccountId: transfer ? 'cash' : null,
        toCurrency: transfer ? 'MYR' : null,
        toAmount: transfer ? 0 : null);

void main() {
  test('posting dates are strict wire days and local calendar dates in memory',
      () {
    expect(parseCardPostingDate(null), isNull);
    expect(parseCardPostingDate('2024-02-29'), DateTime(2024, 2, 29));
    expect(formatCardPostingDate(DateTime(2026, 1, 2, 22)), '2026-01-02');
    for (final invalid in [
      '2026-02-29',
      '2026-02-30',
      '2026-04-31',
      '2026-13-01',
      '2026-11-00',
      '2026-1-02',
      ' 2026-11-25',
      '2026-11-25\n',
      '2026-11-25T00:00:00Z',
      20261125
    ]) {
      expect(() => parseCardPostingDate(invalid), throwsFormatException,
          reason: '$invalid');
    }
    final tx =
        _entry('x', posting: DateTime.utc(2026, 11, 26, 23), transfer: true);
    expect(tx.cardPostingDate, DateTime(2026, 11, 26));
    expect(tx.canonicalOrdinaryTransfer().cardPostingDate, tx.cardPostingDate);
  });

  group('ledger writes', () {
    late AppDatabase db;
    Future<void> seed(List<FinanceTransaction> rows,
            {Map<String, String>? meta}) =>
        db.replaceAllWithSeedData(
            accountItems: _accounts,
            categoryItems: [],
            budgetItems: [],
            transactionItems: rows,
            snapshotItems: [],
            metaValues: meta);
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await seed([]);
    });

    test(
        'v9 calendar day sidecar follows insertion, edits, deletion and id reuse',
        () async {
      expect(db.schemaVersion, 9);
      final sameDay = DateTime(2026, 11, 25);
      final nextDay = DateTime(2026, 11, 26);
      await db.insertTransactions([
        _entry('a', posting: sameDay, transfer: true),
        _entry('b'),
        _entry('c', posting: nextDay)
      ]);
      expect(jsonDecode((await db.getMetaValue(_key))!),
          {'a': '2026-11-25', 'c': '2026-11-26'});
      final transfer =
          (await db.fetchTransactions()).singleWhere((t) => t.id == 'a');
      expect(transfer.cardPostingDate, sameDay);
      expect(transfer.toAmount, isNull);
      await db.updateTransaction(_entry('a', posting: nextDay));
      expect(
          (await db.fetchTransactions())
              .singleWhere((t) => t.id == 'a')
              .cardPostingDate,
          nextDay);
      await db.updateTransaction(_entry('a', from: 'cash'));
      expect(
          (await db.fetchTransactions())
              .singleWhere((t) => t.id == 'a')
              .cardPostingDate,
          isNull);
      await db.deleteTransaction('c');
      expect(await db.getMetaValue(_key), isNull);
      await db.insertTransaction(_entry('c'));
      expect(
          (await db.fetchTransactions())
              .singleWhere((t) => t.id == 'c')
              .cardPostingDate,
          isNull);
    });

    test(
        'invalid updates, bulk replacements and imports roll back rows, balances and sidecar',
        () async {
      final original = _entry('one', posting: DateTime(2026, 11, 26));
      await db.insertTransaction(original);
      for (final invalid in [
        _entry('one', posting: DateTime(2026, 11, 24)),
        _entry('one', from: 'cash', posting: DateTime(2026, 11, 26))
      ]) {
        await expectLater(db.updateTransaction(invalid), throwsFormatException);
        await expectLater(
            db.replaceTransactions(
                deleteIds: ['one'], insertItems: [_entry('two'), invalid]),
            throwsFormatException);
        await expectLater(seed([invalid]), throwsFormatException);
        final tx = (await db.fetchTransactions()).single;
        expect((tx.id, tx.accountId, tx.cardPostingDate),
            ('one', 'card', original.cardPostingDate));
        expect(
            (await db.fetchAccounts())
                .singleWhere((a) => a.id == 'card')
                .currentBalance,
            -20);
        expect(
            (await db.fetchAccounts())
                .singleWhere((a) => a.id == 'cash')
                .currentBalance,
            1000);
      }
    });

    test(
        'whole-ledger restore derives the index from rows and clears obsolete internal keys',
        () async {
      await seed([_entry('old', posting: DateTime(2026, 11, 26))]);
      await seed([
        _entry('new', posting: DateTime(2026, 12, 1))
      ], meta: {
        _key: '{"old":"2026-11-26"}',
        '${creditCardPostingMetaPrefix}bad': 'ignored',
      });
      expect(jsonDecode((await db.getMetaValue(_key))!), {'new': '2026-12-01'});
      expect(
          await db.getMetaValue('${creditCardPostingMetaPrefix}bad'), isNull);
      await seed([_entry('new')]);
      expect(await db.getMetaValue(_key), isNull);
    });
  });

  test('a v9 file preserves seed posting dates across close and reopen',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('finance-posting-v9-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('ledger.sqlite'));
    final writer = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await writer.seedAll(
          accountItems: _accounts,
          categoryItems: [],
          budgetItems: [],
          transactionItems: [_entry('seeded', posting: DateTime(2026, 11, 26))],
          snapshotItems: []);
    } finally {
      await writer.close();
    }
    final reader = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reader.close);
    final restored = (await reader.fetchTransactions()).single;
    expect(restored.cardPostingDate, DateTime(2026, 11, 26));
    expect(restored.transactionDate, DateTime(2026, 11, 25, 23, 59));
    await reader.clearAllUserData();
    expect(await reader.getMetaValue(_key), isNull);
  });
}
