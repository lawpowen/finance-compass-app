import 'account.dart';
import 'transaction.dart';

class CreditCardBillingSummary {
  const CreditCardBillingSummary({
    required this.outstandingBalance,
    required this.billedBalance,
    required this.unbilledBalance,
    required this.dueDate,
    required this.isEstimated,
    this.statementDate,
  });

  final double outstandingBalance;
  final double billedBalance;
  final double unbilledBalance;
  final DateTime? statementDate;
  final DateTime dueDate;
  final bool isEstimated;
}

enum CreditCardDisplayState {
  profileIncomplete,
  noBalance,
  unbilledOnly,
  paidThisCycle,
  paymentDue,
  dueToday,
  overdue,
}

CreditCardDisplayState resolveCreditCardDisplayState({
  required CreditCardBillingSummary summary,
  required bool hasBilledActivity,
  DateTime? now,
}) {
  if (summary.isEstimated) {
    return CreditCardDisplayState.profileIncomplete;
  }
  const epsilon = 0.005;
  final today = _dateOnly(now ?? DateTime.now());
  if (summary.billedBalance > epsilon) {
    final dueDate = _dateOnly(summary.dueDate);
    if (dueDate.isBefore(today)) return CreditCardDisplayState.overdue;
    if (dueDate == today) return CreditCardDisplayState.dueToday;
    return CreditCardDisplayState.paymentDue;
  }
  if (hasBilledActivity) {
    return CreditCardDisplayState.paidThisCycle;
  }
  if (summary.unbilledBalance > epsilon) {
    return CreditCardDisplayState.unbilledOnly;
  }
  return CreditCardDisplayState.noBalance;
}

bool hasCreditCardBilledActivity({
  required Account account,
  required Iterable<FinanceTransaction> transactions,
  DateTime? now,
}) {
  if (!account.hasCompleteCreditCardProfile) return false;
  final today = _dateOnly(now ?? DateTime.now());
  final period = calculateCreditCardBillingPeriod(
    statementDay: account.statementDay!,
    paymentDueDay: account.paymentDueDay!,
    now: today,
  );
  return transactions.any((transaction) {
    final transactionDate = _dateOnly(transaction.transactionDate);
    return transaction.affectsBalance &&
        !transactionDate.isAfter(today) &&
        transaction.accountId == account.id &&
        (transaction.type == TransactionType.expense ||
            transaction.type == TransactionType.transfer) &&
        period.containsBilled(transactionDate);
  });
}

class CreditCardBillingPeriod {
  const CreditCardBillingPeriod({
    required this.cycleStartDate,
    required this.statementDate,
    required this.dueDate,
    required this.nextStatementDate,
  });

  final DateTime cycleStartDate;
  final DateTime statementDate;
  final DateTime dueDate;
  final DateTime nextStatementDate;

  /// The user-facing bill month. A statement cut on the first day belongs to
  /// the month that just ended; other statement days remain in their calendar
  /// month as expected.
  DateTime get billingMonthDate =>
      statementDate.subtract(const Duration(days: 1));

  bool containsBilled(DateTime value) {
    final date = _dateOnly(value);
    return !date.isBefore(cycleStartDate) && !date.isAfter(statementDate);
  }

  bool containsUnbilled(DateTime value) {
    final date = _dateOnly(value);
    return date.isAfter(statementDate) && !date.isAfter(nextStatementDate);
  }
}

