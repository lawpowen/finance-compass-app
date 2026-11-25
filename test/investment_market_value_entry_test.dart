import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/asset_snapshot.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/features/shared/finance_amount_field.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/accounts/account_detail_screen.dart';
import 'package:finance_app/src/features/accounts/asset_snapshot_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

void main() {
  testWidgets(
      'an open snapshot editor keeps its draft and detects a replaced observation',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(const Account(
        id: 'fund',
        name: 'Fund',
        accountType: AccountType.fund,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        currentBalance: 100));
    final snapshot = AssetSnapshot(
        id: 'first',
        accountId: 'fund',
        snapshotDate: DateTime(2025, 1, 1),
        marketValue: 100,
        costBasis: 100);
    repo = await repo.addAssetSnapshot(snapshot);
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider
          .overrideWith(() => _TestRepositoryNotifier(repo))
    ]);
    addTearDown(container.dispose);
    await container.read(financeRepositoryProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: AssetSnapshotFormDialog(
                repository: repo, initialSnapshot: snapshot))));
    await tester.pumpAndSettle();
    await container.read(financeRepositoryProvider.notifier).mutate((live) =>
        live.updateExistingAssetSnapshot(AssetSnapshot(
            id: 'first',
            accountId: 'fund',
            snapshotDate: snapshot.snapshotDate,
            marketValue: 125,
            costBasis: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('这条快照已修改或删除'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull);
    expect(
        tester
            .widgetList<FinanceAmountField>(find.byType(FinanceAmountField))
            .first
            .controller
            .text,
        '100.0');
  });

  testWidgets(
      'removing an account while its detail is open leaves a return path',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const account = Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 0);
    final repo =
        await (await FinanceRepository.load(database)).addAccount(account);
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider
          .overrideWith(() => _TestRepositoryNotifier(repo))
    ]);
    addTearDown(container.dispose);
    await container.read(financeRepositoryProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: AccountDetailScreen(repository: repo, account: account))));
    await tester.pumpAndSettle();
    await container
        .read(financeRepositoryProvider.notifier)
        .mutate((live) => live.deleteAccountIfSafe(account.id));
    await tester.pumpAndSettle();
    expect(find.textContaining('请返回账户列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'snapshot preview uses investment currency, not the ledger currency',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const account = Account(
      id: 'usd-fund',
      name: '美元基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'USD',
      currentBalance: 0,
    );
    repository = await repository.addAccount(account);
    final snapshot = AssetSnapshot(
      id: 'usd-fund-snapshot',
      accountId: account.id,
      snapshotDate: DateTime.now(),
      marketValue: 150,
      costBasis: 120,
    );
    repository = await repository.addAssetSnapshot(snapshot);

    await tester.pumpWidget(MaterialApp(
      home: AssetSnapshotFormDialog(
        repository: repository,
        initialSnapshot: snapshot,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('美元基金 · USD'), findsOneWidget);
    expect(find.text('累计投入成本 USD 120.00'), findsOneWidget);
    expect(find.text('资金净收益 USD 30.00'), findsOneWidget);
  });

  testWidgets(
      'investment with opening principal and no observation shows its ledger',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const account = Account(
      id: 'fund',
      name: '基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    );
    repository = await repository.addAccount(account);
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'income',
      type: TransactionType.income,
      accountId: account.id,
      amount: 15,
      currency: 'MYR',
      transactionDate: DateTime(2024, 1, 2),
      description: '基金分红',
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'next-dividend',
      type: TransactionType.income,
      accountId: account.id,
      amount: 20,
      currency: 'MYR',
      transactionDate: DateTime(2024, 2, 1),
      description: '下月分红',
    ));
    await _openDetail(
        tester, repository, account, DateTime(2024, 1, 31, 23, 59, 59));
    expect(find.text('当前资产'), findsNothing);
    expect(find.text('总市值'), findsOneWidget);
    expect(find.text('净投入'), findsOneWidget);
    expect(find.text('MYR 15.00 (15.0%)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('基金分红'), 250);
    expect(find.text('基金分红'), findsOneWidget);
    expect(find.text('下月分红'), findsNothing);
  });

  testWidgets(
      'snapshot row has one observation date for market cash and return',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const account = Account(
      id: 'fund',
      name: '基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    );
    repository = await repository.addAccount(account);
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'january',
      accountId: account.id,
      snapshotDate: DateTime(2024, 1, 10, 16),
      marketValue: 120,
      cashBalance: 10,
      costBasis: 100,
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'funding',
      type: TransactionType.adjustment,
      accountId: account.id,
      amount: 50,
      currency: 'MYR',
      transactionDate: DateTime(2024, 2, 1),
    ));
    await _openDetail(
        tester, repository, account, DateTime(2024, 2, 28, 23, 59, 59));
    final row = find.byKey(const ValueKey('investment-snapshot-january'));
    await tester.scrollUntilVisible(row, 240);
    for (final label in [
      '总市值 MYR 120.00',
      '现金余额 MYR 10.00',
      '累计投入成本 MYR 100.00',
      '净投入 MYR 100.00',
      '资金净收益 MYR 20.00 (20.0%)'
    ]) {
      expect(
          find.descendant(of: row, matching: find.text(label)), findsOneWidget);
    }
  });

  testWidgets(
      'backdated observation can establish its own baseline at end of selected day',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const account = Account(
      id: 'fund',
      name: '基金',
      accountType: AccountType.fund,
      reportGroup: ReportGroup.investment,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    );
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day - 2);
    repository = await repository.addAccount(account);
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'existing',
      accountId: account.id,
      snapshotDate: DateTime(today.year, today.month, today.day - 1, 12),
      marketValue: 500,
      cashBalance: 0,
      costBasis: 450,
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'capital',
      type: TransactionType.adjustment,
      accountId: account.id,
      amount: 20,
      currency: 'MYR',
      transactionDate: day.add(const Duration(hours: 14)),
    ));
    AssetSnapshot? saved;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('打开'),
                    onPressed: () async {
                      saved = await showDialog<AssetSnapshot>(
                          context: context,
                          builder: (_) => AssetSnapshotFormDialog(
                              repository: repository,
                              initialAccountId: account.id));
                    })))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('快照日投入本金基准'), findsNothing);
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    final labels = MaterialLocalizations.of(tester.element(picker));
    await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: picker, matching: find.byType(TextField)),
      labels.formatCompactDate(day),
    );
    await tester.tap(find.text(labels.okButtonLabel));
    await tester.pumpAndSettle();
    expect(find.text('快照日投入本金基准'), findsOneWidget);
    expect(find.text('累计投入成本 MYR 120.00'), findsOneWidget);
    await enterAmount(tester, find.byType(FinanceAmountField).first, '150');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.snapshotDate,
        DateTime(day.year, day.month, day.day, 23, 59, 59));
    expect(saved!.costBasis, 120);
    repository = await repository.addAssetSnapshot(saved!);
    expect(repository.accountBalanceAt(account.id, saved!.snapshotDate), 150);
  });

  testWidgets(
      'new same-day observation uses stored timestamp precision for baseline ordering',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const account = Account(
        id: 'fund',
        name: '基金',
        accountType: AccountType.fund,
        reportGroup: ReportGroup.investment,
        currency: 'MYR',
        initialBalance: 100,
        currentBalance: 100);
    repository = await repository.addAccount(account);
    final day = DateTime.now();
    repository = await repository.addAssetSnapshot(AssetSnapshot(
      id: 'z-imported',
      accountId: account.id,
      snapshotDate: DateTime(day.year, day.month, day.day, 23, 59, 59),
      marketValue: 450,
      costBasis: 400,
    ));
    await tester.pumpWidget(MaterialApp(
        home: AssetSnapshotFormDialog(
            repository: repository, initialAccountId: account.id)));
    await tester.pumpAndSettle();
    // Generated snap_* IDs precede z-imported at the identical stored second.
    expect(find.text('快照日投入本金基准'), findsOneWidget);
    expect(find.text('累计投入成本 MYR 100.00'), findsOneWidget);
  });

  testWidgets('investment detail exposes a locked market value update entry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FinanceRepository.preview();
    final account = repository.investmentAccounts().first;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          home: AccountDetailScreen(
            account: account,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.text(
      repository.snapshotsForAccount(account.id).isEmpty ? '录入当前市值' : '更新当前市值',
    );
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('更新市值'), findsOneWidget);
    expect(find.text('${account.name} · ${account.currency}'), findsOneWidget);
    final accountDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(accountDropdown.onChanged, isNull);
  });

  testWidgets('historical investment detail hides write actions',
      (tester) async {
    final repository = FinanceRepository.preview();
    final account = repository.investmentAccounts().first;
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          home: AccountDetailScreen(
            account: account,
            repository: repository,
            cutoffDate: DateTime(now.year, now.month, 0, 23, 59, 59),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('account-detail-historical-banner')),
      findsOneWidget,
    );
    expect(find.text('录入当前市值'), findsNothing);
    expect(find.text('更新当前市值'), findsNothing);

    await tester.tap(find.byKey(const Key('account-detail-return-current')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('account-detail-historical-banner')),
      findsNothing,
    );
    expect(
      find.text(
        repository.snapshotsForAccount(account.id).isEmpty
            ? '录入当前市值'
            : '更新当前市值',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _openDetail(WidgetTester tester, FinanceRepository repository,
    Account account, DateTime cutoff) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      financeRepositoryProvider
          .overrideWith(() => _TestRepositoryNotifier(repository))
    ],
    child: MaterialApp(
        home: AccountDetailScreen(
            account: account, repository: repository, cutoffDate: cutoff)),
  ));
  await tester.pumpAndSettle();
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
