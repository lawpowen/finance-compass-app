import 'dart:math' as math;

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
    this.openStatements = const [],
  });

  final double outstandingBalance;
  final double billedBalance;
  final double unbilledBalance;
  final DateTime? statementDate;
  final DateTime dueDate;
  final bool isEstimated;

  /// Closed, unpaid statement amounts in the card's currency, oldest first.
  /// The primary amount and due date describe the first of these statements.
  final List<CreditCardStatementDue> openStatements;
}

class CreditCardStatementDue {
  const CreditCardStatementDue(this.period, this.amount);

  final CreditCardBillingPeriod period;
  final double amount;
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

/// [committedOutstanding] is the card's current debt including committed
/// future records. When it is positive but nothing falls in the billed or next
/// cycle (for example an instalment two statements ahead), the card is shown as
/// not yet billed instead of having no balance.
CreditCardDisplayState resolveCreditCardDisplayState({
  required CreditCardBillingSummary summary,
  required bool hasBilledActivity,
  DateTime? now,
  double? committedOutstanding,
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
  if (summary.unbilledBalance > epsilon ||
      (committedOutstanding ?? 0) > epsilon) {
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
    return transaction.affectsBalance &&
        transaction.accountId == account.id &&
        period.containsBilled(
            creditCardSourceBillingDate(transaction, account.id));
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
      DateTime(statementDate.year, statementDate.month, statementDate.day - 1);

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
  final cycleStartDate = DateTime(previousStatementDate.year,
      previousStatementDate.month, previousStatementDate.day + 1);
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
    final date = creditCardSourceBillingDate(transaction, account.id);
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
        !period.containsBilled(
            creditCardSourceBillingDate(transaction, accountId))) {
      continue;
    }
    amount += creditCardSourceCharge(transaction, accountId);
  }
  return amount.clamp(0, double.infinity).toDouble();
}

/// Returns the original amount printed for a statement cycle.
///
/// A manual override wins. Otherwise, when the cycle has any source record on
/// the card (charge, transfer out, refund or adjustment — even if they net to
/// zero) the cycle's net transaction amount is the statement, so an
/// overpayment after the cut never inflates it. Only when the cycle has no
/// source record at all, as in imported histories missing older purchases, a
/// repayment posted between statement cut and due date is used as evidence of
/// the paid statement amount, so such a statement never shows as zero. The
/// fallback nets reversals (negative transfers) and is clamped at zero.
double calculateCreditCardOriginalStatementAmount({
  required String accountId,
  required Iterable<FinanceTransaction> transactions,
  required CreditCardBillingPeriod period,
  double? statementAmountOverride,
}) {
  if (statementAmountOverride != null) {
    return statementAmountOverride.clamp(0, double.infinity).toDouble();
  }
  final hasSourceRecords = transactions.any(
    (transaction) =>
        transaction.affectsBalance &&
        transaction.accountId == accountId &&
        (period.containsBilled(
                creditCardSourceBillingDate(transaction, accountId)) ||
            // A documented deferral out of this period can leave a genuine
            // zero statement; a later bank payment is not evidence to replace it.
            (transaction.cardPostingDate != null &&
                period.containsBilled(transaction.transactionDate))),
  );
  if (hasSourceRecords) {
    return calculateCreditCardStatementAmount(
      accountId: accountId,
      transactions: transactions,
      period: period,
    );
  }
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
    repayments += _incomingPayment(transaction, accountId);
  }
  // A negative transfer reverses a repayment; the statement is never negative.
  return repayments.clamp(0, double.infinity).toDouble();
}

/// Signed contribution to the card's printed charges (a credit is negative).
/// A same-account transfer affects the card only by the difference of its legs.
double creditCardSourceCharge(FinanceTransaction transaction, String cardId) {
  if (transaction.accountId != cardId) return 0;
  return switch (transaction.type) {
    TransactionType.transfer => transaction.amount -
        (transaction.toAccountId == cardId ? transaction.transferInAmount : 0),
    TransactionType.expense => transaction.amount,
    TransactionType.income || TransactionType.adjustment => -transaction.amount,
  };
}

/// Only the source card uses its bank posting day. Payments received by a
/// card always retain the economic day, even when the payer is another card.
DateTime creditCardSourceBillingDate(
        FinanceTransaction transaction, String cardId) =>
    _dateOnly(transaction.accountId == cardId
        ? transaction.cardPostingDate ?? transaction.transactionDate
        : transaction.transactionDate);

DateTime estimatedCreditCardDueDate(DateTime asOf) =>
    DateTime(asOf.year, asOf.month + 1, 25);

