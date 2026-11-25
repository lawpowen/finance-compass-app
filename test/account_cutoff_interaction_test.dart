import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    hide Account, Category;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:finance_app/src/features/dashboard/dashboard_v2_screen.dart';
import 'package:finance_app/src/features/reports/reports_v2_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'three screens reconcile positive assets, overdrafts and debt at month end',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    final now = DateTime.now();
    final previousEnd = DateTime(now.year, now.month, 0, 15);
    for (final (id, type, group, opening) in [
      ('bank', AccountType.bankSaving, ReportGroup.cash, 500.0),
      ('overdraft', AccountType.cash, ReportGroup.cash, -40.0),
      ('card-a', AccountType.creditCard, ReportGroup.credit, -150.0),
      ('card-b', AccountType.creditCard, ReportGroup.credit, 35.0),
      ('loan', AccountType.loan, ReportGroup.credit, 70.0),
    ]) {
      repo = await repo.addAccount(Account(
          id: id,
          name: id,
          accountType: type,
          reportGroup: group,
          currency: 'MYR',
          initialBalance: opening,
          currentBalance: opening));
    }
    repo = await repo.addTransactions([
      FinanceTransaction(
          id: 'closing-day',
          type: TransactionType.income,
          accountId: 'bank',
          currency: 'MYR',
          amount: 12,
          transactionDate: previousEnd),
      FinanceTransaction(
          id: 'next-month',
          type: TransactionType.expense,
          accountId: 'card-a',
          currency: 'MYR',
          amount: 300,
          transactionDate: DateTime(now.year, now.month + 1, 12)),
    ]);
    // 512 bank + 35 card credit + 70 loan credit - 40 overdraft - 150 debt.
    final sheet = repo.balanceSheetAt(repo.currentMonthCutoffDate());
    expect((sheet.assets, sheet.liabilities, sheet.netWorth),
        (617.0, 190.0, 427.0));
    expect(
        repo
            .totalAssetHistory()
            .firstWhere((p) =>
                p.date.month == previousEnd.month &&
                p.date.year == previousEnd.year)
            .totalAssets,
        427);
    expect(repo.creditCardCommittedOutstandingBalance('card-a'), 450);

    for (final page in <Widget>[
      DashboardV2Screen(repository: repo),
      AccountsV2Screen(repository: repo),
      ReportsV2Screen(repository: repo),
    ]) {
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: buildFinanceTheme(AppThemeStyle.abyss),
              home: Scaffold(body: page))));
      await tester.pumpAndSettle();
      if (page is DashboardV2Screen) {
        expect(
            find.descendant(
                of: find.byKey(const Key('dashboard-kpi-net-worth')),
                matching: find.text('MYR 427')),
            findsOneWidget);
      } else {
        final key = page is AccountsV2Screen
            ? 'accounts-net-worth'
            : 'reports-net-worth';
        expect(tester.widget<Text>(find.byKey(Key(key))).data,
            page is AccountsV2Screen ? 'MYR 427.00' : 'MYR 427');
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'historical navigation retains goal and card cutoffs and excludes unsigned loans',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final prior = DateTime(now.year, now.month, 0);
    var repo = await FinanceRepository.load(db);
    repo = await repo.addAccount(const Account(
        id: 'bank',
        name: 'Bank',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 0));
    repo = await repo.addAccount(const Account(
        id: 'card',
        name: 'Card A',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        creditLimit: 1000,
        statementDay: 12,
        paymentDueDay: 24,
        currentBalance: 0));
    repo = await repo.addAccount(Account(
        id: 'loan',
        name: 'New contract',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -100,
        currentBalance: -100,
        loanStartDate: DateTime(now.year, now.month, 1)));
    repo = await repo.addTransactions([
      FinanceTransaction(
          id: 'old',
          type: TransactionType.income,
          accountId: 'bank',
          amount: 20,
          currency: 'MYR',
          transactionDate: prior),
      FinanceTransaction(
          id: 'new',
          type: TransactionType.income,
          accountId: 'bank',
          amount: 80,
          currency: 'MYR',
          transactionDate: DateTime(now.year, now.month, 1)),
    ]);
    repo = await repo.addAssetGoal(name: 'Goal', amount: 100);
    final activeRepo = repo;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _HistoryRepository(activeRepo))
        ],
        child: MaterialApp(
            home: Scaffold(body: AccountsV2Screen(repository: repo)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-cutoff-selector')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(Key('account-cutoff-${prior.year}-${prior.month}')));
    await tester.pumpAndSettle();
    final goal = find.byKey(const Key('asset-goals-card'));
    expect(
        find.descendant(of: goal, matching: find.text('20%')), findsOneWidget);
    await tester.tap(goal);
    await tester.pumpAndSettle();
    expect(find.text('截至当日总资产'), findsOneWidget);
    expect(find.byKey(const Key('asset-goal-add')), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('贷款').last);
    await tester.pumpAndSettle();
    expect(find.text('New contract'), findsNothing);
    expect(
        tester.widget<Text>(find.byKey(const Key('accounts-net-worth'))).data,
        'MYR 20.00');
    await tester.tap(find.text('信用').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理信用卡账期'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Card A'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('credit-card-historical-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account cutoff selector recalculates totals at prior month end',
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
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );

    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'previous-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 100,
        currency: 'MYR',
        transactionDate: DateTime(previousMonth.year, previousMonth.month, 10),
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'current-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 200,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 10),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Scaffold(body: AccountsV2Screen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MYR 700.00'), findsWidgets);
    expect(find.text('信用卡溢缴款'), findsNothing);
    await tester.tap(find.byKey(const Key('account-cutoff-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-cutoff-month-list')), findsOneWidget);

    await tester.tap(
      find.byKey(
        Key('account-cutoff-${previousMonth.year}-${previousMonth.month}'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('account-historical-cutoff-banner')),
      findsOneWidget,
    );
    expect(find.text('MYR 900.00'), findsWidgets);
    expect(find.textContaining('历史统计 · 截至'), findsOneWidget);
    final historicalHelp = find.textContaining('余额和负债统计截至所选月份末');
    expect(historicalHelp, findsNothing);
    await tester.tap(find.byTooltip('查看历史统计说明'));
    await tester.pumpAndSettle();
    expect(historicalHelp, findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(historicalHelp, findsNothing);

    await tester.tap(find.text('现金').last);
    await tester.pumpAndSettle();
    final cash = find.text('Cash');
    final netAssets = find.text('净资产');
    expect(tester.getTopLeft(cash).dy,
        greaterThan(tester.getBottomLeft(netAssets).dy));

    for (final width in [960.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      final cutoff = find.byKey(const Key('account-cutoff-selector'));
      final summary = tester.getRect(netAssets);
      expect(tester.getBottomRight(cutoff).dx, lessThan(summary.left));
      expect(tester.getTopLeft(cash).dx, lessThan(summary.left));
      expect(find.text('MYR 900.00'), findsWidgets);
      expect(find.byKey(const Key('asset-goals-card')), findsOneWidget);
    }

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(cash).dy,
        greaterThan(tester.getBottomLeft(netAssets).dy));
    expect(find.textContaining('历史统计 · 截至'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _HistoryRepository extends FinanceRepositoryNotifier {
  _HistoryRepository(this.repository);
  final FinanceRepository repository;
  @override
  Future<FinanceRepository> build() async => repository;
}
