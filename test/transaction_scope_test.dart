import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/credit_card_billing.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default account and investment totals stop at the current month',
      () async {
    final now = DateTime.now();
    final past = DateTime(now.year, now.month - 1, 10);
    final future = DateTime(now.year, now.month + 2, 10);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);

    repository = await repository.addAccount(
      const Account(
        id: 'epf',
        name: 'EPF',
        accountType: AccountType.pension,
        reportGroup: ReportGroup.retirement,
        currency: 'MYR',
        initialBalance: 1000,
        currentBalance: 1000,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'actual_past',
        type: TransactionType.adjustment,
        accountId: 'epf',
        amount: 100,
        currency: 'MYR',
        transactionDate: past,
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'actual_future',
        type: TransactionType.adjustment,
        accountId: 'epf',
        amount: 500,
        currency: 'MYR',
        transactionDate: future,
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'planned_future',
        type: TransactionType.adjustment,
        accountId: 'epf',
        amount: 700,
        currency: 'MYR',
        transactionDate: future,
        status: TransactionStatus.planned,
      ),
    );

    expect(repository.accounts.single.currentBalance, 1600);
    expect(repository.totalAssetsByGroup(ReportGroup.retirement), 1100);
    expect(
      repository.investmentFlowSummaryForAccount('epf').contribution,
      100,
    );
    expect(
      repository
          .investmentFlowSummaryForAccount(
            'epf',
            upToDate: DateTime(future.year, future.month + 1, 0),
          )
          .contribution,
      600,
    );

    await database.close();
  });

  test('credit-card next statement includes future actual but not planned', () {
    const card = Account(
      id: 'card',
      name: 'Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: 0,
      currentBalance: -400,
      creditLimit: 1000,
      statementDay: 12,
      paymentDueDay: 28,
    );
    final summary = calculateCreditCardBilling(
      account: card,
      now: DateTime(2026, 7, 17),
      balanceAtCutoff: -300,
      transactions: [
        FinanceTransaction(
          id: 'current',
          type: TransactionType.expense,
          accountId: 'card',
          amount: 300,
          currency: 'MYR',
          transactionDate: DateTime(2026, 7, 15),
        ),
        FinanceTransaction(
          id: 'future_actual',
          type: TransactionType.expense,
          accountId: 'card',
          amount: 100,
          currency: 'MYR',
          transactionDate: DateTime(2026, 8, 1),
        ),
        FinanceTransaction(
          id: 'future_planned',
          type: TransactionType.expense,
          accountId: 'card',
          amount: 200,
          currency: 'MYR',
          transactionDate: DateTime(2026, 8, 2),
          status: TransactionStatus.planned,
        ),
      ],
    );

    expect(summary.outstandingBalance, 300);
    expect(summary.unbilledBalance, 400);
    expect(summary.billedBalance, 0);
  });

  test('credit-card committed debt includes future actual but not planned',
      () async {
    final now = DateTime.now();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'committed_card',
        name: 'Committed card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: 0,
        currentBalance: 0,
        creditLimit: 1000,
        statementDay: 25,
        paymentDueDay: 14,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'past_actual_card',
        type: TransactionType.expense,
        accountId: 'committed_card',
        amount: 50,
        currency: 'MYR',
        transactionDate: now.subtract(const Duration(days: 1)),
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'future_actual_card',
        type: TransactionType.expense,
        accountId: 'committed_card',
        amount: 300,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month + 2, 10),
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'future_planned_card',
        type: TransactionType.expense,
        accountId: 'committed_card',
        amount: 200,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month + 2, 11),
        status: TransactionStatus.planned,
      ),
    );

    expect(repository.accountBalanceAt('committed_card', now), -50);
    expect(
      repository.creditCardCommittedOutstandingBalance('committed_card'),
      350,
    );
    expect(repository.totalAssetsByGroup(ReportGroup.credit), -350);
    expect(
      repository.displayTotalAssetsByGroup(
        ReportGroup.credit,
        cutoffDate: now,
      ),
      -50,
    );

    await database.close();
  });

  test('statement balance includes carried debt, refunds and repayments',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'uob_card',
        name: 'Lazada UOB Credit Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -4000,
        currentBalance: -4000,
        creditLimit: 15000,
        statementDay: 25,
        paymentDueDay: 14,
      ),
    );
    repository = await repository.addAccount(
      const Account(
        id: 'bank',
        name: 'Bank',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 10000,
        currentBalance: 10000,
      ),
    );
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'uob_charges',
        type: TransactionType.expense,
        accountId: 'uob_card',
        amount: 3371.32,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 17),
      ),
      FinanceTransaction(
        id: 'uob_payments',
        type: TransactionType.transfer,
        accountId: 'bank',
        toAccountId: 'uob_card',
        amount: 5887.17,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(2026, 7, 17),
      ),
      FinanceTransaction(
        id: 'uob_credits',
        type: TransactionType.adjustment,
        accountId: 'uob_card',
        amount: 1266.76,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 17),
      ),
    ]);
    final period = calculateCreditCardBillingPeriodForStatement(
      statementDay: 25,
      paymentDueDay: 14,
      statementDate: DateTime(2026, 7, 25),
    );

    expect(
      repository.creditCardStatementBalance('uob_card', period),
      closeTo(217.39, 0.001),
    );
    expect(
      calculateCreditCardOriginalStatementAmount(
        accountId: 'uob_card',
        transactions: repository.transactions,
        period: period,
      ),
      closeTo(2104.56, 0.001),
      reason: 'The printed statement total stays separate from remaining debt.',
    );
  });

  test('forecast starts at today and adds future actual and planned once',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var repository = await FinanceRepository.load(database);
    repository = await repository.addAccount(
      const Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        initialBalance: 1000,
        currentBalance: 1000,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'future_income',
        type: TransactionType.income,
        accountId: 'cash',
        amount: 500,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 20),
        status: TransactionStatus.actual,
      ),
    );
    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'future_plan',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 200,
        currency: 'MYR',
        transactionDate: DateTime(2026, 7, 25),
        status: TransactionStatus.planned,
      ),
    );

    final projection = repository.futureCashFlowProjection(
      months: 1,
      asOf: DateTime(2026, 7, 17),
    );
    expect(projection.single.income, 500);
    expect(projection.single.expense, 200);
    expect(projection.single.endingCash, 1300);

    await database.close();
  });
}
