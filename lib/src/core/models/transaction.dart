enum TransactionType {
  income,
  expense,
  transfer,
  adjustment,
}

enum TransactionStatus {
  planned,
  actual,
  settled,
}

/// Settlement uses integer cents on both native Dart and JavaScript.
bool isLoanMoney(double amount) {
  final cents = amount * 100;
  return cents.isFinite &&
      cents.abs() <= 9007199254740991 &&
      cents.round() / 100 == amount;
}

/// Validates the split in the loan's currency. The source and target may
/// use different units, but a reversal must reverse both sides.
bool validLoanInstallmentAmounts(double payment, double? principal,
    {double? loanPaymentAmount, bool sameCurrency = true}) {
  final total = loanPaymentAmount ?? payment;
  if ((!sameCurrency && loanPaymentAmount == null) ||
      (sameCurrency && total != payment) ||
      !isLoanMoney(payment) ||
      payment == 0 ||
      !isLoanMoney(total) ||
      total == 0 ||
      payment.isNegative != total.isNegative ||
      principal == null ||
      !isLoanMoney(principal)) {
    return false;
  }
  return (principal == 0 || principal.isNegative == total.isNegative) &&
      principal.abs() <= total.abs();
}

int? parseLoanInstallmentNumber(Object? value) {
  if (value == null) return null;
  if (value is num &&
      value.isFinite &&
      value >= 1 &&
      value <= 9007199254740991 &&
      value == value.truncate()) {
    return value.toInt();
  }
  throw const FormatException('贷款期号必须是正整数。');
}

mixin LoanInstallmentFields {
  int? get loanInstallmentNumber;
  double? get loanPaymentAmount;
  String get id;
  TransactionType get type;
  String get accountId;
  String? get toAccountId;
  String get currency;
  String? get toCurrency;
  double get amount;
  double? get toAmount;
  String? get description;

  double get installmentPaymentInLoanCurrency => loanPaymentAmount ?? amount;

  Map<String, Object> get loanFields => {
        if (loanInstallmentNumber != null)
          'loan_installment_number': loanInstallmentNumber!,
        if (loanPaymentAmount != null)
          'loan_payment_amount': loanPaymentAmount!,
      };
}

class FinanceTransaction with LoanInstallmentFields {
  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.transactionDate,
    DateTime? recordDate,
    this.status = TransactionStatus.actual,
    this.recurringRuleId,
    this.categoryId,
    this.toAccountId,
    this.toAmount,
    this.loanInstallmentNumber,
    this.loanPaymentAmount,
    this.legacyLoanPartNumber,
    this.legacyLoanId,
    this.toCurrency,
    this.description,
    this.merchant,
  }) : recordDate = recordDate ?? transactionDate;

  @override
  final String id;
  @override
  final TransactionType type;
  @override
  final String accountId;
  @override
  final String? toAccountId;
  final String? categoryId;
  @override
  final double amount;
  @override
  final String currency;
  @override
  final double? toAmount;
  @override
  final int? loanInstallmentNumber;
  @override
  final double? loanPaymentAmount;
  final int? legacyLoanPartNumber;
  final String? legacyLoanId;
  @override
  final String? toCurrency;
  final DateTime recordDate;
  final DateTime transactionDate;
  final TransactionStatus status;
  final String? recurringRuleId;
  @override
  final String? description;
  final String? merchant;

  @override
  Map<String, Object> get loanFields => {
        ...super.loanFields,
        if (legacyLoanPartNumber != null)
          'legacy_loan_part_number': legacyLoanPartNumber!,
        if (legacyLoanId != null) 'legacy_loan_id': legacyLoanId!,
      };

  bool get affectsBalance => status != TransactionStatus.planned;

  double get transferInAmount => toAmount ?? amount;

  /// Live same-currency ordinary transfers use a single amount. Imports are
  /// decoded separately so an ambiguous historical zero is preserved.
  FinanceTransaction canonicalOrdinaryTransfer() => FinanceTransaction(
        id: id,
        type: type,
        accountId: accountId,
        toAccountId: toAccountId,
        categoryId: categoryId,
        amount: amount,
        currency: currency,
        toCurrency: toCurrency,
        transactionDate: transactionDate,
        recordDate: recordDate,
        status: status,
        merchant: merchant,
        description: description,
        recurringRuleId: recurringRuleId,
      );

  String get transferInCurrency => toCurrency ?? currency;
}