CreditCardBillingSummary calculateCreditCardBilling({
  required Account account,
  required Iterable<FinanceTransaction> transactions,
  DateTime? now,
  double? balanceAtCutoff,
  DateTime? openingAsOf,
}) {
  assert(account.accountType == AccountType.creditCard);
  final today = _dateOnly(now ?? DateTime.now());
  final ledger = transactions.where((t) =>
      t.affectsBalance &&
      (t.accountId == account.id ||
          (t.type == TransactionType.transfer && t.toAccountId == account.id)));
  final occurred = <FinanceTransaction>[];
  var signedBalance = balanceAtCutoff ?? account.currentBalance;
  var nextConfirmed = 0.0;
  final configured = account.hasCompleteCreditCardProfile;
  final reference = calculateCreditCardBillingPeriod(
    statementDay: account.statementDay ?? 1,
    paymentDueDay: account.paymentDueDay ?? 25,
    now: today,
  );
  for (final entry in ledger) {
    final day = _dateOnly(entry.transactionDate);
    if (!day.isAfter(today)) {
      occurred.add(entry);
      continue;
    }
    final charge = creditCardSourceCharge(entry, account.id);
    if (balanceAtCutoff == null) {
      signedBalance += charge - _incomingPayment(entry, account.id);
    }
    if (reference
        .containsUnbilled(creditCardSourceBillingDate(entry, account.id))) {
      nextConfirmed += charge;
    }
  }
  final outstanding = math.max(0.0, -signedBalance);
  if (!configured) {
    return CreditCardBillingSummary(
      outstandingBalance: outstanding,
      billedBalance: outstanding,
      unbilledBalance: 0,
      dueDate: estimatedCreditCardDueDate(today),
      isEstimated: true,
    );
  }

  final charges = <DateTime, double>{};
  var firstDay = today;
  if (openingAsOf != null && openingAsOf.isBefore(firstDay)) {
    firstDay = _dateOnly(openingAsOf);
  }
  var openingDebt = -signedBalance;
  var cyclePayments = 0.0;
  final payments = <FinanceTransaction>[];
  for (final entry in occurred) {
    final day = _dateOnly(entry.transactionDate);
    final charge = creditCardSourceCharge(entry, account.id);
    final payment = _incomingPayment(entry, account.id);
    if (charge == 0 && payment == 0) continue;
    if (day.isBefore(firstDay)) firstDay = day;
    openingDebt += payment - charge;
    if (charge != 0) {
      final billingDay = creditCardSourceBillingDate(entry, account.id);
      final cut =
          creditCardChargeStatementDate(billingDay, account.statementDay!);
      if (billingDay.isAfter(today)) {
        // It already affects the signed balance and openingDebt. Until the
        // posting day a pending refund cannot pay down an older printed bill.
        if (cut == reference.nextStatementDate) nextConfirmed += charge;
      } else {
        charges[cut] = (charges[cut] ?? 0) + charge;
      }
    }
    if (payment != 0) {
      payments.add(entry);
      if (day.isAfter(reference.statementDate)) cyclePayments += payment;
    }
  }

  DateTime closedAt(DateTime day) => calculateCreditCardBillingPeriod(
        statementDay: account.statementDay!,
        paymentDueDay: account.paymentDueDay!,
        now: day,
      ).statementDate;
  var credit = math.max(0.0, -openingDebt);
  if (openingDebt > 0) {
    final cut = closedAt(firstDay);
    charges[cut] = (charges[cut] ?? 0) + openingDebt;
  }

  // Netting a reversed payment before allocating restores the most recently
  // covered statement. A reversal with no recorded original payment becomes
  // billed debt at the date of the reversal.
  payments.sort((a, b) {
    final byDate = a.transactionDate.compareTo(b.transactionDate);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });
  for (final entry in payments) {
    credit += entry.transferInAmount;
    if (credit < 0) {
      final cut = closedAt(entry.transactionDate);
      charges[cut] = (charges[cut] ?? 0) - credit;
      credit = 0;
    }
  }
  final grossUnbilled = charges[reference.nextStatementDate] ?? 0.0;
  final statementDates = charges.keys.toList()..sort();
  for (final amount in charges.values) {
    if (amount < 0) credit -= amount;
  }
  final due = <CreditCardStatementDue>[];
  var unbilled = 0.0;
  for (final date in statementDates) {
    final amount = charges[date]!;
    if (amount <= 0) continue;
    final applied = math.min(amount, credit);
    final remaining = amount - applied;
    credit -= applied;
    if (date == reference.nextStatementDate) {
      unbilled = remaining;
    } else if (!date.isAfter(reference.statementDate) && remaining >= .005) {
      final period = calculateCreditCardBillingPeriodForStatement(
        statementDay: account.statementDay!,
        paymentDueDay: account.paymentDueDay!,
        statementDate: date,
      );
      due.add(CreditCardStatementDue(period, remaining));
    }
  }

  var committed = unbilled + nextConfirmed - credit;
  // Old partial imports can have a zero materialized balance that cannot be
  // reconciled to the documented opening and available charges. Preserve the
  // confirmed cycle amount unless an actual payment or positive card balance
  // evidences its coverage. This fallback never changes the actual debt.
  if (openingDebt < 0 &&
      (openingDebt + account.initialBalance).abs() >= .005 &&
      signedBalance <= 0) {
    committed = math.max(committed,
        grossUnbilled + nextConfirmed - math.max(0.0, cyclePayments));
  }
  final oldest = due.firstOrNull;
  return CreditCardBillingSummary(
    outstandingBalance: outstanding,
    billedBalance: oldest?.amount ?? 0,
    unbilledBalance: math.max(0.0, committed),
    statementDate: oldest?.period.statementDate ?? reference.statementDate,
    dueDate: oldest?.period.dueDate ?? reference.dueDate,
    openStatements: List.unmodifiable(due),
    isEstimated: false,
  );
}

double _incomingPayment(FinanceTransaction transaction, String cardId) =>
    transaction.type == TransactionType.transfer &&
            transaction.accountId != cardId &&
            transaction.toAccountId == cardId
        ? transaction.transferInAmount
        : 0;

/// The first closing date on or after the charge's local billing day.
DateTime creditCardChargeStatementDate(DateTime date, int statementDay) {
  final day = _dateOnly(date);
  final cut = _clampedDate(day.year, day.month, statementDay);
  return day.isAfter(cut)
      ? _clampedDate(day.year, day.month + 1, statementDay)
      : cut;
}

DateTime _clampedDate(int year, int month, int day) {
  final first = DateTime(year, month, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, day.clamp(1, lastDay));
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
