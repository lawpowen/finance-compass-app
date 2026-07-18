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

    await tester.tap(find.text('未来保费'));
    await tester.pumpAndSettle();
    expect(find.text('编辑交易'), findsOneWidget);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
