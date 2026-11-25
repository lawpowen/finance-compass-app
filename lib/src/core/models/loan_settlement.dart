import 'loan_amortization.dart';
import 'transaction.dart';

/// Amounts credited to each installment in loan-currency cents.
class LoanSettlement {
  LoanSettlement._(this._credits);

  final Map<int, ({int principal, int interest})> _credits;

  factory LoanSettlement.forLoan({
    required String loanId,
    required String currency,
    required Iterable<FinanceTransaction> transactions,
    DateTime? cutoff,
    bool includePlanned = false,
  }) {
    final credits = <int, ({int principal, int interest})>{};
    final loanCurrency = currency.trim().toUpperCase();
    for (final tx in transactions) {
      if ((cutoff != null && tx.transactionDate.isAfter(cutoff)) ||
          (!tx.affectsBalance && !includePlanned)) {
        continue;
      }
      final int number;
      final int principal;
      final int interest;
      if (tx.loanInstallmentNumber != null &&
          tx.type == TransactionType.transfer &&
          tx.toAccountId == loanId &&
          tx.transferInCurrency.trim().toUpperCase() == loanCurrency) {
        number = tx.loanInstallmentNumber!;
        principal = _cents(tx.toAmount!);
        interest = _cents(tx.installmentPaymentInLoanCurrency) - principal;
      } else if (tx.legacyLoanId == loanId &&
          tx.legacyLoanPartNumber != null &&
          tx.currency.trim().toUpperCase() == loanCurrency) {
        number = tx.legacyLoanPartNumber!;
        if (tx.type == TransactionType.transfer && tx.toAccountId == loanId) {
          principal = _cents(tx.toAmount ?? tx.amount);
          interest = 0;
        } else if (tx.type == TransactionType.expense) {
          interest = _cents(tx.amount);
          principal = 0;
        } else {
          continue;
        }
      } else {
        continue;
      }
      final previous = credits[number];
      credits[number] = (
        principal: (previous?.principal ?? 0) + principal,
        interest: (previous?.interest ?? 0) + interest,
      );
    }
    return LoanSettlement._(credits);
  }

  LoanInstallment remaining(LoanInstallment due) {
    final paid = _credits[due.number];
    final principal = _unpaid(_cents(due.principal), paid?.principal ?? 0);
    final interest = _unpaid(_cents(due.interest), paid?.interest ?? 0);
    return LoanInstallment(
      number: due.number,
      dueDate: due.dueDate,
      payment: (principal + interest) / 100,
      principal: principal / 100,
      interest: interest / 100,
      remainingPrincipal: due.remainingPrincipal,
    );
  }

  static int _cents(double amount) => (amount * 100).round();
  static int _unpaid(int due, int paid) => due - paid.clamp(0, due).toInt();
}

/// Subtract already-posted future payments before offering another debit. A
/// future reversal cannot increase today's outstanding principal or interest.
LoanInstallment installmentAvailableToRecord(
    LoanInstallment due, LoanSettlement occurred, LoanSettlement allActuals) {
  final now = occurred.remaining(due);
  final booked = allActuals.remaining(due);
  final principal =
      now.principal < booked.principal ? now.principal : booked.principal;
  final interest =
      now.interest < booked.interest ? now.interest : booked.interest;
  return LoanInstallment(
      number: due.number,
      dueDate: due.dueDate,
      principal: principal,
      interest: interest,
      payment: ((principal * 100).round() + (interest * 100).round()) / 100,
      remainingPrincipal: due.remainingPrincipal);
}

/// Contract amounts that still have no actual or planned payment anywhere
/// in the ledger. Future confirmed payments already cover their own plans.
List<LoanInstallment> unplannedLoanInstallments({
  required String loanId,
  required String currency,
  required Iterable<FinanceTransaction> transactions,
  required LoanAmortizationSchedule schedule,
}) {
  final allocated = LoanSettlement.forLoan(
    loanId: loanId,
    currency: currency,
    transactions: transactions,
    includePlanned: true,
  );
  return schedule.installments
      .map(allocated.remaining)
      .where((item) => item.payment > 0)
      .toList();
}
