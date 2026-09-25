import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/services/asset_service.dart';
import 'package:finance_app/src/core/services/currency_service.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:finance_app/src/features/accounts/asset_goals_page.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _endOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
}

/// Noon of the day [offset] days from today.
DateTime _noon(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset, 12);
}

DateTime _dayOf(DateTime date) => DateTime(date.year, date.month, date.day);

FinanceTransaction _cashIncome(
  String id,
  DateTime date,
  double amount, {
  TransactionStatus status = TransactionStatus.actual,
}) {
  return FinanceTransaction(
    id: id,
    type: TransactionType.income,
    accountId: 'cash',
    amount: amount,
    currency: 'MYR',
    transactionDate: date,
    status: status,
  );
}

Future<(AppDatabase, FinanceRepository)> _cashRepository() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  var repository = await FinanceRepository.load(database);
  repository = await repository.addAccount(const Account(
    id: 'cash',
    name: '现金',
    accountType: AccountType.bankSaving,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    currentBalance: 0,
  ));
  return (database, repository);
}

AssetGoalProgressSummary _goal(
  List<AssetGoalProgressSummary> summaries,
  double targetAmount,
) {
  return summaries.firstWhere((item) => item.goal.targetAmount == targetAmount);
}

void main() {
  test('goal cutoff clamps omitted and future dates to the end of today',
      () async {
    final (_, repository) = await _cashRepository();
    expect(repository.assetGoalCutoffDate(), _endOfToday());
    expect(repository.assetGoalCutoffDate(DateTime(2100)), _endOfToday());
    expect(
      repository.assetGoalCutoffDate(repository.currentMonthCutoffDate()),
      _endOfToday(),
    );
    final past = DateTime(2020, 5, 31, 23, 59, 59, 999);
    expect(repository.assetGoalCutoffDate(past), past);
  });

  test(
      'future actual and planned transactions never count toward goal '
      'progress, history or reached state', () async {
    final (database, initialRepository) = await _cashRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(
      _cashIncome('held', _noon(-3), 800),
    );
    repository = await repository.addTransaction(
      _cashIncome('plan', _noon(-1), 5000, status: TransactionStatus.planned),
    );
    // Tomorrow may fall in next month; the explicit future cutoffs below
    // cover both the month-end and far-future forms.
    repository = await repository.addTransaction(
      _cashIncome('payday', _noon(1), 5000),
    );
    repository = await repository.addAssetGoal(name: '1000', amount: 1000);

    for (final cutoff in [
      null,
      repository.currentMonthCutoffDate(),
      DateTime(2100),
    ]) {
      final summary = repository.assetGoalSummaries(cutoffDate: cutoff).single;
      expect(summary.currentAssets, 800, reason: 'cutoff $cutoff');
      expect(summary.isReached, isFalse, reason: 'cutoff $cutoff');
      expect(summary.reachedAt, isNull, reason: 'cutoff $cutoff');
      expect(summary.history.last.totalAssets, 800, reason: 'cutoff $cutoff');
      expect(
        summary.history.every((point) => !point.date.isAfter(_endOfToday())),
        isTrue,
        reason: 'cutoff $cutoff',
      );
    }
    expect(repository.assetGoals.single.reachedAt, isNull);

    // A past cutoff is still honoured as given.
    final beforeIncome = DateTime(
        _noon(-4).year, _noon(-4).month, _noon(-4).day, 23, 59, 59, 999);
    expect(
      repository
          .assetGoalSummaries(cutoffDate: beforeIncome)
          .single
          .currentAssets,
      0,
    );

    // The AssetService mirror applies the same clamp.
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
    final mirrored =
        assetService.assetGoalSummaries(cutoffDate: DateTime(2100)).single;
    expect(mirrored.currentAssets, 800);
    expect(mirrored.isReached, isFalse);
    expect(mirrored.reachedAt, isNull);
  });

  test(
      'reached dates follow the real crossing day across months, including '
      'snapshot appreciation, and stay empty for opening balances', () async {
    final (_, initialRepository) = await _cashRepository();
    var repository = await initialRepository.addAccount(const Account(
      id: 'fund',
      name: '基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
    final today = _today();
    final midLastMonth = DateTime(today.year, today.month - 1, 15, 12);
    final lateLastMonth = DateTime(today.year, today.month - 1, 20, 12);
    repository = await repository.addTransaction(
      _cashIncome('salary', midLastMonth, 1000),
    );
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'rise',
      accountId: 'fund',
      snapshotDate: lateLastMonth,
      marketValue: 3000,
      costBasis: 100,
    ));
    for (final amount in [50.0, 1000.0, 2500.0, 10000.0]) {
      repository = await repository.addAssetGoal(
        name: amount.toStringAsFixed(0),
        amount: amount,
      );
    }

    final summaries = repository.assetGoalSummaries();
    // Opening balance (fund 100) already covers 50: reached, but undated.
    expect(_goal(summaries, 50).isReached, isTrue);
    expect(_goal(summaries, 50).reachedAt, isNull);
    // Mid-month crossing is dated on that day, not the month end.
    expect(_goal(summaries, 1000).reachedAt, _dayOf(midLastMonth));
    // Snapshot appreciation crosses on the snapshot day.
    expect(_goal(summaries, 2500).reachedAt, _dayOf(lateLastMonth));
    expect(_goal(summaries, 10000).isReached, isFalse);
    expect(_goal(summaries, 10000).reachedAt, isNull);

    final stored = {
      for (final goal in repository.assetGoals) goal.targetAmount: goal
    };
    expect(stored[50]!.reachedAt, isNull);
    expect(stored[1000]!.reachedAt, _dayOf(midLastMonth));
    expect(stored[2500]!.reachedAt, _dayOf(lateLastMonth));
    expect(stored[10000]!.reachedAt, isNull);
  });

  test('editing or deleting the crossing transaction clears the stale date',
      () async {
    final (database, initialRepository) = await _cashRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(
      _cashIncome('bonus', _noon(-5), 1200),
    );
    repository = await repository.addAssetGoal(name: '1000', amount: 1000);
    expect(repository.assetGoals.single.reachedAt, _dayOf(_noon(-5)));

    // Moving it to tomorrow makes it a future actual: no longer reached.
    repository = await repository.updateExistingTransaction(
      _cashIncome('bonus', _noon(1), 1200),
    );
    expect(repository.assetGoalSummaries().single.isReached, isFalse);
    expect(repository.assetGoalSummaries().single.reachedAt, isNull);
    expect(repository.assetGoals.single.reachedAt, isNull);

    // Back in the past but too small: still no date.
    repository = await repository.updateExistingTransaction(
      _cashIncome('bonus', _noon(-5), 900),
    );
    expect(repository.assetGoals.single.reachedAt, isNull);

    // Restored amount brings the real day back.
    repository = await repository.updateExistingTransaction(
      _cashIncome('bonus', _noon(-5), 1200),
    );
    expect(repository.assetGoals.single.reachedAt, _dayOf(_noon(-5)));

    // Deleting it clears the persisted date, including after reload.
    repository = await repository.deleteExistingTransaction('bonus');
    expect(repository.assetGoals.single.reachedAt, isNull);
    final reloaded = await FinanceRepository.load(database);
    expect(reloaded.assetGoals.single.reachedAt, isNull);
  });

  testWidgets('asset goals page shows total assets as of today',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final (_, initialRepository) = await _cashRepository();
    var repository = initialRepository;
    repository = await repository.addTransaction(
      _cashIncome('held', _noon(-3), 800),
    );
    repository = await repository.addTransaction(
      _cashIncome('payday', _noon(1), 5000),
    );
    repository = await repository.addAssetGoal(name: '一千', amount: 1000);
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: AssetGoalsPage(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(compassMoney(800)), findsOneWidget);
    expect(find.text(compassMoney(5800)), findsNothing);
    expect(find.text('还差 ${compassMoney(200)}'), findsOneWidget);
    expect(find.textContaining('已达成'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('asset goals use total assets without deducting credit liabilities',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    for (final account in const [
      Account(
        id: 'goal-cash',
        name: 'Cash',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
      Account(
        id: 'goal-investment',
        name: 'Investment',
        accountType: AccountType.fund,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        currentBalance: 500,
      ),
      Account(
        id: 'goal-credit',
        name: 'Credit',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -800,
      ),
    ]) {
      repository = await repository.addAccount(account);
    }
    repository = await repository.addAssetGoal(
      name: 'MYR 1,200',
      amount: 1200,
    );

    final summary = repository.assetGoalSummaries().single;
    expect(repository.totalAssets(), 700);
    expect(repository.totalTargetAssets(), 1500);
    expect(summary.currentAssets, 1500);
    expect(summary.isReached, isTrue);
    expect(summary.history.last.totalAssets, 1500);
  });

  testWidgets('accounts entry opens functional asset-goal management',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: '储蓄账户',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Scaffold(body: AccountsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset-goals-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-goals-card')));
    await tester.pumpAndSettle();
    expect(find.text('资产目标'), findsWidgets);
    expect(find.byKey(const Key('asset-goal-empty-add')), findsOneWidget);

    await tester.tap(find.byKey(const Key('asset-goal-empty-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('asset-goal-name')),
      '首个十万',
    );
    await tester.enterText(
      find.byKey(const Key('asset-goal-amount')),
      '100000',
    );
    await tester.tap(find.byKey(const Key('asset-goal-save')));
    await tester.pumpAndSettle();

    expect(find.text('首个十万'), findsOneWidget);
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.assetGoals.single.name, '首个十万');
    expect(updated.assetGoals.single.targetAmount, 100000);
    expect(tester.takeException(), isNull);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
