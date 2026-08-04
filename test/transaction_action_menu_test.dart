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
  testWidgets('transaction row keeps direct edit and restores all menu actions',
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
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'menu-transaction',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 18,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, now.day),
        merchant: '菜单测试交易',
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
          theme: buildFinanceTheme(AppThemeStyle.abyss)
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: TransactionsV2Screen(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('菜单测试交易'));
    await tester.pumpAndSettle();
    expect(find.text('编辑交易'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    await _openMenu(tester);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('复用新增'), findsOneWidget);
    expect(find.text('保存模板'), findsOneWidget);
    expect(find.text('保存周期'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('复用新增'));
    await tester.pumpAndSettle();
    expect(find.text('复制新增交易'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    await _openMenu(tester);
    await tester.tap(find.text('保存模板'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    var refreshed = await container.read(financeRepositoryProvider.future);
    expect(refreshed.transactionTemplates, hasLength(1));

    await _openMenu(tester);
    await tester.tap(find.text('保存周期'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    refreshed = await container.read(financeRepositoryProvider.future);
    expect(refreshed.recurringTransactionRules, hasLength(1));

    await _openMenu(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 1 笔交易？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('菜单测试交易'), findsNothing);
    refreshed = await container.read(financeRepositoryProvider.future);
    expect(
      refreshed.transactions.where((item) => item.id == 'menu-transaction'),
      isEmpty,
    );
    expect(
      refreshed.transactions
          .where((item) => item.status == TransactionStatus.planned),
      hasLength(3),
    );
  });
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('交易操作'));
  await tester.pumpAndSettle();
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
