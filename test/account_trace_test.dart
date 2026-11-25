import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a historical trace lists only actual movements after its own anchor',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(const Account(
      id: 'pension',
      name: '退休',
      accountType: AccountType.pension,
      reportGroup: ReportGroup.retirement,
      currency: 'MYR',
      currentBalance: 0,
    ));
    repo = await repo.addAssetSnapshot(AssetSnapshot(
      id: 'jan',
      accountId: 'pension',
      marketValue: 100,
      snapshotDate: DateTime(2026, 1, 1),
    ));
    repo = await repo.addAssetSnapshot(AssetSnapshot(
      id: 'feb',
      accountId: 'pension',
      marketValue: 180,
      snapshotDate: DateTime(2026, 2, 1),
    ));
    repo = await repo.addTransactions([
      for (final (id, day, amount) in [
        ('b', 10, 7.0),
        ('a', 10, 2.0),
        ('at-anchor', 1, 1.0),
        ('outside', 22, 3.0)
      ])
        FinanceTransaction(
            id: id,
            type: TransactionType.adjustment,
            accountId: 'pension',
            amount: amount,
            currency: 'MYR',
            transactionDate: DateTime(2026, 1, day)),
    ]);
    final cutoff = DateTime(2026, 1, 20);
    final trace = repo.accountBalanceTrace('pension', cutoff);
    expect(trace.sourceAmount, 100);
    expect(trace.entries.map((e) => e.transactionId), ['a', 'b']);
    expect(trace.entries.map((e) => e.runningBalance), [102, 109]);
    expect(trace.endingBalance, 109);
    expect(repo.accountBalanceAt('pension', cutoff), trace.endingBalance);
    expect(repo.accountBalanceAt('pension', DateTime(2026, 3)), 180);
  });

  test('account balance trace matches accountBalanceAt for every account', () {
    final repository = FinanceRepository.preview();
    final cutoffDate = DateTime(2026, 4, 30, 23, 59, 59, 999);

    for (final account in repository.accounts) {
      final trace = repository.accountBalanceTrace(account.id, cutoffDate);
      final balance = repository.accountBalanceAt(account.id, cutoffDate);

      expect(
        trace.endingBalance,
        closeTo(balance, 0.001),
        reason: '${account.name} trace should explain the displayed balance.',
      );
    }
  });
}
