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

  bool get hasCompleteCreditCardProfile =>
      accountType != AccountType.creditCard ||
      (creditLimit != null && statementDay != null && paymentDueDay != null);
}
