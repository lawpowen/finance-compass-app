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

enum LoanRepaymentMethod {
  equalInstallment,
  equalPrincipal,
  flatRate,
}

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

  bool get hasCompleteCreditCardProfile =>
      accountType != AccountType.creditCard ||
      (creditLimit != null && statementDay != null && paymentDueDay != null);

  bool get hasCompleteLoanProfile =>
      accountType != AccountType.loan ||
      (loanPrincipal != null &&
          loanPrincipal! > 0 &&
          loanAnnualInterestRate != null &&
          loanAnnualInterestRate! >= 0 &&
          loanTermMonths != null &&
          loanTermMonths! > 0 &&
          loanStartDate != null &&
          loanPaymentDay != null &&
          loanPaymentDay! >= 1 &&
          loanPaymentDay! <= 31 &&
          loanRepaymentMethod != null);
}
