import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('three calculation bases use distinct financial scopes', (
    tester,
  ) async {
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
        name: '现金账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    repository = await repository.addAccount(
      const Account(
        id: 'credit',
        name: '信用卡',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 0,
        creditLimit: 5000,
        statementDay: 25,
        paymentDueDay: 14,
      ),
    );
    final now = DateTime.now();
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'cash-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 100,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 2),
      ),
      FinanceTransaction(
        id: 'card-expense',
        type: TransactionType.expense,
        accountId: 'credit',
        amount: 300,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 3),
      ),
      FinanceTransaction(
        id: 'repayment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'credit',
        amount: 200,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 4),
      ),
      FinanceTransaction(
        id: 'planned-cash-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 40,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 5),
        status: TransactionStatus.planned,
      ),
      FinanceTransaction(
        id: 'planned-card-expense',
        type: TransactionType.expense,
        accountId: 'credit',
        amount: 50,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 6),
        status: TransactionStatus.planned,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss)
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: TransactionsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_selectedBasisValue(tester), '- MYR 400');

    await tester.tap(find.byKey(const Key('transaction-filter-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('现金账户').last);
    await tester.pumpAndSettle();
    expect(_selectedBasisValue(tester), '- MYR 100');
    expect(find.text('支出 MYR 100'), findsOneWidget);

    await tester.tap(find.byKey(const Key('transaction-filter-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部').last);
    await tester.pumpAndSettle();
    expect(_selectedBasisValue(tester), '- MYR 400');

    await tester.tap(find.byKey(const Key('basis-card-cash')));
    await tester.pumpAndSettle();
    expect(find.text('实际现金'), findsOneWidget);
    expect(_selectedBasisValue(tester), 'MYR 300');
    expect(find.text('已知流出 MYR 300'), findsOneWidget);
    expect(find.text('尚未安排 MYR 0'), findsOneWidget);
    expect(find.byKey(const Key('monthly-funding-need-note')), findsOneWidget);

    await tester.tap(find.byKey(const Key('basis-card-committed')));
    await tester.pumpAndSettle();
    expect(_selectedBasisValue(tester), 'MYR 100');
    expect(find.text('偿还抵扣 MYR 200'), findsOneWidget);

    await tester.tap(find.text('包含预计'));
    await tester.pumpAndSettle();
    expect(_selectedBasisValue(tester), 'MYR 150');
    expect(find.text('新增承诺 MYR 350'), findsOneWidget);
  });

  testWidgets('calculation scope can include actual and planned together', (
    tester,
  ) async {
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
        name: '现金账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    repository = await repository.addCategory(
      const Category(
        id: 'daily',
        name: '日常',
        type: CategoryType.expense,
      ),
    );
    final now = DateTime.now();
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'actual-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'daily',
        amount: 100,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 2),
        status: TransactionStatus.actual,
        merchant: '已发生消费',
      ),
      FinanceTransaction(
        id: 'planned-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'daily',
        amount: 40,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 3),
        status: TransactionStatus.planned,
        merchant: '预计消费',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(
            AppThemeStyle.abyss,
          ).copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: TransactionsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已发生消费'), findsOneWidget);
    expect(find.text('预计消费'), findsNothing);
    expect(find.text('支出 MYR 100'), findsOneWidget);

    await tester.tap(find.text('包含预计'));
    await tester.pumpAndSettle();

    expect(find.text('已发生消费'), findsOneWidget);
    expect(find.text('预计消费'), findsOneWidget);
    expect(find.text('支出 MYR 140'), findsOneWidget);
  });

  testWidgets('future month is reachable and its transaction opens editor', (
    tester,
  ) async {
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
        name: '现金账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    repository = await repository.addCategory(
      const Category(
        id: 'insurance',
        name: '保险',
        type: CategoryType.expense,
      ),
    );
    repository = await repository.addAccount(
      const Account(
        id: 'loan',
        name: '车贷',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -70000,
      ),
    );
    final now = DateTime.now();
    final futureDate = DateTime(now.year, now.month + 1, 5);
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'future-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'insurance',
        amount: 180,
        currency: 'MYR',
        transactionDate: futureDate,
        status: TransactionStatus.planned,
        merchant: '未来保费',
      ),
      FinanceTransaction(
        id: 'future-actual-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        categoryId: 'insurance',
        amount: 60,
        currency: 'MYR',
        transactionDate: DateTime(futureDate.year, futureDate.month, 6),
        status: TransactionStatus.actual,
        merchant: '已确定未来支出',
      ),
      FinanceTransaction(
        id: 'future-loan-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'loan',
        amount: 1316,
        toAmount: 1193.67,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(futureDate.year, futureDate.month, 23),
        status: TransactionStatus.planned,
        merchant: '车贷月供',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWith(
            () => _TestRepositoryNotifier(repository),
          ),
        ],
        child: MaterialApp(
          theme: buildFinanceTheme(
            AppThemeStyle.abyss,
          ).copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: TransactionsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
    await tester.pumpAndSettle();

    expect(
        find.text('${futureDate.year}年${futureDate.month}月'), findsOneWidget);
    expect(find.text('未来保费'), findsOneWidget);
    expect(find.text('已确定未来支出'), findsOneWidget);
    expect(find.text('车贷月供'), findsOneWidget);
    expect(find.text('实际现金'), findsOneWidget);
    expect(find.byKey(const Key('monthly-funding-need-card')), findsNothing);
    expect(_selectedBasisValue(tester), '- MYR 240');

    await tester.tap(find.byKey(const Key('basis-card-cash')));
    await tester.pumpAndSettle();
    expect(_selectedBasisValue(tester), 'MYR 1,556');
    expect(find.text('需准备现金'), findsOneWidget);
    expect(find.text('已知流出 MYR 1,556'), findsOneWidget);
    expect(find.text('尚未安排 MYR 0'), findsOneWidget);
    expect(find.byKey(const Key('monthly-funding-need-note')), findsOneWidget);

    await tester.tap(find.text('未来保费'));
    await tester.pumpAndSettle();
    expect(find.text('编辑交易'), findsOneWidget);
  });
}

String _selectedBasisValue(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const Key('transaction-basis-selected-value')))
      .data!;
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
