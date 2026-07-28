import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/utils/month_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports use actual cash movement and loan transfer uses full payment',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    for (final account in const [
      Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 5000,
      ),
      Account(
        id: 'card',
        name: 'Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -300,
      ),
      Account(
        id: 'loan',
        name: 'Loan',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: -70000,
      ),
    ]) {
      repository = await repository.addAccount(account);
    }
    final now = DateTime.now();
    final currentMonth = monthKeyFromDate(now);
    final nextDate = DateTime(now.year, now.month + 1, 23);
    final nextMonth = monthKeyFromDate(nextDate);
    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'income',
        type: TransactionType.income,
        accountId: 'cash',
        amount: 1000,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 1),
      ),
      FinanceTransaction(
        id: 'cash-spend',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 100,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 2),
      ),
      FinanceTransaction(
        id: 'card-spend',
        type: TransactionType.expense,
        accountId: 'card',
        amount: 300,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 3),
      ),
      FinanceTransaction(
        id: 'card-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'card',
        amount: 200,
        currency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 4),
      ),
      FinanceTransaction(
        id: 'loan-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'loan',
        amount: 1316,
        toAmount: 1193.67,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(now.year, now.month, 23),
      ),
      FinanceTransaction(
        id: 'future-loan-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'loan',
        amount: 1316,
        toAmount: 1195.75,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: nextDate,
        status: TransactionStatus.planned,
      ),
    ]);

    final current = repository.actualCashFlowSummaryForMonth(currentMonth);
    expect(current.inflow, 1000);
    expect(current.outflow, 1616);
    expect(current.net, -616);
    expect(repository.totalExpenseForMonth(currentMonth), 400);
    final reportMonth = repository
        .monthlySummaries(months: 12)
        .singleWhere((summary) => summary.monthKey == currentMonth);
    expect(reportMonth.income, 1000);
    expect(reportMonth.expense, 1616);

    final futureActual = repository.actualCashFlowSummaryForMonth(nextMonth);
    expect(futureActual.outflow, 0);
    final futureIncludingPlanned = repository.actualCashFlowSummaryForMonth(
      nextMonth,
      includePlanned: true,
    );
    expect(futureIncludingPlanned.outflow, 1316);
    expect(
      repository.cashFlowNetBetween(
        startInclusive: nextDate,
        endInclusive: nextDate,
      ),
      -1316,
    );

    final projection = repository
        .futureCashFlowProjection(months: 2, asOf: now)
        .singleWhere((point) => point.monthKey == nextMonth);
    expect(projection.expense, 1316);
    expect(projection.net, -1316);
  });

  test('monthly funding need adds uncovered debt without double counting',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final nextMonthDate = DateTime(now.year, now.month + 1);
    final nextMonth = monthKeyFromDate(nextMonthDate);
    final previousStatementCharge =
        DateTime(nextMonthDate.year, nextMonthDate.month - 1, 20);

    for (final account in [
      const Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.bankSaving,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 10000,
      ),
      const Account(
        id: 'card',
        name: 'Card',
        accountType: AccountType.creditCard,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        currentBalance: 0,
        creditLimit: 5000,
        statementDay: 25,
        paymentDueDay: 14,
      ),
      Account(
        id: 'loan',
        name: 'Loan',
        accountType: AccountType.loan,
        reportGroup: ReportGroup.credit,
        currency: 'MYR',
        initialBalance: -71097,
        currentBalance: -71097,
        loanPrincipal: 120000,
        loanAnnualInterestRate: 3.55,
        loanTermMonths: 108,
        loanStartDate: DateTime(2022, 5, 23),
        loanTrackingStartDate: currentMonth,
        loanPaymentDay: 23,
        loanRepaymentMethod: LoanRepaymentMethod.equalInstallment,
        loanQuotedMonthlyPayment: 1316,
      ),
    ]) {
      repository = await repository.addAccount(account);
    }

    repository = await repository.addTransactions([
      FinanceTransaction(
        id: 'card-charge',
        type: TransactionType.expense,
        accountId: 'card',
        amount: 500,
        currency: 'MYR',
        transactionDate: previousStatementCharge,
      ),
      FinanceTransaction(
        id: 'cash-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 89,
        currency: 'MYR',
        transactionDate: DateTime(nextMonthDate.year, nextMonthDate.month, 6),
      ),
      FinanceTransaction(
        id: 'planned-cash-expense',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 900,
        currency: 'MYR',
        transactionDate: DateTime(nextMonthDate.year, nextMonthDate.month, 28),
        status: TransactionStatus.planned,
      ),
      FinanceTransaction(
        id: 'planned-loan-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'loan',
        amount: 1316,
        toAmount: 1108.94,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(nextMonthDate.year, nextMonthDate.month, 23),
        status: TransactionStatus.planned,
        description: 'Car loan repayment',
      ),
    ]);

    final beforeCardPayment = repository.monthlyFundingNeedForMonth(nextMonth);
    expect(beforeCardPayment.knownCashOutflow, 2305);
    expect(beforeCardPayment.creditDue, 500);
    expect(beforeCardPayment.loanDue, 1316);
    expect(beforeCardPayment.coveredDebtPayments, 1316);
    expect(beforeCardPayment.uncoveredDebtDue, 500);
    expect(beforeCardPayment.totalCashRequired, 2805);

    repository = await repository.addTransaction(
      FinanceTransaction(
        id: 'planned-card-payment',
        type: TransactionType.transfer,
        accountId: 'cash',
        toAccountId: 'card',
        amount: 500,
        currency: 'MYR',
        toCurrency: 'MYR',
        transactionDate: DateTime(nextMonthDate.year, nextMonthDate.month, 14),
        status: TransactionStatus.planned,
        description: '信用卡还款',
      ),
    );

    final afterCardPayment = repository.monthlyFundingNeedForMonth(nextMonth);
    expect(afterCardPayment.knownCashOutflow, 2805);
    expect(afterCardPayment.coveredDebtPayments, 1816);
    expect(afterCardPayment.uncoveredDebtDue, 0);
    expect(afterCardPayment.totalCashRequired, 2805);
  });
}
