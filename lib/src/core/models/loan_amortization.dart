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
      final calculatedPayment = monthlyRate == 0
          ? principal / termMonths
          : principal *
              monthlyRate *
              math.pow(1 + monthlyRate, termMonths) /
              (math.pow(1 + monthlyRate, termMonths) - 1);
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
      final totalFlatInterest =
          _money(principal * annualInterestRatePercent / 100 * termMonths / 12);
      final regularPrincipal = _money(principal / termMonths);
      final regularInterest = _money(totalFlatInterest / termMonths);
      final regularPayment = quotedMonthlyPayment == null
          ? _money(regularPrincipal + regularInterest)
          : _money(quotedMonthlyPayment);
      if (regularPayment <= regularInterest) {
        throw ArgumentError.value(
          quotedMonthlyPayment,
          'quotedMonthlyPayment',
          'Payment must be above the monthly flat interest.',
        );
      }
      var assignedInterest = 0.0;
      for (var index = 0; index < termMonths && balance > 0; index++) {
        final nextRegularPrincipal = quotedMonthlyPayment == null
            ? regularPrincipal
            : _money(regularPayment - regularInterest);
        final isFinal = index == termMonths - 1 ||
            (isMidstream && nextRegularPrincipal >= balance);
        final interest = isFinal
            ? (isMidstream
                ? regularInterest
                : _money(totalFlatInterest - assignedInterest))
            : regularInterest;
        final principalPart = isFinal
            ? balance
            : quotedMonthlyPayment == null
                ? regularPrincipal
                : _money(regularPayment - interest);
        if (!isMidstream &&
            quotedMonthlyPayment != null &&
            !isFinal &&
            principalPart >= balance) {
          throw ArgumentError.value(
            quotedMonthlyPayment,
            'quotedMonthlyPayment',
            'Payment would clear the loan before the configured term.',
          );
        }
        assignedInterest = _money(assignedInterest + interest);
        final payment = isFinal
            ? _money(principalPart + interest)
            : quotedMonthlyPayment == null
                ? _money(principalPart + interest)
                : regularPayment;
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
  }

  final totalPayment = _money(
    installments.fold<double>(0, (sum, item) => sum + item.payment),
  );
  final totalInterest = _money(
    installments.fold<double>(0, (sum, item) => sum + item.interest),
  );
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

double _money(num value) => (value * 100).round() / 100;
