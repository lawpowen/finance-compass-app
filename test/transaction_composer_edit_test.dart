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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

void main() {
  testWidgets(
      'account chooser quotes month-end balances for both transfer legs',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(const Account(
      id: 'payer',
      name: 'Payer',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 100,
      currentBalance: 100,
    ));
    repo = await repo.addAccount(const Account(
      id: 'receiver',
      name: 'Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -50,
      currentBalance: -50,
    ));
    final now = DateTime.now();
    repo = await repo.addTransaction(FinanceTransaction(
      id: 'future',
      type: TransactionType.transfer,
      accountId: 'payer',
      toAccountId: 'receiver',
      currency: 'MYR',
      amount: 30,
      transactionDate: DateTime(now.year, now.month + 1, 1),
    ));
    await tester.pumpWidget(MaterialApp(
        home: TransactionComposerPage(
      repository: repo,
      draft: FinanceTransaction(
          id: 'draft',
          type: TransactionType.transfer,
          accountId: 'payer',
          toAccountId: 'receiver',
          currency: 'MYR',
          amount: 1,
          transactionDate: now),
    )));
    final source = find.text('转出账户');
    await tester.ensureVisible(source);
    await tester.tap(source);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('本月末余额').evaluate().single.widget,
        isA<Text>()
            .having((w) => w.data, 'month-end cash', contains('100.00')));
    await tester.tap(find.text('Payer · MYR'));
    await tester.pumpAndSettle();
    final target = find.text('转入账户');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('本月末欠款').evaluate().single.widget,
        isA<Text>()
            .having((w) => w.data, 'month-end debt', contains('50.00'))
            .having((w) => w.data, 'later commitments', contains('20.00')));
  });

  testWidgets('empty-account forms show the ledger base currency',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final empty = await FinanceRepository.load(database);
    final repository = await empty.updateExchangeRates(
      {'TWD': 1, 'USD': 32, 'MYR': 7, 'CNY': 4.5},
      ['TWD', 'USD', 'MYR', 'CNY'],
    );
    expect(repository.accounts, isEmpty);

    await tester.pumpWidget(MaterialApp(
      home: TransactionComposerPage(repository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'TWD'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TransactionFormDialog(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(r'TWD (NT$)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving reveals each missing amount or account inline',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: TransactionComposerPage(repository: repository),
    ));
    final save = find.text('保存交易');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的金额').hitTestable(), findsOneWidget);

    final field = find.byType(TextFormField).first;
    await enterAmount(tester, field, '11.34');
    expect(find.text('请输入有效的金额'), findsNothing);
    expect(
      find
          .ancestor(
            of: find.text('请选择账户'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(amountController(tester, field).text, '11.34');
    expect(find.byType(TransactionComposerPage), findsOneWidget);
  });

  testWidgets('transfer feedback distinguishes target account from amount',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(const Account(
      id: 'local',
      name: '本币账户',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 100,
    ));
    repository = await repository.addAccount(const Account(
      id: 'foreign',
      name: '外币账户',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'USD',
      currentBalance: 10,
    ));
    await tester.pumpWidget(MaterialApp(
      home: TransactionComposerPage(
        repository: repository,
        draft: FinanceTransaction(
          id: 'unassigned-transfer',
          type: TransactionType.transfer,
          accountId: 'local',
          currency: 'MYR',
          amount: 42,
          transactionDate: DateTime(2026, 7, 18),
        ),
      ),
    ));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请选择转入账户'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外币账户 · USD'));
    await tester.pumpAndSettle();
    expect(find.text('请选择转入账户'), findsNothing);
    await tester.tap(find.byType(TextFormField).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('amount-key-C')));
    await tester.tap(find.byKey(const ValueKey('amount-key-完成')));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的转入金额').hitTestable(), findsOneWidget);
    expect(amountController(tester, find.byType(TextFormField).first).text,
        '42.00');
    expect(find.byType(TransactionComposerPage), findsOneWidget);
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft
  ]) {
    testWidgets(
        'save shortcut respects keypad and IME with ${modifier.keyLabel}',
        (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      var repository = await FinanceRepository.load(database);
      repository = await repository.addAccount(const Account(
        id: 'cash',
        name: '现金账户',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 100,
      ));
      TransactionFormResult? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: FilledButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<TransactionFormResult>(
                  MaterialPageRoute(
                    builder: (_) =>
                        TransactionComposerPage(repository: repository),
                  ),
                );
              },
              child: const Text('打开交易'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('打开交易'));
      await tester.pumpAndSettle();

      Future<void> sendShortcut() async {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
      }

      final field = find.byType(TextFormField).first;
      await enterAmount(tester, field, '-1.25');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('amount-keyboard')), findsNothing);
      expect(saved, isNull);

      await tester.tap(field);
      await tester.pumpAndSettle();
      await sendShortcut();
      expect(find.byKey(const Key('amount-keyboard')), findsNothing);
      expect(saved, isNull);

      final merchant = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '添加商户',
      );
      await tester.ensureVisible(merchant);
      await tester.showKeyboard(merchant);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '午餐',
        composing: TextRange(start: 0, end: 2),
        selection: TextSelection.collapsed(offset: 2),
      ));
      await tester.pump();

      await sendShortcut();
      expect(saved, isNull);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '午餐',
        selection: TextSelection.collapsed(offset: 2),
      ));
      await tester.pump();
      await sendShortcut();
      expect(saved?.transactions.single.amount, -1.25);
      expect(saved?.transactions.single.merchant, '午餐');
    });
  }

  testWidgets('new composer opens the amount keypad from its caption and icon',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await FinanceRepository.load(database);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: buildFinanceTheme(AppThemeStyle.abyss),
      home: TransactionComposerPage(repository: repository),
    ));

    final keypad = find.byKey(const Key('amount-keyboard'));
    await tester.tap(find.text('金额'));
    await tester.pumpAndSettle();
    expect(keypad, findsOneWidget);
    await tester.tap(find.byTooltip('关闭金额键盘'));
    await tester.pumpAndSettle();
    expect(keypad, findsNothing);

    await tester.tap(find.byTooltip('打开金额键盘'));
    await tester.pumpAndSettle();
    expect(keypad, findsOneWidget);
  });

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
    await enterAmount(tester, find.byType(TextFormField).first, '11.34');
    await tester.scrollUntilVisible(find.text('保存修改'), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存修改').first);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.transactions.single.id, draft.id);
    expect(saved!.transactions.single.amount, 11.34);
    expect(saved!.transactions.single.recordDate, originalRecordDate);
    expect(saved!.transactions.single.transactionDate, transactionDate);
  });

  testWidgets('editing a loan payment preserves payment and principal amounts',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash-loan-payment',
        name: '还款账户',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 5000,
      ),
    );
    repository = await repository.addAccount(
      const Account(
        id: 'loan-payment-target',
        name: '车贷',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -71097,
      ),
    );
    final draft = FinanceTransaction(
      id: 'loan-payment-1',
      type: TransactionType.transfer,
      accountId: 'cash-loan-payment',
      toAccountId: 'loan-payment-target',
      amount: 1316,
      toAmount: 1191.58,
      loanInstallmentNumber: 1,
      currency: 'MYR',
      toCurrency: 'MYR',
      transactionDate: DateTime(2026, 7, 23),
      description: '贷款月供 #1',
    );
    TransactionFormResult? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<TransactionFormResult>(
                  MaterialPageRoute(
                    builder: (_) => TransactionComposerPage(
                      repository: repository,
                      draft: draft,
                      editExisting: true,
                    ),
                  ),
                );
              },
              child: const Text('编辑贷款月供'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('编辑贷款月供'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改').first);
    await tester.pumpAndSettle();

    expect(saved!.transactions.single.amount, 1316);
    expect(saved!.transactions.single.toAmount, 1191.58);
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
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        amount.toStringAsFixed(2),
      );
      await tester.tap(find.text('保存修改').first);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.transactions.single.amount, amount);
    });
  }
}
