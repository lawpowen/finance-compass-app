import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening capital, refund, withdrawals and self-transfer use signed legs',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    for (final account in [
      const Account(
          id: 'fund',
          name: '投资',
          accountType: AccountType.trading,
          reportGroup: ReportGroup.investment,
          currency: 'MYR',
          initialBalance: 100,
          currentBalance: 100),
      const Account(
          id: 'bank',
          name: '银行',
          accountType: AccountType.bankSaving,
          reportGroup: ReportGroup.cash,
          currency: 'MYR',
          currentBalance: 0),
    ]) {
      repo = await repo.addAccount(account);
    }
    final date = DateTime(2026, 1, 8);
    final opening = repo.investmentValuationAt('fund', date);
    expect(opening.marketValue, 100);
    expect(opening.cumulativeCost, 100);
    expect(opening.netInvestment, 100);
    expect(opening.gain, 0);
    repo = await repo.addTransactions([
      FinanceTransaction(
          id: 'income',
          type: TransactionType.income,
          accountId: 'fund',
          amount: 60,
          currency: 'MYR',
          transactionDate: date),
      FinanceTransaction(
          id: 'withdraw',
          type: TransactionType.transfer,
          accountId: 'fund',
          toAccountId: 'bank',
          amount: 130,
          currency: 'MYR',
          transactionDate: date),
    ]);
    // Some old exports contain both legs in one account. They net to zero and
    // must not inflate gross capital. New forms need not offer this operation.
    final self = FinanceTransaction(
        id: 'self',
        type: TransactionType.transfer,
        accountId: 'fund',
        toAccountId: 'fund',
        amount: 80,
        currency: 'MYR',
        transactionDate: date);
    expect(repo.transactionDeltaForAccount('fund', self), 0);
    final unequalLegs = FinanceTransaction(
      id: 'legacy-self',
      type: TransactionType.transfer,
      accountId: 'fund',
      toAccountId: 'fund',
      amount: 80,
      toAmount: 75,
      currency: 'MYR',
      transactionDate: date,
    );
    expect(repo.transactionDeltaForAccount('fund', unequalLegs), -5);
    final value = repo.investmentValuationAt('fund', date);
    expect(repo.snapshotsForAccount('fund'), isEmpty);
    expect(value.marketValue, 30);
    expect(value.cashBalance, 30);
    expect(value.cumulativeCost, 100);
    expect(value.netInvestment, -30);
    expect(value.gain, 60);
    expect(value.returnRatio, isNull);
    expect(repo.accountBalanceTrace('fund', date).endingBalance,
        value.marketValue);
  });

  test(
      'a draft observation uses its own point and the first cost by date and ID',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(const Account(
        id: 'fund',
        name: '投资',
        accountType: AccountType.trading,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        initialBalance: 50,
        currentBalance: 50));
    final date = DateTime(2026, 2, 1);
    final b = AssetSnapshot(
        id: 'b',
        accountId: 'fund',
        snapshotDate: date,
        marketValue: 120,
        cashBalance: 25,
        costBasis: 90);
    final a = AssetSnapshot(
        id: 'a',
        accountId: 'fund',
        snapshotDate: date,
        marketValue: 100,
        cashBalance: 10,
        costBasis: 80);
    repo = await repo.addAssetSnapshot(b);
    expect(repo.snapshotSetsCostBaseline(a), isTrue);
    repo = await repo.addAssetSnapshot(a);
    expect(repo.snapshotSetsCostBaseline(b), isFalse);
    expect(repo.accountBalanceAt('fund', date), 120);
    expect(repo.snapshotValuation(b).cumulativeCost, 80);
    expect(repo.snapshotValuation(b).gain, 40);
    expect(repo.snapshotValuation(a).marketValue, 100);
    expect(repo.snapshotValuation(a).cashBalance, 10);
    expect(repo.snapshotValuation(a).gain, 20);
    expect(repo.snapshotValuation(a).returnRatio, .25);
    final earlier = DateTime(2026, 1);
    expect(repo.suggestedSnapshotBaseline('fund', earlier), 50);
    expect(repo.investmentValuationAt('fund', earlier).cumulativeCost, 50);
  });

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

    expect(repository.firstSnapshotForAccount('investment')!.costBasis, 800);
    expect(
        repository.remainingCostBasisForAccount('investment',
            upToDate: DateTime(2026, 1, 31)),
        800);
  });
}
