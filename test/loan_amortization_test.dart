import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart' hide Account;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/loan_amortization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loan amortization', () {
    test('equal installment keeps payment stable and clears principal', () {
      final result = calculateLoanAmortization(
        principal: 100000,
        annualInterestRatePercent: 6,
        termMonths: 12,
        startDate: DateTime(2026, 1, 31),
        paymentDay: 31,
        method: LoanRepaymentMethod.equalInstallment,
      );

      expect(result.installments, hasLength(12));
      expect(result.regularPayment, closeTo(8606.64, .01));
      expect(result.installments.first.interest, 500);
      expect(result.installments.last.remainingPrincipal, 0);
      expect(result.installments.first.dueDate, DateTime(2026, 2, 28));
      expect(result.totalPayment, closeTo(103279.72, .1));
    });

    test('equal principal payment decreases every month', () {
      final result = calculateLoanAmortization(
        principal: 12000,
        annualInterestRatePercent: 12,
        termMonths: 12,
        startDate: DateTime(2026, 1, 1),
        paymentDay: 15,
        method: LoanRepaymentMethod.equalPrincipal,
      );

      expect(result.installments.first.payment, 1120);
      expect(result.installments.last.payment, 1010);
      expect(result.installments.last.remainingPrincipal, 0);
    });

    test('flat rate uses original principal for total interest', () {
      final result = calculateLoanAmortization(
        principal: 60000,
        annualInterestRatePercent: 3,
        termMonths: 60,
        startDate: DateTime(2026, 7, 20),
        paymentDay: 20,
        method: LoanRepaymentMethod.flatRate,
      );

      expect(result.installments, hasLength(60));
      expect(result.regularPayment, 1150);
      expect(result.totalInterest, 9000);
      expect(result.totalPayment, 69000);
    });

    test('bank quoted installment drives payment and adjusts final period', () {
      final result = calculateLoanAmortization(
        principal: 10000,
        annualInterestRatePercent: 5,
        termMonths: 12,
        startDate: DateTime(2026, 1, 1),
        paymentDay: 1,
        method: LoanRepaymentMethod.equalInstallment,
        quotedMonthlyPayment: 860,
      );

      expect(result.regularPayment, 860);
      expect(result.installments.first.payment, 860);
      expect(result.installments.last.payment, isNot(860));
      expect(result.installments.last.remainingPrincipal, 0);
    });

    test('flat rate accepts bank installment and reconciles the final period',
        () {
      final result = calculateLoanAmortization(
        principal: 120000,
        annualInterestRatePercent: 2.1,
        termMonths: 108,
        startDate: DateTime(2026, 7, 21),
        paymentDay: 21,
        method: LoanRepaymentMethod.flatRate,
        quotedMonthlyPayment: 1316,
      );

      expect(result.installments, hasLength(108));
      expect(result.regularPayment, 1316);
      expect(result.installments.first.interest, 210);
      expect(result.installments.first.principal, 1106);
      expect(result.installments.last.payment, 1868);
      expect(result.totalInterest, 22680);
      expect(result.totalPayment, 142680);
      expect(result.installments.last.remainingPrincipal, 0);
    });

    test('midstream reducing-balance loan starts from reported balance', () {
      final result = calculateLoanAmortization(
        principal: 120000,
        openingPrincipal: 71097,
        annualInterestRatePercent: 2.1,
        termMonths: 108,
        startDate: DateTime(2026, 6, 30),
        paymentDay: 21,
        method: LoanRepaymentMethod.equalInstallment,
        quotedMonthlyPayment: 1316,
      );

      expect(result.installments, hasLength(57));
      expect(result.installments.first.dueDate, DateTime(2026, 7, 21));
      expect(result.installments.first.principal, 1191.58);
      expect(result.installments.first.interest, 124.42);
      expect(result.installments.last.payment, 1055.44);
      expect(result.totalInterest, 3654.44);
      expect(result.totalPayment, 74751.44);
      expect(result.installments.last.remainingPrincipal, 0);
    });
  });

  test('loan terms persist and survive full JSON export/import', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await FinanceRepository.load(database);
    final loan = Account(
      id: 'car_loan',
      name: 'Car loan',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -60000,
      currentBalance: -60000,
      loanPrincipal: 60000,
      loanAnnualInterestRate: 3,
      loanTermMonths: 60,
      loanStartDate: DateTime(2026, 7, 20),
      loanTrackingStartDate: DateTime(2026, 7, 20),
      loanPaymentDay: 20,
      loanRepaymentMethod: LoanRepaymentMethod.flatRate,
    );
    repository = await repository.addAccount(loan);

    final reloaded = await FinanceRepository.load(database);
    expect(reloaded.accounts.single.loanPrincipal, 60000);
    expect(
      reloaded.accounts.single.loanRepaymentMethod,
      LoanRepaymentMethod.flatRate,
    );
    expect(
      reloaded.accounts.single.loanTrackingStartDate,
      DateTime(2026, 7, 20),
    );

    final payload = jsonDecode(
      utf8.decode(await repository.exportJsonSnapshotBytes()),
    ) as Map<String, dynamic>;
    expect(payload['schema_version'], 9);
    final exported = (payload['accounts'] as List).single;
    expect(exported['loan_term_months'], 60);
    expect(exported['loan_repayment_method'], 'flatRate');
    expect(exported['loan_tracking_start_date'], '2026-07-20T00:00:00.000');
  });
}
