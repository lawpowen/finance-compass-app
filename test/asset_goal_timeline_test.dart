import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/account_valuation.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingDatabase extends AppDatabase {
  _CountingDatabase() : super.forTesting(NativeDatabase.memory());

  int accountReads = 0;
  int goalWrites = 0;

  void resetCounts() {
    accountReads = 0;
    goalWrites = 0;
  }

  @override
  Future<List<Account>> fetchAccounts() {
    accountReads++;
    return super.fetchAccounts();
  }

  @override
  Future<void> setMetaValue(String key, String value) {
    if (key.startsWith('asset_goal')) goalWrites++;
    return super.setMetaValue(key, value);
  }

  @override
  Future<void> deleteMetaValue(String key) {
    if (key.startsWith('asset_goal')) goalWrites++;
    return super.deleteMetaValue(key);
  }
}

void main() {
  test(
      'one immutable sweep matches independent account projections and exact cutoffs',
      () {
    final accounts = [
      for (var i = 0; i < 24; i++)
        Account(
            id: 'cash$i',
            name: 'Bank $i',
            accountType: AccountType.cash,
            reportGroup: ReportGroup.cash,
            currency: i.isEven ? 'MYR' : 'USD',
            initialBalance: 100,
            currentBalance: 1000),
      const Account(
          id: 'fund',
          name: 'Fund',
          accountType: AccountType.fund,
          reportGroup: ReportGroup.investment,
          currency: 'USD',
          initialBalance: 500,
          currentBalance: 0),
      const Account(
          id: 'card',
          name: 'Card',
          accountType: AccountType.creditCard,
          reportGroup: ReportGroup.credit,
          currency: 'MYR',
          currentBalance: -10000),
    ];
    final first = DateTime(2020, 1, 1);
    DateTime at(int day, int hour) =>
        DateTime(first.year, first.month, first.day + day, hour);
    final entries = [
      for (var i = 0; i < 24; i++)
        for (var d = 0; d < 60; d++)
          FinanceTransaction(
              id: '${i}_$d',
              type: TransactionType.income,
              accountId: 'cash$i',
              amount: (d % 10) + 1.0,
              currency: accounts[i].currency,
              transactionDate: at(d, 12),
              status: d % 3 == 0
                  ? TransactionStatus.planned
                  : TransactionStatus.settled),
      FinanceTransaction(
          id: 'transfer',
          type: TransactionType.transfer,
          accountId: 'cash0',
          toAccountId: 'fund',
          amount: 40,
          toAmount: 10,
          currency: 'MYR',
          toCurrency: 'USD',
          transactionDate: at(30, 12)),
      FinanceTransaction(
          id: 'self',
          type: TransactionType.transfer,
          accountId: 'cash1',
          toAccountId: 'cash1',
          amount: 75,
          currency: 'USD',
          transactionDate: at(25, 12)),
      FinanceTransaction(
          id: 'spike',
          type: TransactionType.adjustment,
          accountId: 'fund',
          amount: 100000,
          currency: 'USD',
          transactionDate: at(8, 10)),
      FinanceTransaction(
          id: 'reverse',
          type: TransactionType.adjustment,
          accountId: 'fund',
          amount: -100000,
          currency: 'USD',
          transactionDate: at(8, 13)),
    ];
    final snapshots = [
      for (final (id, value) in [('z', 750.0), ('a', 800.0)])
        AssetSnapshot(
            id: id,
            accountId: 'fund',
            snapshotDate: at(30, 12),
            marketValue: value),
      AssetSnapshot(
          id: 'last',
          accountId: 'fund',
          snapshotDate: at(40, 16),
          marketValue: 7000),
    ];
    final book = AccountValuationBook(accounts, entries, snapshots);
    double toBase(double value, String code) => value * (code == 'USD' ? 4 : 1);
    var conversions = 0;
    final timeline = book.goalTimeline((v, code) {
      conversions++;
      return toBase(v, code);
    });
    final buildConversions = conversions;
    expect(
        buildConversions,
        lessThanOrEqualTo(
            accounts.length + entries.length + snapshots.length + 1));
    double reference(DateTime cutoff) =>
        accounts.where((a) => a.accountType != AccountType.creditCard).fold(
            0.0,
            (sum, a) =>
                sum +
                toBase(book.projection(a.id, cutoff).balance, a.currency));
    final initial = reference(first.subtract(const Duration(microseconds: 1)));
    final targets = [
      initial - 1,
      initial + 1,
      reference(at(35, 23)) + 1,
      200000.0
    ];
    final reached = <double, DateTime>{};
    for (var d = 0; d <= 62; d++) {
      for (final h in [0, 11, 12, 23]) {
        final cutoff = at(d, h);
        final expected = reference(cutoff);
        expect(timeline.valueAt(cutoff), expected, reason: 'cutoff $cutoff');
        for (final target in targets) {
          final day = at(d, 0);
          final crossing = target <= initial
              ? null
              : reached[target] ?? (expected >= target ? day : null);
          expect(timeline.firstReached(target, cutoff), crossing);
          expect(timeline.firstReached(target, cutoff.toUtc()), crossing);
          if (h == 23 && crossing != null) reached[target] = crossing;
        }
      }
    }
    expect(conversions, buildConversions,
        reason: 'Historical queries reuse the indexed ledger revision');
  });

  test(
      'each ordinary write loads the finance rows once and changes only dirty goal metadata',
      () async {
    final db = _CountingDatabase();
    addTearDown(db.close);
    var ledger = await FinanceRepository.load(db);
    ledger = await ledger.addAccount(const Account(
        id: 'cash',
        name: 'Bank',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 0));
    FinanceTransaction receipt(String id, double amount) => FinanceTransaction(
        id: id,
        type: TransactionType.income,
        accountId: 'cash',
        amount: amount,
        currency: 'MYR',
        transactionDate: DateTime(2020, 1, 1, 12));
    db.resetCounts();
    ledger = await ledger.addTransaction(receipt('seed', 1));
    expect((db.accountReads, db.goalWrites), (1, 0));
    ledger = await ledger.addAssetGoal(name: 'Target', amount: 100);
    db.resetCounts();
    ledger = await ledger.addTransaction(receipt('cross', 110));
    expect((db.accountReads, db.goalWrites), (1, 1));
    expect(ledger.assetGoals.single.reachedAt, DateTime(2020, 1, 1));
    db.resetCounts();
    ledger = await ledger.addTransaction(receipt('later', 1));
    expect((db.accountReads, db.goalWrites), (1, 0));
    db.resetCounts();
    ledger = await ledger.deleteExistingTransaction('cross');
    expect((db.accountReads, db.goalWrites), (1, 1));
    expect(ledger.assetGoals.single.reachedAt, isNull);
  });
}
