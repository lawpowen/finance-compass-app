import 'dart:math' as math;

import 'account.dart';

class LoanInstallment {
  const LoanInstallment({
    required this.number,
    required this.dueDate,
    required this.payment,
    required this.principal,
    required this.interest,
    required this.remainingPrincipal,
  });

  final int number;
  final DateTime dueDate;
  final double payment;
  final double principal;
  final double interest;
  final double remainingPrincipal;
}

class LoanAmortizationSchedule {
  const LoanAmortizationSchedule({
    required this.installments,
    required this.regularPayment,
    required this.totalPayment,
    required this.totalInterest,
  });

  final List<LoanInstallment> installments;
  final double regularPayment;
  final double totalPayment;
  final double totalInterest;
}

LoanAmortizationSchedule calculateLoanAmortization({
  required double principal,
  required double annualInterestRatePercent,
  required int termMonths,
  required DateTime startDate,
  required int paymentDay,
  required LoanRepaymentMethod method,
  double? quotedMonthlyPayment,
  double? openingPrincipal,
}) {
  if (!principal.isFinite || principal <= 0) {
    throw ArgumentError.value(principal, 'principal', 'Must be above zero');
  }
  if (!annualInterestRatePercent.isFinite || annualInterestRatePercent < 0) {
    throw ArgumentError.value(
      annualInterestRatePercent,
      'annualInterestRatePercent',
      'Must not be negative',
    );
  }
  if (termMonths <= 0 || termMonths > 1200) {
    throw ArgumentError.value(termMonths, 'termMonths', 'Must be 1–1200');
  }
  if (paymentDay < 1 || paymentDay > 31) {
    throw ArgumentError.value(paymentDay, 'paymentDay', 'Must be 1–31');
  }
  if (quotedMonthlyPayment != null &&
      (!quotedMonthlyPayment.isFinite || quotedMonthlyPayment <= 0)) {
    throw ArgumentError.value(
      quotedMonthlyPayment,
      'quotedMonthlyPayment',
      'Must be above zero',
    );
  }
  if (quotedMonthlyPayment != null &&
      method == LoanRepaymentMethod.equalPrincipal) {
    throw ArgumentError(
      'A quoted monthly payment is not supported for equal principal loans.',
    );
  }
  if (openingPrincipal != null &&
      (!openingPrincipal.isFinite ||
          openingPrincipal <= 0 ||
          openingPrincipal > principal)) {
    throw ArgumentError.value(
      openingPrincipal,
      'openingPrincipal',
      'Must be above zero and no more than the contract principal.',
    );
  }

  final monthlyRate = annualInterestRatePercent / 100 / 12;
  final firstDueMonth = DateTime(startDate.year, startDate.month + 1, 1);
  final installments = <LoanInstallment>[];
  var balance = _money(openingPrincipal ?? principal);
  final isMidstream = balance < _money(principal);

  switch (method) {
    case LoanRepaymentMethod.equalInstallment:
      final discount = math.pow(1 + monthlyRate, -termMonths).toDouble();
      final denominator = 1 - discount;
      final calculatedPayment = monthlyRate == 0
          ? principal / termMonths
          : principal * monthlyRate / denominator;
      if (!calculatedPayment.isFinite) {
        throw ArgumentError('Loan payment calculation overflowed.');
      }
      final regularPayment = _money(quotedMonthlyPayment ?? calculatedPayment);
      final firstInterest = _money(balance * monthlyRate);
      if (regularPayment <= firstInterest) {
        throw ArgumentError.value(
          quotedMonthlyPayment,
          'quotedMonthlyPayment',
          'Payment must be above the first month interest.',
        );
      }
      for (var index = 0; index < termMonths && balance > 0; index++) {
        final interest = _money(balance * monthlyRate);
        final isFinal = index == termMonths - 1 ||
            (isMidstream && regularPayment >= _money(balance + interest));
        final payment = isFinal
            ? _money(balance + interest)
            : math.min(regularPayment, _money(balance + interest)).toDouble();
        if (!isMidstream &&
            quotedMonthlyPayment != null &&
            !isFinal &&
            regularPayment >= _money(balance + interest)) {
          throw ArgumentError.value(
            quotedMonthlyPayment,
            'quotedMonthlyPayment',
            'Payment would clear the loan before the configured term.',
          );
        }
        final principalPart = _money(math.min(balance, payment - interest));
        balance = _money(math.max(0, balance - principalPart));
        installments.add(
          LoanInstallment(
            number: index + 1,
            dueDate: _clampedMonthDate(
              firstDueMonth.year,
              firstDueMonth.month + index,
              paymentDay,
            ),
            payment: payment,
            principal: principalPart,
            interest: interest,
            remainingPrincipal: balance,
          ),
        );
      }
    case LoanRepaymentMethod.equalPrincipal:
      final regularPrincipal = _money(principal / termMonths);
      for (var index = 0; index < termMonths && balance > 0; index++) {
        final interest = _money(balance * monthlyRate);
        final principalPart = index == termMonths - 1 ||
                (isMidstream && regularPrincipal >= balance)
            ? balance
            : math.min(balance, regularPrincipal).toDouble();
        final payment = _money(principalPart + interest);
        balance = _money(math.max(0, balance - principalPart));
        installments.add(
          LoanInstallment(
            number: index + 1,
            dueDate: _clampedMonthDate(
              firstDueMonth.year,
              firstDueMonth.month + index,
              paymentDay,
            ),
            payment: payment,
            principal: principalPart,
            interest: interest,
            remainingPrincipal: balance,
          ),
        );
      }
    case LoanRepaymentMethod.flatRate:
      final contractCents = _moneyCents(principal);
      final interestCents = _moneyCents(
          principal * annualInterestRatePercent / 100 * termMonths / 12);
      var remainingCents = _moneyCents(openingPrincipal ?? principal);
      final quoteCents = quotedMonthlyPayment == null
          ? null
          : _moneyCents(quotedMonthlyPayment);
      if (remainingCents == 0) {
        throw ArgumentError('Opening principal must be at least one cent.');
      }
      if (quoteCents != null && quoteCents <= interestCents ~/ termMonths) {
        throw ArgumentError.value(
          quotedMonthlyPayment,
          'quotedMonthlyPayment',
          'Payment must be above the monthly flat interest.',
        );
      }
      for (var number = 1;
          number <= termMonths && remainingCents > 0;
          number++) {
        final interest = _installmentCents(interestCents, termMonths, number);
        final scheduledPrincipal = quoteCents == null
            ? _installmentCents(contractCents, termMonths, number)
            : quoteCents - interest;
        final isFinal = number == termMonths;
        if (!isMidstream &&
            quoteCents != null &&
            !isFinal &&
            scheduledPrincipal >= remainingCents) {
          throw ArgumentError.value(
            quotedMonthlyPayment,
            'quotedMonthlyPayment',
            'Payment would clear the loan before the configured term.',
          );
        }
        final principalPart = isFinal
            ? remainingCents
            : math.min(remainingCents, scheduledPrincipal);
        remainingCents -= principalPart;
        installments.add(
          LoanInstallment(
            number: number,
            dueDate: _clampedMonthDate(
              firstDueMonth.year,
              firstDueMonth.month + number - 1,
              paymentDay,
            ),
            payment: (principalPart + interest) / 100,
            principal: principalPart / 100,
            interest: interest / 100,
            remainingPrincipal: remainingCents / 100,
          ),
        );
      }
  }

  final totalPayment = installments.fold<int>(
          0, (sum, item) => sum + _moneyCents(item.payment)) /
      100;
  final totalInterest = installments.fold<int>(
          0, (sum, item) => sum + _moneyCents(item.interest)) /
      100;
  return LoanAmortizationSchedule(
    installments: List.unmodifiable(installments),
    regularPayment: installments.isEmpty ? 0 : installments.first.payment,
    totalPayment: totalPayment,
    totalInterest: totalInterest,
  );
}

