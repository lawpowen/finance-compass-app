import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/services/asset_service.dart';
import 'package:finance_app/src/core/services/currency_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Noon of the day [offset] days from today, so each event lands on a single
/// calendar day regardless of when the test runs.
DateTime _at(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset, 12);
}

DateTime _day(int offset) {
  final date = _at(offset);
  return DateTime(date.year, date.month, date.day);
}

Future<(AppDatabase, FinanceRepository)> _openRepository({
  double cashBalance = 0,
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  var repository = await FinanceRepository.load(database);
  repository = await repository.addAccount(Account(
    id: 'cash',
    name: '现金',
    accountType: AccountType.bankSaving,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    initialBalance: cashBalance,
    currentBalance: cashBalance,
  ));
  return (database, repository);
}

FinanceTransaction _income(
  String id,
  int dayOffset,
  double amount, {
  TransactionStatus status = TransactionStatus.actual,
}) {
  return FinanceTransaction(
    id: id,
    type: TransactionType.income,
    accountId: 'cash',
    amount: amount,
    currency: 'MYR',
    transactionDate: _at(dayOffset),
    status: status,
  );
}

FinanceTransaction _expense(String id, int dayOffset, double amount) {
  return FinanceTransaction(
    id: id,
    type: TransactionType.expense,
    accountId: 'cash',
    amount: amount,
    currency: 'MYR',
    transactionDate: _at(dayOffset),
  );
}

AssetGoalProgressSummary _summaryFor(
  FinanceRepository repository,
  double targetAmount, {
  DateTime? cutoffDate,
}) {
  return repository
      .assetGoalSummaries(cutoffDate: cutoffDate)
      .firstWhere((item) => item.goal.targetAmount == targetAmount);
}

void main() {
  test('reached date is the real day the total crossed, not a month end',
      () async {
    final (_, initialRepository) = await _openRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(_income('a', -20, 600));
    repository = await repository.addTransaction(_income('b', -10, 500));
    repository = await repository.addTransaction(_expense('c', -5, 700));
    repository = await repository.addAssetGoal(name: '1000', amount: 1000);

    final summary = _summaryFor(repository, 1000);
    // Crossed on day -10 (1100) and fell back to 400 afterwards.
    expect(summary.reachedAt, _day(-10));
    expect(summary.isReached, isFalse);
    expect(repository.assetGoals.single.reachedAt, _day(-10));

    // Progress and history are measured at the end of today.
    final cutoff = repository.assetGoalCutoffDate();
    expect(summary.currentAssets,
        repository.totalAssetsAt(cutoff, includeCredit: false));
    expect(
      summary.history.map((point) => point.totalAssets),
      repository
          .totalAssetHistory(cutoffDate: cutoff, includeCredit: false)
          .map((point) => point.totalAssets),
    );

    // A cutoff before the crossing day cannot see it.
    final earlyCutoff = DateTime(
        _day(-11).year, _day(-11).month, _day(-11).day, 23, 59, 59, 999);
    expect(
        _summaryFor(repository, 1000, cutoffDate: earlyCutoff).reachedAt, null);
  });

  test('snapshot dates count as crossing days', () async {
    final (_, initialRepository) = await _openRepository();
    var repository = await initialRepository.addAccount(const Account(
      id: 'fund',
      name: '基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
    repository = await repository.addTransaction(_income('a', -15, 50));
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'snap',
      accountId: 'fund',
      snapshotDate: _at(-7),
      marketValue: 2000,
      costBasis: 100,
    ));
    repository = await repository.addAssetGoal(name: '1500', amount: 1500);

    expect(_summaryFor(repository, 1500).reachedAt, _day(-7));
  });

  test('planned and future actual transactions do not bring the date forward',
      () async {
    final (_, initialRepository) = await _openRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(_income('now', -3, 500));
    repository = await repository.addTransaction(
      _income('plan', -2, 5000, status: TransactionStatus.planned),
    );
    repository = await repository.addTransaction(_income('future', 1, 5000));
    repository = await repository.addAssetGoal(name: '400', amount: 400);
    repository = await repository.addAssetGoal(name: '1000', amount: 1000);

    expect(_summaryFor(repository, 400).reachedAt, _day(-3));
    expect(_summaryFor(repository, 1000).reachedAt, isNull);
    final stored = {
      for (final goal in repository.assetGoals) goal.targetAmount: goal
    };
    expect(stored[400]!.reachedAt, _day(-3));
    expect(stored[1000]!.reachedAt, isNull);
  });

  test('goal met by the opening balance gets no fabricated date', () async {
    final (_, emptyLedger) = await _openRepository(cashBalance: 5000);
    var repository = await emptyLedger.addAssetGoal(name: '1000', amount: 1000);
    var summary = _summaryFor(repository, 1000);
    expect(summary.isReached, isTrue);
    expect(summary.reachedAt, isNull);

    repository = await repository.addTransaction(_expense('spend', -5, 100));
    summary = _summaryFor(repository, 1000);
    expect(summary.isReached, isTrue);
    expect(summary.reachedAt, isNull);
    expect(repository.assetGoals.single.reachedAt, isNull);
  });

  test('stored dates are recomputed from the current ledger', () async {
    final (database, initialRepository) = await _openRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(_income('big', -10, 1200));
    repository = await repository.addTransaction(_income('small', -3, 100));
    repository = await repository.addAssetGoal(name: '1000', amount: 1000);
    expect(repository.assetGoals.single.reachedAt, _day(-10));

    // A stale stored value is neither shown nor kept.
    repository = await repository.updateAssetGoal(
      repository.assetGoals.single.copyWith(reachedAt: DateTime(2001, 1, 1)),
    );
    expect(repository.assetGoals.single.reachedAt, _day(-10));

    // Removing the crossing transaction clears the date.
    repository = await repository.deleteExistingTransaction('big');
    expect(_summaryFor(repository, 1000).reachedAt, isNull);
    expect(repository.assetGoals.single.reachedAt, isNull);
    final reloaded = await FinanceRepository.load(database);
    expect(reloaded.assetGoals.single.reachedAt, isNull);

    // A later crossing sets the new real day.
    repository = await repository.addTransaction(_income('late', -2, 1000));
    expect(repository.assetGoals.single.reachedAt, _day(-2));
  });

  test('asset service mirror computes the same reached dates', () async {
    final (database, initialRepository) = await _openRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(_income('a', -20, 600));
    repository = await repository.addTransaction(_income('b', -10, 500));
    repository = await repository.addTransaction(
      _income('plan', -8, 5000, status: TransactionStatus.planned),
    );
    repository = await repository.addTransaction(_expense('c', -5, 700));
    repository = await repository.addAssetGoal(name: '500', amount: 500);
    repository = await repository.addAssetGoal(name: '1000', amount: 1000);
    repository = await repository.addAssetGoal(name: '2000', amount: 2000);

    final assetService = AssetService(
      accounts: repository.accounts,
      transactions: repository.transactions,
      snapshots: repository.snapshots,
      metaValues: {
        'asset_goals_json': jsonEncode(
          repository.assetGoals.map((goal) => goal.toJson()).toList(),
        ),
      },
      currencyService:
          CurrencyService(database: database, metaValues: const {}),
      database: database,
    );

    Map<double, DateTime?> reachedByTarget(
            List<AssetGoalProgressSummary> summaries) =>
        {
          for (final summary in summaries)
            summary.goal.targetAmount: summary.reachedAt
        };
    final expected = {500.0: _day(-20), 1000.0: _day(-10), 2000.0: null};
    expect(reachedByTarget(repository.assetGoalSummaries()), expected);
    expect(reachedByTarget(assetService.assetGoalSummaries()), expected);
  });
}
