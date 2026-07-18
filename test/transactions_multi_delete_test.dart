import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long press selects multiple transactions and deletes live',
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
        name: '现金账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000,
      ),
    );
    final now = DateTime.now();
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'expense-one',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 10,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 2),
        merchant: '第一笔消费',
      ),
      FinanceTransaction(
        id: 'expense-two',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 20,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 3),
        merchant: '第二笔消费',
      ),
    ]);
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
          theme: buildFinanceTheme(AppThemeStyle.abyss)
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: TransactionsV2Screen(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('第一笔消费'));
    await tester.pump();
    expect(find.text('已选择 1 笔'), findsOneWidget);

    await tester.tap(find.text('第二笔消费'));
    await tester.pump();
    expect(find.text('已选择 2 笔'), findsOneWidget);

    await tester.tap(find.byTooltip('删除所选交易'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 笔交易？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('第一笔消费'), findsNothing);
    expect(find.text('第二笔消费'), findsNothing);
    expect(find.text('已删除 2 笔交易'), findsOneWidget);
    final refreshed = await container.read(financeRepositoryProvider.future);
    expect(refreshed.transactions, isEmpty);
    expect(refreshed.accounts.single.currentBalance, 1000);
  });

  test('batch delete rolls back when any selected id is stale', () async {
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
        currentBalance: 100,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 25,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 17),
      ),
    );

    await expectLater(
      repository.deleteExistingTransactions(['expense', 'missing']),
      throwsStateError,
    );
    final refreshed = await FinanceRepository.load(database);
    expect(refreshed.transactions.map((item) => item.id), contains('expense'));
    expect(refreshed.accounts.single.currentBalance, 75);
  });
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
