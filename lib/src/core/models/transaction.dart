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

const creditCardPostingMetaPrefix = 'credit_card_posting_dates/';
final _cardPostingDayPattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

/// The wire value is a calendar day, never a timestamp or a UTC conversion.
DateTime? parseCardPostingDate(Object? value) {
  if (value == null) return null;
  if (value is String &&
      value.length == 10 &&
      _cardPostingDayPattern.hasMatch(value)) {
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8));
    final date = DateTime(year, month, day);
    if (date.year == year && date.month == month && date.day == day) {
      return date;
    }
  }
  throw const FormatException('信用卡账单入账日须为有效的 YYYY-MM-DD 日期。');
}

String formatCardPostingDate(DateTime date) {
  if (date.year < 0 || date.year > 9999) {
    throw const FormatException('信用卡账单入账日须为四位数年份。');
  }
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

void validateCardPostingDate(FinanceTransaction tx,
    {required bool sourceIsCreditCard}) {
  final posting = tx.cardPostingDate;
  if (posting == null) return;
  if (!sourceIsCreditCard) {
    throw const FormatException('仅信用卡来源交易可设置账单入账日。');
  }
  final economic = tx.transactionDate.toLocal();
  if (posting.isBefore(DateTime(economic.year, economic.month, economic.day))) {
    throw const FormatException('信用卡账单入账日不能早于交易发生日。');
  }
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
  FinanceTransaction({
    required this.id,
    required this.type,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.transactionDate,
    DateTime? cardPostingDate,
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
  })  : recordDate = recordDate ?? transactionDate,
        cardPostingDate = cardPostingDate == null
            ? null
            : DateTime(cardPostingDate.year, cardPostingDate.month,
                cardPostingDate.day);

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
  final DateTime? cardPostingDate;
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
        cardPostingDate: cardPostingDate,
        recordDate: recordDate,
        status: status,
        merchant: merchant,
        description: description,
        recurringRuleId: recurringRuleId,
      );

  String get transferInCurrency => toCurrency ?? currency;
}