DateTime _clampedMonthDate(int year, int month, int day) {
  final first = DateTime(year, month, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, day.clamp(1, lastDay));
}

// Each period receives the difference between two cumulative integer shares.
// Splitting only the remainder keeps intermediate products small on Web.
int _installmentCents(int total, int periods, int number) {
  final extra = total % periods;
  return total ~/ periods +
      (number * extra ~/ periods) -
      ((number - 1) * extra ~/ periods);
}

int _moneyCents(num value) {
  final scaled = value * 100;
  if (!scaled.isFinite || scaled.abs() > 9007199254740991) {
    throw ArgumentError('Money exceeds the supported cent precision.');
  }
  return scaled.round();
}

double _money(num value) => _moneyCents(value) / 100;

/// Attempts to build the amortization schedule for [account], returning `null`
/// when required terms are missing or mathematically invalid.
LoanAmortizationSchedule? tryCalculateLoanScheduleForAccount(Account account) {
  if (!account.hasCompleteLoanProfile) {
    return null;
  }
  final openingPrincipal = account.initialBalance.abs();
  if (!openingPrincipal.isFinite || openingPrincipal <= 0) {
    return null;
  }
  try {
    return calculateLoanAmortization(
      principal: account.loanPrincipal!,
      annualInterestRatePercent: account.loanAnnualInterestRate!,
      termMonths: account.loanTermMonths!,
      startDate: account.loanTrackingStartDate ?? account.loanStartDate!,
      paymentDay: account.loanPaymentDay!,
      method: account.loanRepaymentMethod!,
      quotedMonthlyPayment: account.loanQuotedMonthlyPayment,
      openingPrincipal: openingPrincipal,
    );
  } on ArgumentError {
    return null;
  }
}
