import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/models/loan_amortization.dart';
import 'package:finance_app/src/core/models/loan_settlement.dart';
import 'package:finance_app/src/core/providers/mutations/transaction_mutations.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/features/accounts/loan_detail_screen.dart';
import 'package:finance_app/src/features/accounts/account_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/amount_entry.dart';

void main() {
  testWidgets('loan form saves complete terms at 390 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const incompleteLoan = Account(
      id: 'legacy_loan',
      name: '旧贷款',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -120000,
      currentBalance: -120000,
    );
    Account? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<Account>(
                  context: context,
                  builder: (_) => const AccountFormDialog(
                    initialAccount: incompleteLoan,
                  ),
                );
              },
              child: const Text('编辑贷款'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑贷款'));
    await tester.pumpAndSettle();

    expect(find.text('贷款金额'), findsOneWidget);
    expect(find.text('年利率'), findsOneWidget);
    expect(find.text('还款方式'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await enterAmount(
        tester, find.byKey(const Key('loan-opening-balance')), '71097');
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.loanPrincipal, 120000);
    expect(result!.loanTermMonths, 60);
    expect(result!.loanRepaymentMethod, LoanRepaymentMethod.equalInstallment);
    expect(result!.initialBalance, -71097);
    expect(result!.currentBalance, -71097);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paying from another account clears just the matching plan',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'cash',
      name: '还款户口',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 20000,
      currentBalance: 20000,
    );
    const actualPayer = Account(
        id: 'other_payer',
        name: '其他银行',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 20000,
        currentBalance: 20000);
    final loan = Account(
      id: 'loan',
      name: '车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 7, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(actualPayer);
    repository = await repository.addAccount(loan);

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
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: LoanDetailScreen(
            account: loan,
            repository: repository,
            promptForPlannedGeneration: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生成预计还款交易？'), findsOneWidget);
    await tester.tap(find.text('暂不生成'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-installment-1')), findsOneWidget);
    expect(find.text('生成 12 期预计交易'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('generate-loan-planned-transactions')),
    );
    await tester.tap(
      find.byKey(const Key('generate-loan-planned-transactions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(cash.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    final planned = await container.read(financeRepositoryProvider.future);
    expect(
      planned.transactions
          .where((item) => item.status == TransactionStatus.planned),
      hasLength(12),
    );
    final firstPlanned = planned.transactions.singleWhere(
      (item) => item.description == '贷款月供 #1',
    );
    expect(firstPlanned.amount, 1120);
    expect(firstPlanned.toAmount, 1000);
    expect(find.text('预计交易已补齐'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('record-loan-installment')));
    await tester.tap(find.byKey(const Key('record-loan-installment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(actualPayer.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    final updated = await container.read(financeRepositoryProvider.future);
    final payment = updated.transactions.singleWhere(
      (item) =>
          item.type == TransactionType.transfer &&
          item.status == TransactionStatus.actual,
    );
    expect(payment.loanInstallmentNumber, 1);
    expect(payment.accountId, actualPayer.id);
    expect(payment.amount, 1120);
    expect(payment.toAmount, 1000);
    expect(payment.toAccountId, loan.id);
    expect(payment.description, '贷款月供 #1');
    expect(
      updated.transactions
          .where((item) => item.status == TransactionStatus.planned),
      hasLength(11),
    );
    expect(
      updated.accounts.singleWhere((item) => item.id == loan.id).currentBalance,
      -11000,
    );
    expect(
      updated.accounts.singleWhere((item) => item.id == cash.id).currentBalance,
      20000,
    );
    expect(
      updated.accounts
          .singleWhere((item) => item.id == actualPayer.id)
          .currentBalance,
      18880,
    );
    expect(find.textContaining('已记录'), findsWidgets);

    await container
        .read(transactionMutationsProvider.notifier)
        .deleteTransaction(payment.id);
    await tester.pumpAndSettle();
    final afterDelete = await container.read(financeRepositoryProvider.future);
    expect(
        afterDelete.accounts
            .singleWhere((item) => item.id == actualPayer.id)
            .currentBalance,
        20000);
    expect(
        afterDelete.transactions
            .where((item) => item.status == TransactionStatus.actual),
        isEmpty);
    expect(
      afterDelete.accounts
          .singleWhere((item) => item.id == loan.id)
          .currentBalance,
      -12000,
    );
    expect(find.text('记录第 1 期还款'), findsOneWidget);
  });

  test(
      'consolidating imported card-backed plans preserves their statement days',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var ledger = await FinanceRepository.load(database);
    for (final type in [AccountType.creditCard, AccountType.loan]) {
      ledger = await ledger.addAccount(Account(
          id: type.name,
          name: type.name,
          accountType: type,
          reportGroup: ReportGroup.credit,
          currency: 'MYR',
          currentBalance: 0));
    }
    final payload = await ledger.buildJsonSnapshotPayload();
    final rows = <Map<String, dynamic>>[];
    for (final (number, principalDay, interestDay) in [
      (1, '2026-11-26', '2026-11-26'),
      (2, '2026-11-25', '2026-11-26'),
      (3, null, '2026-11-25'),
    ]) {
      for (final principal in [true, false]) {
        final posting = principal ? principalDay : interestDay;
        rows.add({
          'id': '${principal ? 'principal' : 'interest'}-$number',
          'type': principal ? 'transfer' : 'expense',
          'account_id': 'creditCard',
          if (principal) 'to_account_id': 'loan',
          'amount': principal ? 80 : 20,
          'currency': 'MYR',
          'status': 'planned',
          'transaction_date': '2026-11-25T12:00:00',
          if (posting != null) 'card_posting_date': posting,
          'legacy_loan_id': 'loan',
          'legacy_loan_part_number': number,
        });
      }
    }
    payload['transactions'] = rows;
    ledger = await ledger.restoreSyncedSnapshot(payload);
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider
          .overrideWith(() => _TestRepositoryNotifier(ledger)),
    ]);
    addTearDown(container.dispose);
    await container
        .read(transactionMutationsProvider.notifier)
        .consolidateLegacyLoanPlans('loan');
    final stored = {
      for (final tx in await database.fetchTransactions()) tx.id: tx
    };
    expect(
        stored.keys,
        unorderedEquals(
            ['principal-1', 'principal-2', 'interest-2', 'principal-3']));
    expect(stored['principal-1']!.cardPostingDate, DateTime(2026, 11, 26));
    expect(stored['principal-1']!.amount, 100);
    expect(stored['principal-1']!.toAmount, 80);
    expect(stored['principal-1']!.loanInstallmentNumber, 1);
    expect(stored['principal-2']!.legacyLoanPartNumber, 2);
    expect(stored['principal-2']!.cardPostingDate, DateTime(2026, 11, 25));
    expect(stored['interest-2']!.cardPostingDate, DateTime(2026, 11, 26));
    expect(stored['principal-3']!.cardPostingDate, DateTime(2026, 11, 25));
  });

  test('deleting either legacy repayment part removes the whole installment',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'legacy_delete_cash',
      name: '还款账户',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 5000,
      currentBalance: 5000,
    );
    const loan = Account(
      id: 'legacy_delete_loan',
      name: '旧车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(loan);
    final date = DateTime(2026, 7, 23);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_actual_principal',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: loan.id,
        amount: 1191.58,
        currency: 'MYR',
        transactionDate: date,
        description: '贷款本金 #1',
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_actual_interest',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 124.42,
        currency: 'MYR',
        transactionDate: date,
        description: '贷款利息 #1',
      ),
    );
    repository = await _restorePreviousLoanFormat(repository);
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(transactionMutationsProvider.notifier)
        .deleteTransaction('legacy_actual_interest');
    final updated = await container.read(financeRepositoryProvider.future);
    expect(updated.transactions, isEmpty);
    expect(
        updated.accounts
            .singleWhere((item) => item.id == cash.id)
            .currentBalance,
        5000);
    expect(
        updated.accounts
            .singleWhere((item) => item.id == loan.id)
            .currentBalance,
        -12000);
  });

  testWidgets(
      'legacy principal and interest plans upgrade to one monthly payment',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'cash_upgrade',
      name: '还款户口',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 20000,
      currentBalance: 20000,
    );
    final loan = Account(
      id: 'loan_upgrade',
      name: '车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 7, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(loan);
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_principal',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: loan.id,
        amount: 1000,
        toAmount: 1000,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 8, 15),
        status: TransactionStatus.planned,
        description: '贷款本金 #1',
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'legacy_interest',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 120,
        currency: 'MYR',
        transactionDate: DateTime(2026, 8, 15),
        status: TransactionStatus.planned,
        description: '贷款利息 #1',
      ),
    );
    repository = await _restorePreviousLoanFormat(repository);
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
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: LoanDetailScreen(account: loan, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final upgraded = await container.read(financeRepositoryProvider.future);
    final payment = upgraded.transactions.single;
    expect(payment.description, '贷款月供 #1');
    expect(payment.amount, 1120);
    expect(payment.toAmount, 1000);
    expect(payment.status, TransactionStatus.planned);
    expect(find.text('补齐 11 期预计交易'), findsOneWidget);
  });

  testWidgets(
      'partial payments and reversals reduce only remaining installment components',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var ledger = await FinanceRepository.load(database);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const cash = Account(
        id: 'payer',
        name: '银行账户',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 10000,
        currentBalance: 10000);
    final loan = Account(
        id: 'l',
        name: '两期贷款',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -1000,
        currentBalance: -1000,
        loanPrincipal: 1000,
        loanAnnualInterestRate: 12,
        loanTermMonths: 2,
        loanStartDate: DateTime(now.year, now.month - 2),
        loanPaymentDay: 1,
        loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal);
    ledger = await ledger.addAccount(cash);
    ledger = await ledger.addAccount(loan);
    FinanceTransaction transfer(String id, int? number, double payment,
            double principal, DateTime date,
            {TransactionStatus status = TransactionStatus.actual}) =>
        FinanceTransaction(
            id: id,
            accountId: cash.id,
            toAccountId: loan.id,
            type: TransactionType.transfer,
            amount: payment,
            toAmount: principal,
            currency: 'MYR',
            toCurrency: 'MYR',
            transactionDate: date,
            loanInstallmentNumber: number,
            status: status,
            description: number == null ? '贷款月供 #1' : '自定义备注');
    ledger = await ledger.addTransactions([
      transfer('partial', 1, 200, 195, today),
      transfer('reverse', 1, -50, -48, today,
          status: TransactionStatus.settled),
      transfer('future-2', 2, 505, 500, DateTime(now.year, now.month + 1, 15)),
      transfer('ordinary', null, 5, 5, today),
    ]);
    final container = ProviderContainer(overrides: [
      financeRepositoryProvider
          .overrideWith(() => _TestRepositoryNotifier(ledger))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFinanceTheme(AppThemeStyle.abyss),
            home: LoanDetailScreen(account: loan, repository: ledger))));
    await tester.pumpAndSettle();
    // P1: 500 - (195 - 48) = 353. I1: 10 - (5 - 2) = 7.
    // Period 2 is fully booked in the future but still owed today.
    final firstRow = find.byKey(const Key('loan-installment-1'));
    final secondRow = find.byKey(const Key('loan-installment-2'));
    expect(find.descendant(of: firstRow, matching: find.byKey(const Key('loan-payment-partial'))), findsOneWidget);
    expect(find.descendant(of: firstRow, matching: find.textContaining('已冲正')), findsOneWidget);
    expect(find.byKey(const Key('loan-payment-ordinary')), findsNothing);
    expect(find.descendant(of: secondRow, matching: find.byKey(const Key('loan-payment-future-2'))), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(const Key('loan-installment-2')),
      matching: find.textContaining('已确认，待入账'),
    ), findsOneWidget);
    expect(find.text('RM 865.00'), findsOneWidget);
    expect(find.text('RM 12.00'), findsOneWidget);
    expect(find.text('待付 RM 360.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-loan-installment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cash.name));
    await tester.pumpAndSettle();
    expect(find.textContaining('本金 RM 353.00 · 利息 RM 7.00'), findsOneWidget);
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();
    final updated = await container.read(financeRepositoryProvider.future);
    expect(
        updated.transactions.where((tx) =>
            tx.loanInstallmentNumber == 1 &&
            tx.amount == 360 &&
            tx.toAmount == 353),
        hasLength(1));
    expect(find.text('RM 5.00'), findsOneWidget);
    expect(find.text('第 2 期已有未来实还记录'), findsOneWidget);

    // A second command issued with the stale confirmation never posts again.
    final schedule = tryCalculateLoanScheduleForAccount(loan)!;
    final remainingBefore = LoanSettlement.forLoan(
            loanId: loan.id,
            currency: 'MYR',
            transactions: ledger.transactions,
            cutoff: today)
        .remaining(schedule.installments.first);
    final duplicate = await container
        .read(transactionMutationsProvider.notifier)
        .recordLoanInstallment(
            loanId: loan.id, payerId: cash.id, confirmed: remainingBefore);
    expect(duplicate, isFalse);
    expect(
        (await container.read(financeRepositoryProvider.future))
            .transactions
            .length,
        updated.transactions.length);
  });

  test('tagged foreign-currency repayments settle on loan-currency components',
      () {
    final due = LoanInstallment(
        number: 3,
        dueDate: DateTime(2026, 11, 1),
        payment: 100,
        principal: 90,
        interest: 10,
        remainingPrincipal: 0);
    final tx = FinanceTransaction(
        id: 'fx',
        accountId: 'usd',
        toAccountId: 'l',
        type: TransactionType.transfer,
        amount: 25,
        currency: 'USD',
        toAmount: 90,
        loanInstallmentNumber: 3,
        loanPaymentAmount: 100,
        toCurrency: ' myr ',
        transactionDate: due.dueDate);
    final result = LoanSettlement.forLoan(
            loanId: 'l',
            currency: 'MYR',
            transactions: [tx],
            cutoff: due.dueDate)
        .remaining(due);
    expect(result.principal, 0);
    expect(result.interest, 0);
    expect(result.payment, 0);
  });

  testWidgets('historical loan detail is read only until returning current',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    final now = DateTime.now();
    final loan = Account(
      id: 'historical_loan',
      name: '历史车贷',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(now.year, now.month - 3, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(loan);
    repository = await repository.addAccount(const Account(
      id: 'history-payer', name: '还款账户', accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash, currency: 'MYR', initialBalance: 5000, currentBalance: 5000,
    ));
    repository = await repository.addTransaction(FinanceTransaction(
      id: 'future-part-payment', type: TransactionType.transfer, accountId: 'history-payer',
      toAccountId: loan.id, loanInstallmentNumber: 1, amount: 300, toAmount: 250,
      currency: 'MYR', transactionDate: DateTime(now.year, now.month + 1, 15),
    ));
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
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: LoanDetailScreen(
            account: loan,
            repository: repository,
            cutoffDate: DateTime(now.year, now.month - 1, 28, 23, 59, 59),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-historical-banner')), findsOneWidget);
    final firstPeriod = find.byKey(const Key('loan-installment-1'));
    expect(find.descendant(of: firstPeriod, matching: find.textContaining(' · 预计')), findsOneWidget);
    expect(find.byKey(const Key('loan-payment-future-part-payment')), findsNothing);
    expect(find.textContaining('待入账'), findsNothing);
    expect(find.byKey(const Key('record-loan-installment')), findsNothing);
    expect(
      find.byKey(const Key('generate-loan-planned-transactions')),
      findsNothing,
    );
    expect(find.textContaining('月末 · 只读'), findsOneWidget);
    final guidance = find.textContaining('不能记录或生成还款交易');
    expect(guidance, findsNothing);
    await tester.tap(find.byTooltip('查看贷款历史统计说明'));
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(guidance, findsNothing);

    await tester.tap(find.byKey(const Key('loan-return-current')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loan-historical-banner')), findsNothing);
    expect(find.descendant(of: firstPeriod, matching: find.textContaining('部分已确认，待入账')), findsOneWidget);
    expect(find.text('其中待入账 RM 300.00'), findsOneWidget);
    expect(find.descendant(of: firstPeriod, matching: find.byKey(const Key('loan-payment-future-part-payment'))), findsOneWidget);
    expect(find.byKey(const Key('record-loan-installment')), findsOneWidget);
  });

  testWidgets(
      'non-finite loan term in form and invalid persisted loan do not crash',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFinanceTheme(AppThemeStyle.abyss),
        home: const AccountFormDialog(
          initialAccount: Account(
            id: 'form_loan',
            name: 'Form Loan',
            accountType: AccountType.loan,
            reportGroup: ReportGroup.credit,
            currency: 'MYR',
            initialBalance: -12000,
            currentBalance: -12000,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '5'),
      'Infinity',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    final invalidLoan = Account(
      id: 'invalid_loan',
      name: 'Invalid Loan',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: 0,
      currentBalance: 0,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 5,
      loanTermMonths: 2400,
      loanStartDate: DateTime(2026, 1, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalInstallment,
    );
    repository = await repository.addAccount(invalidLoan);
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
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: LoanDetailScreen(account: invalidLoan, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('贷款条件待设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two loans sharing payer and date keep separate plans on upgrade and delete',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    const cash = Account(
      id: 'shared_cash',
      name: 'Shared Cash',
      accountType: AccountType.bankSaving,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      initialBalance: 50000,
      currentBalance: 50000,
    );
    final loanA = Account(
      id: 'loan_a',
      name: 'Loan A',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -12000,
      currentBalance: -12000,
      loanPrincipal: 12000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 7, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    final loanB = Account(
      id: 'loan_b',
      name: 'Loan B',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -24000,
      currentBalance: -24000,
      loanPrincipal: 24000,
      loanAnnualInterestRate: 12,
      loanTermMonths: 12,
      loanStartDate: DateTime(2026, 7, 1),
      loanPaymentDay: 15,
      loanRepaymentMethod: LoanRepaymentMethod.equalPrincipal,
    );
    repository = await repository.addAccount(cash);
    repository = await repository.addAccount(loanA);
    repository = await repository.addAccount(loanB);
    final due = DateTime(2026, 8, 15);
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'a_principal',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: loanA.id,
        amount: 1000,
        currency: 'MYR',
        transactionDate: due,
        status: TransactionStatus.planned,
        description: '贷款本金 #1',
      ),
      FinanceTransaction(
        id: 'a_interest',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 120,
        currency: 'MYR',
        transactionDate: due,
        status: TransactionStatus.planned,
        description: '贷款利息 #1',
      ),
      FinanceTransaction(
        id: 'b_principal',
        type: TransactionType.transfer,
        accountId: cash.id,
        toAccountId: loanB.id,
        amount: 2000,
        currency: 'MYR',
        transactionDate: due,
        status: TransactionStatus.planned,
        description: '贷款本金 #1',
      ),
      FinanceTransaction(
        id: 'b_interest',
        type: TransactionType.expense,
        accountId: cash.id,
        amount: 240,
        currency: 'MYR',
        transactionDate: due,
        status: TransactionStatus.planned,
        description: '贷款利息 #1',
      ),
    ]);
    repository = await _restorePreviousLoanFormat(repository);
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
          theme: buildFinanceTheme(AppThemeStyle.abyss),
          home: LoanDetailScreen(account: loanA, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final afterOpen = await container.read(financeRepositoryProvider.future);
    expect(afterOpen.transactions.map((item) => item.id).toSet(), {
      'a_principal',
      'a_interest',
      'b_principal',
      'b_interest',
    });

    await container
        .read(transactionMutationsProvider.notifier)
        .deleteTransaction('a_principal');
    final afterDelete = await container.read(financeRepositoryProvider.future);
    expect(afterDelete.transactions.map((item) => item.id).toSet(), {
      'a_interest',
      'b_principal',
      'b_interest',
    });
  });
}

Future<FinanceRepository> _restorePreviousLoanFormat(
    FinanceRepository repository) async {
  final payload = await repository.buildJsonSnapshotPayload();
  final meta = payload['meta'] as Map;
  meta.remove('loan_installment_semantics');
  return repository.restoreSyncedSnapshot(payload);
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
