import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/loan_amortization.dart';
import 'package:finance_app/src/core/models/loan_settlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server reminder fixture preserves client settlement through v3 restore',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final json = jsonDecode(
            await File('test/fixtures/loan_settlement_v3.json').readAsString())
        as Map<String, dynamic>;
    var ledger =
        await (await FinanceRepository.load(db)).restoreSyncedSnapshot(json);
    for (var pass = 0; pass < 2; pass++) {
      final loan = ledger.accounts.singleWhere((a) => a.id == 'loan');
      final period = calculateLoanAmortization(
        principal: loan.loanPrincipal!,
        annualInterestRatePercent: loan.loanAnnualInterestRate!,
        termMonths: loan.loanTermMonths!,
        startDate: loan.loanStartDate!,
        paymentDay: loan.loanPaymentDay!,
        method: loan.loanRepaymentMethod!,
      ).installments.first;
      expect(period.payment, 102);
      for (final (day, due) in [(19, 22.0), (20, 0.0), (23, 22.0)]) {
        final remaining = LoanSettlement.forLoan(
          loanId: loan.id,
          currency: loan.currency,
          transactions: ledger.transactions,
          cutoff: DateTime(2026, 11, day, 23, 59, 59),
        ).remaining(period);
        expect(remaining.principal, due, reason: 'November $day');
        expect(remaining.interest, 0);
      }
      expect({for (final a in ledger.accounts) a.id: a.currentBalance},
          {'usd': 980.0, 'myr': 78.0, 'loan': -100.0});
      if (pass == 0) {
        ledger = await ledger
            .restoreSyncedSnapshot(await ledger.buildJsonSnapshotPayload());
      }
    }
  });
}
