import 'package:finance_app/src/core/models/loan_amortization.dart';
import 'package:finance_app/src/core/models/loan_settlement.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repayment records retain the precise entries behind each installment',
      () {
    final morning = DateTime(2026, 11, 19, 9);
    final later = DateTime(2026, 11, 20);
    FinanceTransaction split(
            String id, DateTime date, double total, double principal,
            {String loan = 'loan',
            int? installment = 1,
            TransactionStatus status = TransactionStatus.actual}) =>
        FinanceTransaction(
          id: id,
          type: TransactionType.transfer,
          accountId: 'usd-bank',
          toAccountId: loan,
          amount: total / 4,
          currency: 'USD',
          toCurrency: 'MYR',
          loanPaymentAmount: total,
          toAmount: principal,
          loanInstallmentNumber: installment,
          transactionDate: date,
          status: status,
        );
    final payment = split('a', morning, 80, 75);
    final reversal =
        split('b', morning, -12, -10, status: TransactionStatus.settled);
    final future = split('c', later, 30, 25);
    final entries = [
      future,
      reversal,
      payment,
      split('plan', morning, 100, 90, status: TransactionStatus.planned),
      split('other-loan', morning, 80, 75, loan: 'separate'),
      split('no-period', morning, 80, 75, installment: null),
      split('period-two', morning, 80, 75, installment: 2),
    ];
    final due = LoanInstallment(
        number: 1,
        dueDate: later,
        payment: 110,
        principal: 100,
        interest: 10,
        remainingPrincipal: 0);
    LoanSettlement settlement(
            {DateTime? cutoff,
            bool includeRecords = true,
            bool includePlanned = false}) =>
        LoanSettlement.forLoan(
            loanId: 'loan',
            currency: 'MYR',
            transactions: entries,
            cutoff: cutoff,
            includeRecords: includeRecords,
            includePlanned: includePlanned);

    final posted = settlement(cutoff: morning);
    final records = posted.recordsFor(1);
    expect(records.map((r) => r.transaction.id), ['a', 'b']);
    expect(records.first.transaction, same(payment));
    expect(records.map((r) => (r.principalCents, r.interestCents)),
        [(7500, 500), (-1000, -200)]);
    expect(posted.remaining(due).payment, 42);
    expect(
        settlement(includeRecords: false, cutoff: morning)
            .remaining(due)
            .payment,
        42);
    expect(settlement(includeRecords: false).recordsFor(1), isEmpty);
    expect(() => records.clear(), throwsUnsupportedError);
    expect(posted.recordsFor(2).single.transaction.id, 'period-two');
    expect(posted.recordsFor(3), isEmpty);
    expect(settlement().recordsFor(1).map((r) => r.transaction.id),
        ['c', 'a', 'b']);
    expect(
        settlement(includePlanned: true)
            .recordsFor(1)
            .map((r) => r.transaction.id),
        ['c', 'a', 'b', 'plan']);
  });

  test(
      'legacy principal and interest keep their original transaction identities',
      () {
    final date = DateTime(2026, 11, 1);
    final entries = [
      FinanceTransaction(
          id: 'principal',
          type: TransactionType.transfer,
          accountId: 'payer',
          toAccountId: 'loan',
          amount: 80,
          currency: 'MYR',
          transactionDate: date,
          legacyLoanPartNumber: 2,
          legacyLoanId: 'loan'),
      FinanceTransaction(
          id: 'interest',
          type: TransactionType.expense,
          accountId: 'payer',
          amount: 1.63,
          currency: 'MYR',
          transactionDate: date,
          legacyLoanPartNumber: 2,
          legacyLoanId: 'loan'),
    ];
    final result = LoanSettlement.forLoan(
        loanId: 'loan',
        currency: 'MYR',
        transactions: entries,
        includeRecords: true);
    final records = result.recordsFor(2);
    expect(
        records
            .map((r) => (r.transaction.id, r.principalCents, r.interestCents)),
        [('interest', 0, 163), ('principal', 8000, 0)]);
  });
}
