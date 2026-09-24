import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('withdrawal reduces remaining cost without creating a false loss',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(const Account(
      id: 'investment',
      name: '投资',
      accountType: AccountType.trading,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      currentBalance: 0,
    ));
    repository = await repository.addAccount(const Account(
      id: 'cash',
      name: '现金',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 0,
    ));
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'initial',
      accountId: 'investment',
      snapshotDate: DateTime(2026, 1, 10),
      marketValue: 1100,
      costBasis: 1000,
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'add',
      type: TransactionType.transfer,
      accountId: 'cash',
      toAccountId: 'investment',
      amount: 500,
      currency: 'MYR',
      transactionDate: DateTime(2026, 1, 20),
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'take',
      type: TransactionType.transfer,
      accountId: 'investment',
      toAccountId: 'cash',
      amount: 200,
      currency: 'MYR',
      transactionDate: DateTime(2026, 1, 25),
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'planned-add',
      type: TransactionType.transfer,
      accountId: 'cash',
      toAccountId: 'investment',
      amount: 5000,
      currency: 'MYR',
      transactionDate: DateTime(2026, 1, 26),
      status: TransactionStatus.planned,
    ));

    final cutoff = DateTime(2026, 1, 31);
    expect(
        repository
            .investmentFlowSummaryForAccount('investment', upToDate: cutoff)
            .contribution,
        500);
    expect(
        repository
            .investmentFlowSummaryForAccount('investment', upToDate: cutoff)
            .withdrawal,
        200);
    expect(
        repository.costBasisForAccount('investment', upToDate: cutoff), 1500);
    expect(
        repository.remainingCostBasisForAccount('investment', upToDate: cutoff),
        1300);
    expect(repository.accountBalanceAt('investment', cutoff), 1400);
    expect(
        repository.accountBalanceAt('investment', cutoff) -
            repository.remainingCostBasisForAccount('investment',
                upToDate: cutoff),
        100);
  });

  test('withdrawal included in first snapshot baseline is not subtracted twice',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(const Account(
      id: 'investment',
      name: '投资',
      accountType: AccountType.trading,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      currentBalance: 0,
    ));
    repository = await repository.addAccount(const Account(
      id: 'cash',
      name: '现金',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 0,
    ));
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'initial',
      accountId: 'investment',
      snapshotDate: DateTime(2026, 1, 10),
      marketValue: 900,
      costBasis: 800,
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'earlier-take',
      type: TransactionType.transfer,
      accountId: 'investment',
      toAccountId: 'cash',
      amount: 200,
      currency: 'MYR',
      transactionDate: DateTime(2026, 1, 5),
    ));

    expect(repository.firstSnapshotForAccount('investment')!.costBasis, 600);
    expect(
        repository.remainingCostBasisForAccount('investment',
            upToDate: DateTime(2026, 1, 31)),
        600);
  });
}
