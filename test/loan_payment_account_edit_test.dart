import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/shared/finance_amount_field.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

void main() {
  for (final currency in ['MYR', 'USD']) {
    testWidgets(
        'editing an unmatched legacy $currency payment preserves both legs',
        (tester) async {
      tester.view.physicalSize = const Size(520, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var repo = await FinanceRepository.load(db);
      repo = await repo.addAccount(Account(
          id: 'payer',
          name: 'Bank',
          accountType: AccountType.cash,
          reportGroup: ReportGroup.cash,
          currency: currency,
          currentBalance: 10000));
      repo = await repo.addAccount(const Account(
          id: 'loan',
          name: 'Car',
          accountType: AccountType.loan,
          reportGroup: ReportGroup.credit,
          currency: 'MYR',
          initialBalance: -5000,
          currentBalance: -5000));
      final debit = currency == 'MYR' ? 1000.0 : 235.0;
      repo = await repo.addTransaction(FinanceTransaction(
        id: 'old',
        type: TransactionType.transfer,
        accountId: 'payer',
        toAccountId: 'loan',
        amount: debit,
        currency: currency,
        toAmount: 800,
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 1, 2),
        description: '自动扣款',
      ));
      final backup = await repo.buildJsonSnapshotPayload();
      (backup['meta'] as Map).remove('loan_installment_semantics');
      repo = await repo.restoreSyncedSnapshot(backup);
      final entry = repo.transactions.single;
      expect(entry.loanInstallmentNumber, isNull);
      TransactionFormResult? result;
      await tester.pumpWidget(MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () async {
                      result = await Navigator.push<TransactionFormResult>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TransactionComposerPage(
                                  repository: repo,
                                  draft: entry,
                                  editExisting: true)));
                    },
                    child: const Text('编辑'),
                  )))));
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.textContaining('未关联贷款期号'), findsOneWidget);
      expect(
          tester
              .widget<FinanceAmountField>(find.byType(FinanceAmountField).at(1))
              .readOnly,
          isTrue);
      await tester.enterText(
          find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.hintText == '添加备注（选填）'),
          '核对完成');
      await tester.tap(find.text('保存修改').first);
      await tester.pumpAndSettle();
      final saved = result!.transactions.single;
      expect(saved.loanInstallmentNumber, isNull);
      expect(saved.amount, debit);
      expect(saved.toAmount, 800);
      repo = await repo.updateExistingTransaction(saved);
      expect(repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance,
          -4200);
      expect(repo.accounts.singleWhere((a) => a.id == 'payer').currentBalance,
          10000 - debit);
    });
  }
  testWidgets(
      'installment identity survives memo edits, templates, copies and a signed reversal',
      (tester) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repo = await FinanceRepository.load(database);
    repo = await repo.addAccount(const Account(
        id: 'payer',
        name: 'Bank',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 1000));
    repo = await repo.addAccount(const Account(
        id: 'loan',
        name: 'Car',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -1000,
        currentBalance: -1000));
    final original = FinanceTransaction(
      id: 'split',
      type: TransactionType.transfer,
      accountId: 'payer',
      toAccountId: 'loan',
      currency: 'MYR',
      toCurrency: 'MYR',
      amount: 110,
      toAmount: 100,
      loanInstallmentNumber: 1,
      transactionDate: DateTime(2026, 3, 3),
      description: '贷款月供 #1',
    );
    repo = await repo.addTransaction(original);
    FinanceTransaction? result;
    Future<void> open({FinanceTransaction? draft, bool edit = false}) async {
      result = null;
      await tester.pumpWidget(MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () async {
                      final saved = await Navigator.push<TransactionFormResult>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TransactionComposerPage(
                                  repository: repo,
                                  draft: draft,
                                  editExisting: edit)));
                      result = saved?.transactions.single;
                    },
                    child: const Text('打开'),
                  )))));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    Future<void> save(String label) async {
      final button = find.text(label).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Finder editHint(String text) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == text);

    await open(draft: original, edit: true);
    await tester.enterText(editHint('添加备注（选填）'), '银行自动扣款');
    await save('保存修改');
    repo = await repo.updateExistingTransaction(result!);
    await open(draft: repo.transactions.single, edit: true);
    await tester.enterText(editHint('添加商户'), '我的银行');
    await save('保存修改');
    repo = await repo.updateExistingTransaction(result!);
    final edited = repo.transactions.single;
    expect(edited.description, '银行自动扣款');
    expect(edited.merchant, '我的银行');
    expect(edited.toAmount, 100);
    expect(edited.loanInstallmentNumber, 1);

    repo = await repo.addTransactionTemplate(name: '贷款模板', transaction: edited);
    await open();
    await tester.tap(find.text('套用模板'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('贷款模板 ·'));
    await tester.pumpAndSettle();
    expect(find.text('Car · 第 1 期'), findsOneWidget);
    await save('保存');
    expect(result!.id, isNot(edited.id));
    expect(result!.toAmount, 100);
    expect(result!.amount, 110);
    expect(result!.merchant, '我的银行');
    expect(result!.loanInstallmentNumber, 1);

    await open(draft: edited); // Copy the posted payment to reverse it.
    final amounts = find.byType(FinanceAmountField);
    await enterAmount(tester, amounts.at(0), '0');
    await save('保存');
    expect(result, isNull);
    expect(find.textContaining('本金不能超过'), findsOneWidget);
    await enterAmount(tester, amounts.at(0), '-110');
    await save('保存');
    expect(result, isNull);
    await enterAmount(tester, amounts.at(1), '-111');
    await save('保存');
    expect(result, isNull);
    await enterAmount(tester, amounts.at(1), '-100');
    await save('保存');
    expect(result!.loanInstallmentNumber, 1);
    repo = await repo.addTransaction(result!);
    expect(
        repo.accounts.singleWhere((a) => a.id == 'payer').currentBalance, 1000);
    expect(
        repo.accounts.singleWhere((a) => a.id == 'loan').currentBalance, -1000);

    final ordinary = FinanceTransaction(
        id: 'ordinary',
        type: TransactionType.transfer,
        accountId: 'payer',
        toAccountId: 'loan',
        amount: 20,
        currency: 'MYR',
        transactionDate: DateTime(2026, 3, 3),
        description: '贷款月供 #1');
    await open(draft: ordinary);
    expect(find.text('偿还本金'), findsNothing);
    await save('保存');
    expect(result!.loanInstallmentNumber, isNull);
    expect(result!.toAmount, isNull);
  });

  for (final status in [TransactionStatus.actual, TransactionStatus.planned]) {
    for (final sourceCurrency in ['MYR', 'USD']) {
      testWidgets(
          'changing $status loan payer to $sourceCurrency preserves principal and balances',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        var repository = await FinanceRepository.load(database);
        for (final account in [
          const Account(
            id: 'old-payer',
            name: '原付款账户',
            accountType: AccountType.bankSaving,
            reportGroup: ReportGroup.cash,
            currency: 'MYR',
            currentBalance: 5000,
          ),
          Account(
            id: 'new-payer',
            name: '新付款账户',
            accountType: AccountType.bankSaving,
            reportGroup: ReportGroup.cash,
            currency: sourceCurrency,
            currentBalance: 8000,
          ),
          const Account(
            id: 'loan',
            name: '车贷',
            accountType: AccountType.loan,
            reportGroup: ReportGroup.credit,
            currency: 'MYR',
            currentBalance: -71097,
          ),
        ]) {
          repository = await repository.addAccount(account);
        }
        final original = FinanceTransaction(
          id: 'loan-payment',
          type: TransactionType.transfer,
          accountId: 'old-payer',
          toAccountId: 'loan',
          amount: 1316,
          toAmount: 1191.58,
          loanInstallmentNumber: 1,
          currency: 'MYR',
          toCurrency: 'MYR',
          transactionDate: DateTime(2026, 7, 23),
          description: '贷款月供 #1',
          status: status,
        );
        repository = await repository.addTransaction(original);
        TransactionFormResult? saved;
        await tester.pumpWidget(MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: Builder(
              builder: (context) => Scaffold(
                    body: FilledButton(
                      onPressed: () async {
                        saved = await Navigator.of(context)
                            .push<TransactionFormResult>(
                          MaterialPageRoute(
                              builder: (_) => TransactionComposerPage(
                                    repository: repository,
                                    draft: original,
                                    editExisting: true,
                                  )),
                        );
                      },
                      child: const Text('编辑月供'),
                    ),
                  )),
        ));
        await tester.tap(find.text('编辑月供'));
        await tester.pumpAndSettle();

        // Exercise the real account selector repeatedly, including switching back.
        for (final name in ['新付款账户', '原付款账户', '新付款账户']) {
          await tester.tap(find.byType(OutlinedButton).first);
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('$name ·'));
          await tester.pumpAndSettle();
          final fields = tester
              .widgetList<FinanceAmountField>(find.byType(FinanceAmountField))
              .toList();
          final payerCurrency = name == '原付款账户' ? 'MYR' : sourceCurrency;
          expect(
              fields[0].controller.text,
              repository
                  .convertAmount(
                      amount: 1316,
                      fromCurrency: 'MYR',
                      toCurrency: payerCurrency)
                  .toStringAsFixed(2));
          expect(fields[1].controller.text, '1191.58');
        }
        const loanAmountHelp = '贷款月供 · 转出为本息合计，转入仅偿还本金';
        expect(find.text('本息 → 本金'), findsOneWidget);
        expect(find.text(loanAmountHelp), findsNothing);
        final help = find.byTooltip('查看转入金额说明');
        await tester.ensureVisible(help);
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(find.text(loanAmountHelp), findsOneWidget);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        expect(find.text('重新换算'), findsNothing);
        await tester.tap(find.text('保存修改').first);
        await tester.pumpAndSettle();
        final edited = saved!.transactions.single;
        expect(edited.id, original.id);
        expect(edited.accountId, 'new-payer');
        expect(edited.toAccountId, 'loan');
        final debit = double.parse(repository
            .convertAmount(
                amount: 1316, fromCurrency: 'MYR', toCurrency: sourceCurrency)
            .toStringAsFixed(2));
        expect(edited.amount, debit);
        expect(edited.loanInstallmentNumber, 1);
        expect(edited.installmentPaymentInLoanCurrency, 1316);
        expect(edited.toAmount, 1191.58);
        expect(edited.currency, sourceCurrency);
        expect(edited.toCurrency, 'MYR');
        expect(edited.status, status);
        repository = await repository.updateExistingTransaction(edited);
        final reloaded = await FinanceRepository.load(database);
        final actual = status == TransactionStatus.actual;
        for (final repo in [repository, reloaded]) {
          double balance(String id) =>
              repo.accounts.singleWhere((a) => a.id == id).currentBalance;
          expect(balance('old-payer'), 5000);
          expect(balance('new-payer'),
              closeTo(actual ? 8000 - debit : 8000, .001));
          expect(balance('loan'), closeTo(actual ? -69905.42 : -71097, 0.001));
          expect(repo.transactions.single.toAmount, 1191.58);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
