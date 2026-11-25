part of 'finance_repository.dart';

DateTime _fundingDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

DateTime _fundingDayEnd(DateTime date) =>
    DateTime(date.year, date.month, date.day + 1)
        .subtract(const Duration(microseconds: 1));

class CreditCardPaymentReminder {
  const CreditCardPaymentReminder({
    required this.account,
    required this.amountDue,
    required this.amountDueInBase,
    required this.dueDate,
    required this.billingMonthDate,
  });

  final Account account;
  final double amountDue;
  final double amountDueInBase;
  final DateTime dueDate;
  final DateTime billingMonthDate;
}

List<CreditCardPaymentReminder> buildCreditCardPaymentReminders({
  required Iterable<Account> accounts,
  required List<FinanceTransaction> transactions,
  required DateTime asOf,
  required double Function(String, DateTime) balanceAt,
  required double Function(double, String) convertToBase,
}) {
  final result = <CreditCardPaymentReminder>[];
  final cutoff = _fundingDayEnd(asOf);
  for (final card in accounts
      .where((a) => a.isActive && a.accountType == AccountType.creditCard)) {
    final summary = calculateCreditCardBilling(
        account: card,
        transactions: transactions,
        now: asOf,
        balanceAtCutoff: balanceAt(card.id, cutoff));
    void add(double amount, DateTime due, DateTime billingMonth) {
      if (amount <= 0) return;
      result.add(CreditCardPaymentReminder(
          account: card,
          amountDue: amount,
          amountDueInBase: convertToBase(amount, card.currency),
          dueDate: due,
          billingMonthDate: billingMonth));
    }

    if (summary.isEstimated) {
      add(summary.billedBalance, summary.dueDate, _fundingDay(asOf));
    } else {
      for (final statement in summary.openStatements) {
        add(statement.amount, statement.period.dueDate,
            statement.period.billingMonthDate);
      }
    }
  }
  result.sort((a, b) {
    final byAmount = b.amountDueInBase.compareTo(a.amountDueInBase);
    if (byAmount != 0) return byAmount;
    final byDue = a.dueDate.compareTo(b.dueDate);
    return byDue == 0 ? a.account.id.compareTo(b.account.id) : byDue;
  });
  return result;
}

typedef _DebtFunding = ({double due, double uncovered});
typedef _ForecastPoint = ({double balance, _DebtFunding cardFunding});

/// The opening balance is the actual cash balance at the end of [asOf].
/// At each later sample, known cash movements and the still-uncovered bills
/// due by that day are evaluated at the *same* cutoff.
class CashFundingForecast {
  CashFundingForecast._(
      this.openingCash, this.asOf, this.endInclusive, this._project);

  final double openingCash;
  final DateTime asOf;
  final DateTime endInclusive;
  final _ForecastPoint Function(DateTime) _project;
  final _points = <DateTime, _ForecastPoint>{};

  _ForecastPoint _at(DateTime date) {
    final day = _fundingDay(date);
    if (!day.isAfter(asOf)) {
      return (balance: openingCash, cardFunding: (due: 0.0, uncovered: 0.0));
    }
    final end = day.isAfter(endInclusive) ? endInclusive : day;
    return _points.putIfAbsent(end, () => _project(end));
  }

  double balanceAt(DateTime date) => _at(date).balance;
  double get endingCash => balanceAt(endInclusive);
  double get creditDue => _at(endInclusive).cardFunding.due;
  double get uncoveredCreditDue => _at(endInclusive).cardFunding.uncovered;
}

/// Project cash at each maturity. Statement-specific replacement rights allow
/// a late scheduled cash payment to replace an estimated debit exactly once.
class _CardFundingWindow {
  _CardFundingWindow({
    required this.start,
    required this.openingAsOf,
    required this.firstPlanDay,
    required this.includeOverdue,
    required this.includePlanned,
    required Iterable<Account> accounts,
    required Iterable<FinanceTransaction> transactions,
    required this.balanceAt,
    required this.convertToBase,
  })  : _cards = {
          for (final a in accounts)
            if (a.accountType == AccountType.creditCard) a.id: a,
        },
        _cash = {
          for (final a in accounts)
            if (a.effectiveReportGroup == ReportGroup.cash) a.id,
        } {
    for (final tx in transactions) {
      if (_cards.containsKey(tx.accountId)) {
        (_ledger[tx.accountId] ??= []).add(tx);
      }
      final target = tx.toAccountId;
      if (tx.type == TransactionType.transfer &&
          target != null &&
          target != tx.accountId &&
          _cards.containsKey(target)) {
        (_ledger[target] ??= []).add(tx);
      }
    }
  }

