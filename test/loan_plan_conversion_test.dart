import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/loan_amortization.dart';
import 'package:finance_app/src/core/models/loan_settlement.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/database_provider.dart';
import 'package:finance_app/src/core/providers/mutations/transaction_mutations.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/accounts/loan_detail_screen.dart';
import 'package:finance_app/src/features/transactions/transaction_composer_page.dart';
import 'package:finance_app/src/features/transactions/transaction_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'a generated plan converted to actual appears as one payment under its original installment',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateUtils.dateOnly(DateTime.now());
    final loan = Account(
      id: 'loan',
      name: '测试车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -1000,
      currentBalance: -1000,
      loanPrincipal: 1000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 2,
      loanStartDate: DateTime(today.year, today.month),
      loanPaymentDay: 12,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    const bank = Account(
      id: 'bank',
      name: '付款银行',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 2000,
      currentBalance: 2000,
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final seed = await FinanceRepository.load(db);
    await seed.addAccount(bank);
    await seed.addAccount(loan);
    final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    final writes = container.read(transactionMutationsProvider.notifier);
    final schedule = tryCalculateLoanScheduleForAccount(loan)!;
    final generated = await writes.generateLoanInstallmentPlans(
      loanId: loan.id,
      payerId: bank.id,
      confirmed: schedule.installments,
    );
    expect(generated, 2);
    final plans = await container.read(financeRepositoryProvider.future);
    final original =
        plans.transactions.singleWhere((tx) => tx.loanInstallmentNumber == 1);
    final other =
        plans.transactions.singleWhere((tx) => tx.loanInstallmentNumber == 2);
    expect(original.status, TransactionStatus.planned);
    expect(original.transactionDate.isAfter(today), isTrue);

    TransactionFormResult? result;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: FilledButton(
                      onPressed: () async {
                        result = await Navigator.of(context)
                            .push<TransactionFormResult>(
                          MaterialPageRoute(
                              builder: (_) => TransactionComposerPage(
                                    repository: plans,
                                    draft: original,
                                    editExisting: true,
                                  )),
                        );
                      },
                      child: const Text('编辑合同月供'),
                    ),
                  ))),
    ));
    await tester.tap(find.text('编辑合同月供'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('已发生'));
    await tester.tap(find.text('已发生'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天已还'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改').first);
    await tester.pumpAndSettle();
    await writes.updateTransaction(result!.transactions.single,
        expectedDatabase: db);
    final refreshed = await container.read(financeRepositoryProvider.future);
    expect(refreshed.transactions, hasLength(2));
    expect(
        refreshed.transactions
            .singleWhere((tx) => tx.status == TransactionStatus.actual)
            .id,
        original.id);
    expect(
        refreshed.transactions
            .singleWhere((tx) => tx.status == TransactionStatus.planned)
            .id,
        other.id);
    expect(refreshed.accountBalanceAt(bank.id, today), 1490);
    expect(refreshed.accountBalanceAt(loan.id, today), -500);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: LoanDetailScreen(account: loan, repository: refreshed)),
    ));
    await tester.pumpAndSettle();
    final period = find.byKey(const Key('loan-installment-1'));
    await tester.ensureVisible(period);
    final payment = find.byKey(Key('loan-payment-${original.id}'));
    expect(payment, findsOneWidget);
    expect(find.descendant(of: period, matching: payment), findsOneWidget);
    final dayLabel =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    for (final field in [
      find.textContaining(dayLabel),
      find.textContaining(bank.name),
      find.textContaining(RegExp(r'本金[^0-9]*500\.00')),
      find.textContaining(RegExp(r'利息[^0-9]*10\.00')),
    ]) {
      expect(find.descendant(of: payment, matching: field), findsOneWidget);
    }
    expect(find.byKey(Key('loan-payment-${other.id}')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (dialog: false, payToday: true, legacyInterest: false),
    (dialog: false, payToday: false, legacyInterest: false),
    (dialog: true, payToday: true, legacyInterest: false),
    (dialog: false, payToday: true, legacyInterest: true),
  ]) {
    testWidgets(
        'converting a future installment in ${scenario.dialog ? 'dialog' : 'composer'} '
        'uses the confirmed ${scenario.payToday ? 'payment' : 'scheduled'} date '
        'for ${scenario.legacyInterest ? 'legacy interest' : 'a split monthly payment'}',
        (tester) async {
      tester.view.physicalSize = const Size(520, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var repo = await FinanceRepository.load(db);
      repo = await repo.addAccount(const Account(
        id: 'bank',
        name: '银行',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 2000,
        currentBalance: 2000,
      ));
      repo = await repo.addAccount(const Account(
        id: 'loan',
        name: '贷款',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -1000,
        currentBalance: -1000,
      ));
      final today = DateUtils.dateOnly(DateTime.now());
      final scheduled = DateTime(today.year, today.month + 1, 10, 15);
      final principal = scenario.legacyInterest ? 0.0 : 100.0;
      final due = LoanInstallment(
        number: 3,
        dueDate: scheduled,
        principal: principal,
        interest: 10,
        payment: principal + 10,
        remainingPrincipal: 1000 - principal,
      );
      repo = await repo.addTransaction(FinanceTransaction(
        id: 'existing',
        type: scenario.legacyInterest
            ? TransactionType.expense
            : TransactionType.transfer,
        accountId: 'bank',
        toAccountId: scenario.legacyInterest ? null : 'loan',
        amount: due.payment,
        toAmount: scenario.legacyInterest ? null : due.principal,
        loanInstallmentNumber: scenario.legacyInterest ? null : due.number,
        legacyLoanId: scenario.legacyInterest ? 'loan' : null,
        legacyLoanPartNumber: scenario.legacyInterest ? due.number : null,
        currency: 'MYR',
        toCurrency: scenario.legacyInterest ? null : 'MYR',
        transactionDate: scheduled,
        description: '自定义月供',
        status: TransactionStatus.planned,
      ));
      final original = repo.transactions.single;
      TransactionFormResult? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: FilledButton(
                      onPressed: () async {
                        saved = scenario.dialog
                            ? await showDialog<TransactionFormResult>(
                                context: context,
                                builder: (_) => TransactionFormDialog(
                                    repository: repo,
                                    initialTransaction: original),
                              )
                            : await Navigator.of(context)
                                .push<TransactionFormResult>(
                                MaterialPageRoute(
                                    builder: (_) => TransactionComposerPage(
                                          repository: repo,
                                          draft: original,
                                          editExisting: true,
                                        )),
                              );
                      },
                      child: const Text('编辑预计月供')),
                )),
      ));
      await tester.tap(find.text('编辑预计月供'));
      await tester.pumpAndSettle();
      final actual = find.text('已发生');
      await tester.ensureVisible(actual);
      await tester.tap(actual);
      await tester.pumpAndSettle();
      final dialog = find.widgetWithText(AlertDialog, '确认还款日期');
      expect(dialog, findsOneWidget);
      await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
      await tester.pumpAndSettle();
      await tester.tap(actual);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      await tester.tap(find.text(scenario.payToday ? '今天已还' : '保留原日期'));
      await tester.pumpAndSettle();
      final save = find.text(scenario.dialog ? '保存' : '保存修改').first;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await repo.updateExistingTransaction(saved!.transactions.single);
      final reloaded = await FinanceRepository.load(db);
      final tx = reloaded.transactions.single;
      expect(tx.id, original.id);
      expect(tx.accountId, 'bank');
      expect(tx.toAccountId, original.toAccountId);
      expect(tx.amount, due.payment);
      expect(tx.toAmount, original.toAmount);
      expect(tx.loanInstallmentNumber, original.loanInstallmentNumber);
      expect(tx.legacyLoanId, original.legacyLoanId);
      expect(tx.legacyLoanPartNumber, original.legacyLoanPartNumber);
      expect(tx.status, TransactionStatus.actual);
      expect(tx.transactionDate, scenario.payToday ? today : scheduled);
      expect(tx.recordDate, original.recordDate);
      final todayEnd = DateTime(today.year, today.month, today.day + 1)
          .subtract(const Duration(microseconds: 1));
      LoanInstallment remaining(DateTime cutoff) => LoanSettlement.forLoan(
            loanId: 'loan',
            currency: 'MYR',
            transactions: reloaded.transactions,
            cutoff: cutoff,
          ).remaining(due);
      expect(remaining(todayEnd).payment, scenario.payToday ? 0 : due.payment);
      expect(remaining(scheduled).payment, 0);
      expect(reloaded.accountBalanceAt('bank', todayEnd),
          2000 - (scenario.payToday ? due.payment : 0));
      expect(reloaded.accountBalanceAt('loan', todayEnd),
          -1000 + (scenario.payToday ? principal : 0));
      expect(tester.takeException(), isNull);
    });
  }
}
