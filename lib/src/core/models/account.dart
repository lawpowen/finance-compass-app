enum AccountType {
  cash,
  bankSaving,
  eWallet,
  creditCard,
  moneyMarketFund,
  pension,
  stock,
  crypto,
  trading,
  fund,
  loan,
  other,
}

enum ReportGroup {
  cash,
  credit,
  investment,
  retirement,
}

/// The first group is the default for a new account of this type.
List<ReportGroup> allowedReportGroups(AccountType type) => switch (type) {
      AccountType.creditCard || AccountType.loan => const [ReportGroup.credit],
      AccountType.cash ||
      AccountType.bankSaving ||
      AccountType.eWallet =>
        const [ReportGroup.cash],
      AccountType.pension => const [ReportGroup.retirement],
      AccountType.stock ||
      AccountType.crypto ||
      AccountType.trading ||
      AccountType.fund =>
        const [ReportGroup.investment, ReportGroup.retirement],
      AccountType.moneyMarketFund || AccountType.other => const [
          ReportGroup.investment,
          ReportGroup.cash,
          ReportGroup.retirement,
        ],
    };

ReportGroup effectiveReportGroupFor(AccountType type, ReportGroup stored) {
  final groups = allowedReportGroups(type);
  return groups.contains(stored) ? stored : groups.first;
}

enum LoanRepaymentMethod {
  equalInstallment,
  equalPrincipal,
  flatRate,
}

/// Loan contract and tracking dates represent local calendar days.
bool validLoanTrackingDate(DateTime contract, DateTime tracking) =>
    !DateTime(tracking.year, tracking.month, tracking.day)
        .isBefore(DateTime(contract.year, contract.month, contract.day));

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.reportGroup,
    required this.currency,
    required this.currentBalance,
    this.institution,
    this.note,
    this.initialBalance = 0,
    this.isActive = true,
    this.creditLimit,
    this.statementDay,
    this.paymentDueDay,
    this.loanPrincipal,
    this.loanAnnualInterestRate,
    this.loanTermMonths,
    this.loanStartDate,
    this.loanTrackingStartDate,
    this.loanPaymentDay,
    this.loanRepaymentMethod,
    this.loanQuotedMonthlyPayment,
  });

  final String id;
  final String name;
  final AccountType accountType;
  final ReportGroup reportGroup;
  final String currency;
  final double initialBalance;
  final double currentBalance;
  final String? institution;
  final String? note;
  final bool isActive;
  final double? creditLimit;
  final int? statementDay;
  final int? paymentDueDay;
  final double? loanPrincipal;
  final double? loanAnnualInterestRate;
  final int? loanTermMonths;
  final DateTime? loanStartDate;
  final DateTime? loanTrackingStartDate;
  final int? loanPaymentDay;
  final LoanRepaymentMethod? loanRepaymentMethod;
  final double? loanQuotedMonthlyPayment;

  ReportGroup get effectiveReportGroup =>
      effectiveReportGroupFor(accountType, reportGroup);

  bool get hasCompleteCreditCardProfile =>
      accountType != AccountType.creditCard ||
      (creditLimit != null && statementDay != null && paymentDueDay != null);

  bool get hasCompleteLoanProfile =>
      accountType != AccountType.loan ||
      (loanPrincipal != null &&
          loanPrincipal!.isFinite &&
          loanPrincipal! > 0 &&
          loanAnnualInterestRate != null &&
          loanAnnualInterestRate!.isFinite &&
          loanAnnualInterestRate! >= 0 &&
          loanTermMonths != null &&
          loanTermMonths! > 0 &&
          loanTermMonths! <= 1200 &&
          loanStartDate != null &&
          (loanTrackingStartDate == null ||
              validLoanTrackingDate(loanStartDate!, loanTrackingStartDate!)) &&
          loanPaymentDay != null &&
          loanPaymentDay! >= 1 &&
          loanPaymentDay! <= 31 &&
          loanRepaymentMethod != null &&
          initialBalance.isFinite &&
          (loanQuotedMonthlyPayment == null ||
              (loanQuotedMonthlyPayment!.isFinite &&
                  loanQuotedMonthlyPayment! > 0)));
}