  final DateTime start;
  final DateTime openingAsOf;
  final DateTime firstPlanDay;
  final bool includeOverdue;
  final bool includePlanned;
  final Map<String, Account> _cards;
  final Set<String> _cash;
  final double Function(String, DateTime) balanceAt;
  final double Function(double, String) convertToBase;
  final _ledger = <String, List<FinanceTransaction>>{};

  _DebtFunding Function(DateTime) timeline(DateTime end) {
    final histories = [
      for (final card in _cards.values)
        (
          currency: card.currency,
          points: _timelineForCard(card, _fundingDayEnd(end))
        ),
    ];
    return (date) {
      var due = 0.0;
      var uncovered = 0.0;
      for (final history in histories) {
        final point =
            history.points.where((p) => !p.day.isAfter(date)).lastOrNull;
        if (point == null) continue;
        due += convertToBase(point.funding.due, history.currency);
        uncovered += convertToBase(point.funding.uncovered, history.currency);
      }
      return (due: due, uncovered: uncovered);
    };
  }

  List<({DateTime day, _DebtFunding funding})> _timelineForCard(
      Account card, DateTime end) {
    if (!card.hasCompleteCreditCardProfile && !includeOverdue) return [];
    final rows = <FinanceTransaction>[];
    final grossRows = <FinanceTransaction>[];
    final events = <DateTime, List<FinanceTransaction>>{
      // The opening point displays actual bank cash. Reserve any debt that
      // is already overdue before applying the first forecast day's refunds.
      if (includeOverdue) openingAsOf: [],
      start: [],
    };
    final beforeStart = start.subtract(const Duration(microseconds: 1));
    var balance = balanceAt(card.id, beforeStart);
    bool fromCash(FinanceTransaction tx) =>
        tx.type == TransactionType.transfer &&
        tx.toAccountId == card.id &&
        _cash.contains(tx.accountId);

    for (var tx in _ledger[card.id] ?? const <FinanceTransaction>[]) {
      if (tx.transactionDate.isAfter(end)) continue;
      if (!tx.affectsBalance) {
        if (!includePlanned ||
            !fromCash(tx) ||
            tx.transactionDate.isBefore(firstPlanDay)) {
          continue;
        }
        // Only the in-memory billing projection treats the scheduled receipt as paid.
        tx = FinanceTransaction(
            id: tx.id,
            type: tx.type,
            accountId: tx.accountId,
            toAccountId: tx.toAccountId,
            amount: tx.amount,
            currency: tx.currency,
            toCurrency: tx.toCurrency,
            toAmount: tx.toAmount,
            transactionDate: tx.transactionDate);
        if (tx.transactionDate.isBefore(start)) balance += tx.transferInAmount;
      }
      if (tx.transactionDate.isBefore(start)) {
        rows.add(tx);
        grossRows.add(tx);
      } else {
        (events[_fundingDay(tx.transactionDate)] ??= []).add(tx);
      }
    }
    var grossBalance = balance;
    final estimatedOpeningDebt =
        (-balance).clamp(0.0, double.infinity).toDouble();
    final estimatedDue = DateTime(openingAsOf.year, openingAsOf.month + 1, 25);
    if (card.hasCompleteCreditCardProfile) {
      for (var month = DateTime(start.year, start.month);
          !month.isAfter(end);
          month = DateTime(month.year, month.month + 1)) {
        final lastDay = DateTime(month.year, month.month + 1, 0).day;
        final due = DateTime(
            month.year, month.month, card.paymentDueDay!.clamp(1, lastDay));
        if (!due.isBefore(start) && !due.isAfter(end)) {
          events.putIfAbsent(due, () => []);
        }
      }
    } else if (!estimatedDue.isAfter(end) && !estimatedDue.isBefore(start)) {
      events.putIfAbsent(estimatedDue, () => []);
    }

    Map<DateTime, double> dueAmounts(
        DateTime day, List<FinanceTransaction> entries, double signedBalance) {
      if (!card.hasCompleteCreditCardProfile) {
        if (day.isBefore(estimatedDue) || estimatedOpeningDebt <= 0) return {};
        var remaining = estimatedOpeningDebt;
        for (final tx
            in entries.where((t) => !t.transactionDate.isBefore(start))) {
          if (tx.type == TransactionType.transfer &&
              tx.toAccountId == card.id &&
              tx.accountId != card.id) {
            remaining -= tx.transferInAmount;
          }
          final charge = creditCardSourceCharge(tx, card.id);
          if (charge < 0) remaining += charge;
        }
        final amount = remaining
            .clamp(0.0, (-signedBalance).clamp(0.0, double.infinity))
            .toDouble();
        return amount > 0 ? {estimatedDue: amount} : {};
      }
      final billing = calculateCreditCardBilling(
          account: card,
          transactions: entries,
          now: day,
          balanceAtCutoff: signedBalance,
          openingAsOf: openingAsOf);
      return {
        for (final bill in billing.openStatements)
          if (!bill.period.dueDate.isAfter(day) &&
              (includeOverdue || !bill.period.dueDate.isBefore(start)))
            bill.period.statementDate: bill.amount,
      };
    }

    final days = events.keys.toList()..sort();
    final history = <({DateTime day, _DebtFunding funding})>[];
    final replaceable = <DateTime, double>{};
    var reserved = 0.0;
    var grossObligation = 0.0;
    for (final day in days) {
      final postings = events[day]!
        ..sort((a, b) {
          final order = a.transactionDate.compareTo(b.transactionDate);
          return order != 0 ? order : a.id.compareTo(b.id);
        });
      for (final tx in postings) {
        final incoming = tx.type == TransactionType.transfer &&
                tx.toAccountId == card.id &&
                tx.accountId != card.id
            ? tx.transferInAmount
            : 0.0;
        final delta = incoming - creditCardSourceCharge(tx, card.id);
        final cash = fromCash(tx);
        final before = delta > 0 && replaceable.isNotEmpty
            ? dueAmounts(day, rows, balance)
            : null;
        rows.add(tx);
        balance += delta;
        if (!cash) {
          grossRows.add(tx);
          grossBalance += delta;
        }
        if (before != null) {
          final after = dueAmounts(day, rows, balance);
          for (final statement in replaceable.keys.toList()) {
            final reduction =
                (before[statement] ?? 0) - (after[statement] ?? 0);
            final matched =
                reduction.clamp(0.0, replaceable[statement]!).toDouble();
            if (cash) reserved -= matched;
            // A merchant refund can settle the real statement, but cannot
            // return an earlier cash payment to the forecast's bank account.
            final left = replaceable[statement]! - matched;
            if (left < .005) {
              replaceable.remove(statement);
            } else {
              replaceable[statement] = left;
            }
          }
        }
      }

      // Scheduled cash on the maturity date is already in the real cash
      // projection. Fund any residual at day end. Prior estimated payments
      // remain on the card and may cover later bills, including via a surplus.
      var priorCredit = reserved;
      for (final bill in dueAmounts(day, rows, balance).entries) {
        final available = priorCredit.clamp(0.0, bill.value).toDouble();
        priorCredit -= available;
        final needed = bill.value - available;
        if (needed >= .005) {
          reserved += needed;
          replaceable[bill.key] = (replaceable[bill.key] ?? 0) + needed;
        }
      }
      final gross = dueAmounts(day, grossRows, grossBalance)
          .values
          .fold(0.0, (a, b) => a + b);
      if (gross > grossObligation) grossObligation = gross;
      if (reserved > grossObligation) grossObligation = reserved;
      history.add(
          (day: day, funding: (due: grossObligation, uncovered: reserved)));
    }
    return history;
  }
}
