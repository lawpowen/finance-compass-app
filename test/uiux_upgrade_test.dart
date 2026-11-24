import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/core/utils/month_key.dart';
import 'package:finance_app/src/features/accounts/account_detail_screen.dart';
import 'package:finance_app/src/features/accounts/accounts_v2_screen.dart';
import 'package:finance_app/src/features/budgets/budgets_v2_screen.dart';
import 'package:finance_app/src/features/dashboard/dashboard_v2_screen.dart';
import 'package:finance_app/src/features/reports/reports_v2_screen.dart';
import 'package:finance_app/src/features/shared/compass_ui.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
      'dashboard shows KPI strip, multi-item attention queue, and recent transactions',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    final monthKey = monthKeyFromDate(now);
    final statementDay = now.day > 2 ? now.day - 1 : 28;
    final paymentDueDay = now.day < 26 ? now.day + 2 : 28;
    final billedDate = DateTime(now.year, now.month - 1, 10, 12);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(
      const Account(
        id: 'cash-main',
        name: 'Cash Wallet',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 5000,
        currentBalance: 5000,
      ),
    );
    repo = await repo.addAccount(
      Account(
        id: 'card-a',
        name: 'Alpha Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 0,
        creditLimit: 5000,
        statementDay: statementDay,
        paymentDueDay: paymentDueDay,
      ),
    );
    repo = await repo.addAccount(
      Account(
        id: 'card-b',
        name: 'Beta Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 0,
        creditLimit: 6000,
        statementDay: statementDay,
        paymentDueDay: paymentDueDay,
      ),
    );
    repo = await repo.addCategory(
      const Category(id: 'cat-sal', name: 'Salary', type: CategoryType.income),
    );
    repo = await repo.addCategory(
      const Category(id: 'cat-food', name: 'Food', type: CategoryType.expense),
    );
    repo = await repo.addCategory(
      const Category(
        id: 'cat-shop',
        name: 'Shopping',
        type: CategoryType.expense,
      ),
    );
    repo = await repo.addBudget(
      Budget(
        id: 'b-food',
        categoryId: 'cat-food',
        monthKey: monthKey,
        amount: 500,
      ),
    );
    repo = await repo.addBudget(
      Budget(
        id: 'b-shop',
        categoryId: 'cat-shop',
        monthKey: monthKey,
        amount: 400,
      ),
    );
    repo = await repo.addTransactions([
      FinanceTransaction(
        id: 'tx-sal',
        type: TransactionType.income,
        accountId: 'cash-main',
        categoryId: 'cat-sal',
        amount: 3000,
        currency: 'MYR',
        transactionDate: today,
      ),
      FinanceTransaction(
        id: 'tx-food',
        type: TransactionType.expense,
        accountId: 'cash-main',
        categoryId: 'cat-food',
        amount: 460,
        currency: 'MYR',
        transactionDate: today,
        description: 'Lunch feast',
      ),
      FinanceTransaction(
        id: 'tx-shop',
        type: TransactionType.expense,
        accountId: 'cash-main',
        categoryId: 'cat-shop',
        amount: 420,
        currency: 'MYR',
        transactionDate: today,
        description: 'Grocery haul',
      ),
      FinanceTransaction(
        id: 'tx-card-a',
        type: TransactionType.expense,
        accountId: 'card-a',
        categoryId: 'cat-food',
        amount: 210,
        currency: 'MYR',
        transactionDate: billedDate,
      ),
      FinanceTransaction(
        id: 'tx-card-b',
        type: TransactionType.expense,
        accountId: 'card-b',
        categoryId: 'cat-shop',
        amount: 320,
        currency: 'MYR',
        transactionDate: billedDate,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.monochrome),
          home: Scaffold(body: DashboardV2Screen(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-kpi-net-worth')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-kpi-income')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-kpi-expense')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-kpi-net')), findsOneWidget);

    expect(find.textContaining('Alpha Card · '), findsOneWidget);
    expect(find.textContaining('Beta Card · '), findsOneWidget);
    expect(find.textContaining('Food预算'), findsOneWidget);
    expect(find.textContaining('Shopping预算'), findsOneWidget);
    expect(find.text('近期交易'), findsOneWidget);
    expect(find.textContaining('Lunch feast'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('Lunch feast').first);
    await tester.tap(find.textContaining('Lunch feast').first);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionComposerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'accounts show multi-currency conversion, credit card overpayment/bar, and modernized cash detail',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final monthKey = monthKeyFromDate(now);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    const usdCash = Account(
      id: 'usd-cash',
      name: 'USD Brokerage Cash',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'USD',
      initialBalance: 100,
      currentBalance: 100,
    );
    const overpaidCard = Account(
      id: 'cc-over',
      name: 'Overpaid Platinum',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: 80,
      currentBalance: 80,
      creditLimit: 5000,
      statementDay: 15,
      paymentDueDay: 5,
    );
    const activeCard = Account(
      id: 'cc-debt',
      name: 'Travel Visa',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -1200,
      currentBalance: -1200,
      creditLimit: 5000,
      statementDay: 15,
      paymentDueDay: 5,
    );
    repo = await repo.addAccount(usdCash);
    repo = await repo.addAccount(overpaidCard);
    repo = await repo.addAccount(activeCard);
    repo = await repo.addCategory(
      const Category(id: 'c-fx', name: 'Coffee', type: CategoryType.expense),
    );
    repo = await repo.addTransaction(
      FinanceTransaction(
        id: 'tx-usd-1',
        type: TransactionType.expense,
        accountId: usdCash.id,
        categoryId: 'c-fx',
        amount: 12,
        currency: 'USD',
        transactionDate: DateTime(now.year, now.month, now.day, 10),
        description: 'Airport espresso',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.monochrome),
          home: Scaffold(body: AccountsV2Screen(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('溢缴 MYR 80.00'),
      160,
      scrollable: scrollable,
    );
    expect(find.text('溢缴 MYR 80.00'), findsOneWidget);
    expect(find.byType(CompassDualProgressBar), findsOneWidget);

    await tester.ensureVisible(find.text('现金').last);
    await tester.tap(find.text('现金').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('USD 88.00'),
      160,
      scrollable: scrollable,
    );
    expect(find.text('USD 88.00'), findsOneWidget);
    expect(find.textContaining('≈ MYR '), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.monochrome),
          home: AccountDetailScreen(
            account: repo.accounts.firstWhere((a) => a.id == usdCash.id),
            repository: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-detail-balance')), findsOneWidget);
    expect(find.text('标记已对账至 $monthKey'), findsOneWidget);
    expect(find.text('$monthKey 账户收支'), findsOneWidget);
    expect(find.text('账户流水明细'), findsOneWidget);
    expect(find.text('余额追溯'), findsOneWidget);
    expect(find.textContaining('Airport espresso'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'transactions show daily subtotals/reset pills and composer shows dynamic labels and quick chips',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(
      const Account(
        id: 'cash',
        name: 'Main Bank',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 1000,
        currentBalance: 1000,
      ),
    );
    repo = await repo.addCategory(
      const Category(id: 'eat', name: 'Dining', type: CategoryType.expense),
    );
    repo = await repo.addCategory(
      const Category(id: 'pay', name: 'Payroll', type: CategoryType.income),
    );
    repo = await repo.addTransactions([
      FinanceTransaction(
        id: 't1',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'eat',
        amount: 25,
        currency: 'MYR',
        transactionDate: today,
      ),
      FinanceTransaction(
        id: 't2',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'eat',
        amount: 35,
        currency: 'MYR',
        transactionDate: today,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.monochrome),
          home: Scaffold(body: TransactionsV2Screen(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('支 MYR 60'), findsOneWidget);

    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transaction-month-today')), findsOneWidget);
    await tester.tap(find.byKey(const Key('transaction-month-today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transaction-month-today')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.monochrome),
        home: TransactionComposerPage(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('付款账户'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Dining'), findsOneWidget);

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('收款账户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'budgets render dual progress bars, daily guidance, and dynamic base currency in editor',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final monthKey = monthKeyFromDate(now);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.setMetaValue('currency_priority_json', '["USD","MYR"]');
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(
      const Account(
        id: 'usd',
        name: 'USD Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'USD',
        initialBalance: 1000,
        currentBalance: 1000,
      ),
    );
    repo = await repo.addCategory(
      const Category(id: 'gro', name: 'Groceries', type: CategoryType.expense),
    );
    repo = await repo.addBudget(
      Budget(
        id: 'b-gro',
        categoryId: 'gro',
        monthKey: monthKey,
        amount: 600,
        currency: 'USD',
      ),
    );
    repo = await repo.addTransaction(
      FinanceTransaction(
        id: 't-gro',
        type: TransactionType.expense,
        accountId: 'usd',
        categoryId: 'gro',
        amount: 120,
        currency: 'USD',
        transactionDate: DateTime(now.year, now.month, now.day, 9),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider
              .overrideWith(() => _TestRepositoryNotifier(repo)),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.monochrome),
          home: Scaffold(body: BudgetsV2Screen(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CompassDualProgressBar), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('日均可用'), findsNothing);
    expect(
        find.byKey(const Key('budget-mobile-total-remaining')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '调整'));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetEditorPage), findsOneWidget);
    expect(find.textContaining('USD '), findsWidgets);
    expect(find.text('MYR '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reports expand all categories inline, show dual progress on budget, and keep no dead chevrons',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final monthKey = monthKeyFromDate(now);
    final txDate = DateTime(now.year, now.month, now.day, 12);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(
      const Account(
        id: 'cash',
        name: 'Main Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 8000,
        currentBalance: 8000,
      ),
    );
    for (var i = 0; i < 6; i++) {
      final catId = 'cat-$i';
      repo = await repo.addCategory(
        Category(
          id: catId,
          name: 'Category $i',
          type: CategoryType.expense,
        ),
      );
      repo = await repo.addTransaction(
        FinanceTransaction(
          id: 'tx-$i',
          type: TransactionType.expense,
          accountId: 'cash',
          categoryId: catId,
          amount: (600 - i * 80).toDouble(),
          currency: 'MYR',
          transactionDate: txDate,
        ),
      );
    }
    repo = await repo.addBudget(
      Budget(
        id: 'b0',
        categoryId: 'cat-0',
        monthKey: monthKey,
        amount: 1000,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.monochrome),
        home: Scaffold(body: ReportsV2Screen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byKey(const Key('reports-category-0-name')), findsOneWidget);
    expect(find.byKey(const Key('reports-category-5-name')), findsNothing);
    final rankCard = find.ancestor(
      of: find.byKey(const Key('reports-category-0-name')),
      matching: find.byType(CompassCard),
    );
    expect(
        find.descendant(
            of: rankCard, matching: find.byType(CompassDualProgressBar)),
        findsNWidgets(5));

    final toggle = find.byKey(const Key('reports-toggle-all-categories'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reports-category-5-name')), findsOneWidget);
    expect(find.text('收起至前 5'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports-category-5-name')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('reports-budget-rate')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final budgetCard = find.ancestor(
      of: find.byKey(const Key('reports-budget-rate')),
      matching: find.byType(CompassCard),
    );
    expect(
        find.descendant(
            of: budgetCard, matching: find.byType(CompassDualProgressBar)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