CreditCardBillingPeriod calculateCreditCardBillingPeriod({
  required int statementDay,
  required int paymentDueDay,
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  var statementDate = _clampedDate(today.year, today.month, statementDay);
  if (statementDate.isAfter(today)) {
    statementDate = _clampedDate(today.year, today.month - 1, statementDay);
  }
  return calculateCreditCardBillingPeriodForStatement(
    statementDay: statementDay,
    paymentDueDay: paymentDueDay,
    statementDate: statementDate,
  );
}

CreditCardBillingPeriod calculateCreditCardBillingPeriodForStatement({
  required int statementDay,
  required int paymentDueDay,
  required DateTime statementDate,
}) {
  final normalizedStatementDate = _clampedDate(
    statementDate.year,
    statementDate.month,
    statementDay,
  );
  final previousStatementDate = _clampedDate(
    normalizedStatementDate.year,
    normalizedStatementDate.month - 1,
    statementDay,
  );
  final cycleStartDate = previousStatementDate.add(const Duration(days: 1));
  final nextStatementDate = _clampedDate(
    normalizedStatementDate.year,
    normalizedStatementDate.month + 1,
    statementDay,
  );
  var dueDate = _clampedDate(
    normalizedStatementDate.year,
    normalizedStatementDate.month,
    paymentDueDay,
  );
  if (!dueDate.isAfter(normalizedStatementDate)) {
    dueDate = _clampedDate(
      normalizedStatementDate.year,
      normalizedStatementDate.month + 1,
      paymentDueDay,
    );
  }
  return CreditCardBillingPeriod(
    cycleStartDate: cycleStartDate,
    statementDate: normalizedStatementDate,
    dueDate: dueDate,
    nextStatementDate: nextStatementDate,
  );
}

List<CreditCardBillingPeriod> availableCreditCardBillingPeriods({
  required Account account,
  required Iterable<FinanceTransaction> transactions,
  DateTime? now,
  int maximumPeriods = 120,
}) {
  if (!account.hasCompleteCreditCardProfile || maximumPeriods <= 0) {
    return const [];
  }
  final today = _dateOnly(now ?? DateTime.now());
  final relevantTransactions = transactions.where((transaction) {
    if (!transaction.affectsBalance) return false;
    return transaction.accountId == account.id ||
        (transaction.type == TransactionType.transfer &&
            transaction.toAccountId == account.id);
  }).toList();

  DateTime? earliestDate;
  DateTime? latestFutureChargeDate;
  for (final transaction in relevantTransactions) {
    final date = _dateOnly(transaction.transactionDate);
    if (earliestDate == null || date.isBefore(earliestDate)) {
      earliestDate = date;
    }
    if (transaction.accountId == account.id && date.isAfter(today)) {
      if (latestFutureChargeDate == null ||
          date.isAfter(latestFutureChargeDate)) {
        latestFutureChargeDate = date;
      }
    }
  }

  final current = calculateCreditCardBillingPeriod(
    statementDay: account.statementDay!,
    paymentDueDay: account.paymentDueDay!,
    now: today,
  );
  final futurePeriods = <CreditCardBillingPeriod>[];
  var futureCursor = current;
  while (latestFutureChargeDate != null &&
      latestFutureChargeDate.isAfter(futureCursor.statementDate) &&
      futurePeriods.length < maximumPeriods - 1) {
    futureCursor = calculateCreditCardBillingPeriodForStatement(
      statementDay: account.statementDay!,
      paymentDueDay: account.paymentDueDay!,
      statementDate: DateTime(
        futureCursor.statementDate.year,
        futureCursor.statementDate.month + 1,
        1,
      ),
    );
    futurePeriods.add(futureCursor);
  }

  final periods = <CreditCardBillingPeriod>[...futurePeriods, current];
  var cursor = current;
  while (earliestDate != null &&
      earliestDate.isBefore(cursor.cycleStartDate) &&
      periods.length < maximumPeriods) {
    cursor = calculateCreditCardBillingPeriodForStatement(
      statementDay: account.statementDay!,
      paymentDueDay: account.paymentDueDay!,
      statementDate: DateTime(
        cursor.statementDate.year,
        cursor.statementDate.month - 1,
        1,
      ),
    );
    periods.add(cursor);
  }
  return periods;
}

double calculateCreditCardStatementAmount({
  required String accountId,
  required Iterable<FinanceTransaction> transactions,
  required CreditCardBillingPeriod period,
}) {
  var amount = 0.0;
  for (final transaction in transactions) {
    if (!transaction.affectsBalance ||
        transaction.accountId != accountId ||
        !period.containsBilled(transaction.transactionDate)) {
      continue;
    }
    switch (transaction.type) {
      case TransactionType.expense:
      case TransactionType.transfer:
        amount += transaction.amount;
      case TransactionType.income:
      case TransactionType.adjustment:
        amount -= transaction.amount;
    }
  }
  return amount.clamp(0, double.infinity).toDouble();
}

/// Returns the original amount printed for a statement cycle.
///
/// The transaction sum is the primary source. For imported histories where
/// older purchase rows are incomplete, a repayment posted between statement
/// cut and due date is retained as evidence of the paid statement amount. A
/// later repayment therefore never turns a historical statement into zero.
double calculateCreditCardOriginalStatementAmount({
  required String accountId,
  required Iterable<FinanceTransaction> transactions,
  required CreditCardBillingPeriod period,
  double? statementAmountOverride,
}) {
  if (statementAmountOverride != null) {
    return statementAmountOverride.clamp(0, double.infinity).toDouble();
  }
  final transactionAmount = calculateCreditCardStatementAmount(
    accountId: accountId,
    transactions: transactions,
    period: period,
  );
  var repayments = 0.0;
  for (final transaction in transactions) {
    final transactionDate = _dateOnly(transaction.transactionDate);
    if (!transaction.affectsBalance ||
        transaction.type != TransactionType.transfer ||
        transaction.toAccountId != accountId ||
        transactionDate.isBefore(period.statementDate) ||
        transactionDate.isAfter(period.dueDate)) {
      continue;
    }
    repayments += transaction.toAmount ?? transaction.amount;
  }
  return transactionAmount > repayments ? transactionAmount : repayments;
}

CreditCardBillingSummary calculateCreditCardBilling({
  required Account account,
  required Iterable<FinanceTransaction> transactions,
  DateTime? now,
  double? balanceAtCutoff,
}) {
  assert(account.accountType == AccountType.creditCard);
  final today = _dateOnly(now ?? DateTime.now());
  final outstanding = (-(balanceAtCutoff ?? account.currentBalance))
      .clamp(0, double.infinity)
      .toDouble();

  if (!account.hasCompleteCreditCardProfile) {
    return CreditCardBillingSummary(
      outstandingBalance: outstanding,
      billedBalance: outstanding,
      unbilledBalance: 0,
      dueDate: _clampedDate(today.year, today.month + 1, 25),
      isEstimated: true,
    );
  }

  final period = calculateCreditCardBillingPeriod(
    statementDay: account.statementDay!,
    paymentDueDay: account.paymentDueDay!,
    now: today,
  );
  final statementDate = period.statementDate;

  var occurredUnbilled = 0.0;
  var repaymentsAfterStatement = 0.0;
  for (final transaction in transactions) {
    if (!transaction.affectsBalance ||
        _dateOnly(transaction.transactionDate).isAfter(today) ||
        !_dateOnly(transaction.transactionDate).isAfter(statementDate)) {
      continue;
    }
    if (transaction.type == TransactionType.transfer &&
        transaction.toAccountId == account.id) {
      // A transfer into the card is a repayment and reduces the billed balance.
      repaymentsAfterStatement += transaction.transferInAmount;
      continue;
    }
    if (transaction.accountId != account.id) continue;
    switch (transaction.type) {
      case TransactionType.expense:
      case TransactionType.transfer:
        occurredUnbilled += transaction.amount;
      case TransactionType.income:
      case TransactionType.adjustment:
        occurredUnbilled -= transaction.amount;
    }
  }

  final normalizedOccurredUnbilled =
      occurredUnbilled.clamp(0, outstanding).toDouble();
  final billed = (outstanding - normalizedOccurredUnbilled)
      .clamp(0, double.infinity)
      .toDouble();
  // Once the billed statement has been cleared, any remaining repayment or
  // credit belongs to the next statement cycle.  Keep the next-statement
  // figure on the committed-cycle basis, but deduct that surplus so the UI
  // does not show gross new spending after it has already been offset.
  final impliedCreditAppliedToUnbilled =
      (occurredUnbilled - outstanding).clamp(0, double.infinity).toDouble();
  final creditAppliedToUnbilled = impliedCreditAppliedToUnbilled
      .clamp(0, repaymentsAfterStatement)
      .toDouble();
  final nextPeriod = calculateCreditCardBillingPeriodForStatement(
    statementDay: account.statementDay!,
    paymentDueDay: account.paymentDueDay!,
    statementDate: period.nextStatementDate,
  );
  final committedNextStatement = calculateCreditCardStatementAmount(
    accountId: account.id,
    transactions: transactions,
    period: nextPeriod,
  );
  final remainingCommittedNextStatement =
      (committedNextStatement - creditAppliedToUnbilled)
          .clamp(0, double.infinity)
          .toDouble();
  return CreditCardBillingSummary(
    outstandingBalance: outstanding,
    billedBalance: billed,
    unbilledBalance: remainingCommittedNextStatement,
    statementDate: statementDate,
    dueDate: period.dueDate,
    isEstimated: false,
  );
}

DateTime _clampedDate(int year, int month, int day) {
  final first = DateTime(year, month, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, day.clamp(1, lastDay));
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
