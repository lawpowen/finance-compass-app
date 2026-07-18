import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edit composer preserves the existing transaction identity', (
    tester,
  ) async {
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
    repository = await repository.addCategory(
      const Category(
        id: 'food',
        name: '餐饮',
        type: CategoryType.expense,
      ),
    );
    final originalRecordDate = DateTime(2026, 7, 1, 9, 30);
    final transactionDate = DateTime(2026, 7, 8);
    final draft = FinanceTransaction(
      id: 'existing-transaction',
      type: TransactionType.expense,
      accountId: 'cash',
      categoryId: 'food',
      amount: 18,
      currency: 'MYR',
      recordDate: originalRecordDate,
      transactionDate: transactionDate,
      merchant: '午餐',
    );
    TransactionFormResult? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(
          AppThemeStyle.abyss,
        ).copyWith(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  saved =
                      await Navigator.of(context).push<TransactionFormResult>(
                    MaterialPageRoute(
                      builder: (_) => TransactionComposerPage(
                        repository: repository,
                        draft: draft,
                        editExisting: true,
                      ),
                    ),
                  );
                },
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑交易'), findsOneWidget);

    await tester.tap(find.text('保存修改').first);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.transactions.single.id, draft.id);
    expect(saved!.transactions.single.recordDate, originalRecordDate);
    expect(saved!.transactions.single.transactionDate, transactionDate);
  });

  testWidgets('new composer directly generates a selected monthly range', (
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
        currentBalance: 100,
      ),
    );
    final draft = FinanceTransaction(
      id: 'cycle-draft',
      type: TransactionType.expense,
      accountId: 'cash',
      amount: 88,
      currency: 'MYR',
      recordDate: DateTime(2026, 7, 17),
      transactionDate: DateTime(2026, 7, 17),
      status: TransactionStatus.actual,
      merchant: '周期测试',
    );
    TransactionFormResult? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss)
            .copyWith(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<TransactionFormResult>(
                  MaterialPageRoute(
                    builder: (_) => TransactionComposerPage(
                      repository: repository,
                      draft: draft,
                    ),
                  ),
                );
              },
              child: const Text('新增周期交易'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增周期交易'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('生成周期'));
    await tester.tap(find.text('生成周期'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '3 个月'));
    await tester.pumpAndSettle();
    expect(find.text('当前起 3 个月'), findsOneWidget);

    await tester.ensureVisible(find.text('保存交易'));
    await tester.tap(find.text('保存交易'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.transactions, hasLength(3));
    expect(saved!.transactions.map((item) => item.status),
        everyElement(TransactionStatus.actual));
    expect(saved!.transactions.map((item) => item.transactionDate.month),
        [7, 8, 9]);
  });

  testWidgets('edit composer confirms deletion and returns a delete action', (
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
        currentBalance: 100,
      ),
    );
    final draft = FinanceTransaction(
      id: 'delete-me',
      type: TransactionType.expense,
      accountId: 'cash',
      amount: 18,
      currency: 'MYR',
      recordDate: DateTime(2026, 7, 18),
      transactionDate: DateTime(2026, 7, 18),
    );
    TransactionFormResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss)
            .copyWith(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result =
                    await Navigator.of(context).push<TransactionFormResult>(
                  MaterialPageRoute(
                    builder: (_) => TransactionComposerPage(
                      repository: repository,
                      draft: draft,
                      editExisting: true,
                    ),
                  ),
                );
              },
              child: const Text('编辑待删除交易'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('编辑待删除交易'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除交易'));
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    expect(find.text('删除交易？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('删除交易'), findsOneWidget);

    await tester.ensureVisible(find.text('删除交易'));
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.deletedTransactionId, draft.id);
    expect(result!.transactions, isEmpty);
  });

  for (final amount in [0.0, -25.5]) {
    testWidgets('edit composer accepts signed amount $amount', (tester) async {
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
      final draft = FinanceTransaction(
        id: 'signed-$amount',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: amount,
        currency: 'MYR',
        recordDate: DateTime(2026, 7, 18),
        transactionDate: DateTime(2026, 7, 18),
      );
      TransactionFormResult? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss)
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result =
                      await Navigator.of(context).push<TransactionFormResult>(
                    MaterialPageRoute(
                      builder: (_) => TransactionComposerPage(
                        repository: repository,
                        draft: draft,
                        editExisting: true,
                      ),
                    ),
                  );
                },
                child: const Text('编辑金额'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('编辑金额'));
      await tester.pumpAndSettle();
      expect(find.text(amount.toStringAsFixed(2)), findsOneWidget);
      await tester.tap(find.text('保存修改').first);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.transactions.single.amount, amount);
    });
  }
}
