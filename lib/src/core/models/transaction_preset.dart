import '../utils/anchored_month.dart';
import 'transaction.dart';

void _validatePresetLoanFields(Map<String, dynamic> json) {
  if (json['legacy_loan_id'] != null ||
      json['legacy_loan_part_number'] != null) {
    throw const FormatException('旧贷款分录配对仅适用于原始交易。');
  }
}

/// A present choice may explicitly select the uncategorized option.
typedef PresetCategoryChoice = ({String? categoryId});

class TransactionTemplate with LoanInstallmentFields {
  const TransactionTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.accountId,
    required this.amount,
    required this.currency,
    this.status = TransactionStatus.actual,
    this.toAccountId,
    this.toAmount,
    this.loanInstallmentNumber,
    this.loanPaymentAmount,
    this.toCurrency,
    this.categoryId,
    this.description,
    this.merchant,
    this.sortOrder = 0,
  });

  @override
  final String id;
  final String name;
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
  @override
  final String? toCurrency;
  final TransactionStatus status;
  @override
  final String? description;
  final String? merchant;
  final int sortOrder;

  FinanceTransaction toTransaction(
          {required String id, required DateTime date}) =>
      FinanceTransaction(
          id: id,
          type: type,
          accountId: accountId,
          toAccountId: toAccountId,
          categoryId: categoryId,
          amount: amount,
          currency: currency,
          toAmount: toAmount,
          toCurrency: toCurrency,
          loanInstallmentNumber: loanInstallmentNumber,
          loanPaymentAmount: loanPaymentAmount,
          status: status,
          description: description,
          merchant: merchant,
          transactionDate: date);

  factory TransactionTemplate.fromTransaction({
    required String id,
    required String name,
    required FinanceTransaction transaction,
    PresetCategoryChoice? categoryChoice,
  }) {
    return TransactionTemplate(
      id: id,
      name: name,
      type: transaction.type,
      accountId: transaction.accountId,
      toAccountId: transaction.toAccountId,
      categoryId: categoryChoice == null
          ? transaction.categoryId
          : categoryChoice.categoryId,
      amount: transaction.amount,
      currency: transaction.currency,
      toAmount: transaction.toAmount,
      loanInstallmentNumber: transaction.loanInstallmentNumber,
      loanPaymentAmount: transaction.loanPaymentAmount,
      toCurrency: transaction.toCurrency,
      status: transaction.status,
      description: transaction.description,
      merchant: transaction.merchant,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category_id': categoryId,
        'amount': amount,
        'currency': currency,
        'to_amount': toAmount,
        ...loanFields,
        'to_currency': toCurrency,
        'status': status.name,
        'description': description,
        'merchant': merchant,
        'sort_order': sortOrder,
      };

  factory TransactionTemplate.fromJson(Map<String, dynamic> json) {
    _validatePresetLoanFields(json);
    return TransactionTemplate(
      id: json['id'] as String,
      name: json['name'] as String? ?? '未命名模板',
      type: TransactionType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => TransactionType.expense,
      ),
      accountId: json['account_id'] as String,
      toAccountId: json['to_account_id'] as String?,
      categoryId: json['category_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'MYR',
      toAmount: (json['to_amount'] as num?)?.toDouble(),
      loanInstallmentNumber:
          parseLoanInstallmentNumber(json['loan_installment_number']),
      loanPaymentAmount: (json['loan_payment_amount'] as num?)?.toDouble(),
      toCurrency: json['to_currency'] as String?,
      status: json['status'] == null
          ? TransactionStatus.actual
          : TransactionStatus.values.byName(json['status'] as String),
      description: json['description'] as String?,
      merchant: json['merchant'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecurringTransactionRule with LoanInstallmentFields {
  const RecurringTransactionRule({
    required this.id,
    required this.name,
    required this.type,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.startDate,
    this.intervalMonths = 1,
    this.status = TransactionStatus.actual,
    this.toAccountId,
    this.toAmount,
    this.loanInstallmentNumber,
    this.loanPaymentAmount,
    this.toCurrency,
    this.categoryId,
    this.description,
    this.merchant,
    this.endDate,
    this.generatedMonthKeys = const [],
    this.isActive = true,
  });

  @override
  final String id;
  final String name;
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
  @override
  final String? toCurrency;
  final DateTime startDate;
  final int intervalMonths;
  final TransactionStatus status;
  @override
  final String? description;
  final String? merchant;
  final DateTime? endDate;
  final List<String> generatedMonthKeys;
  final bool isActive;

  factory RecurringTransactionRule.fromTransaction({
    required String id,
    required String name,
    required FinanceTransaction transaction,
    PresetCategoryChoice? categoryChoice,
    int intervalMonths = 1,
  }) {
    return RecurringTransactionRule(
      id: id,
      name: name,
      type: transaction.type,
      accountId: transaction.accountId,
      toAccountId: transaction.toAccountId,
      categoryId: categoryChoice == null
          ? transaction.categoryId
          : categoryChoice.categoryId,
      amount: transaction.amount,
      currency: transaction.currency,
      toAmount: transaction.toAmount,
      loanInstallmentNumber: transaction.loanInstallmentNumber,
      loanPaymentAmount: transaction.loanPaymentAmount,
      toCurrency: transaction.toCurrency,
      startDate: transaction.transactionDate,
      intervalMonths: intervalMonths,
      status: transaction.status,
      description: transaction.description,
      merchant: transaction.merchant,
    );
  }

  FinanceTransaction toTransaction({
    required String id,
    required DateTime date,
    required TransactionStatus status,
  }) {
    return FinanceTransaction(
      id: id,
      type: type,
      accountId: accountId,
      toAccountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      currency: currency,
      toAmount: toAmount,
      loanInstallmentNumber: loanInstallmentNumber,
      loanPaymentAmount: loanPaymentAmount,
      toCurrency: toCurrency,
      recordDate: date,
      transactionDate: date,
      status: status,
      recurringRuleId: this.id,
      description: description,
      merchant: merchant,
    );
  }

  RecurringTransactionRule copyWith({
    List<String>? generatedMonthKeys,
    bool? isActive,
  }) {
    return RecurringTransactionRule(
      id: id,
      name: name,
      type: type,
      accountId: accountId,
      toAccountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      currency: currency,
      toAmount: toAmount,
      loanInstallmentNumber: loanInstallmentNumber,
      loanPaymentAmount: loanPaymentAmount,
      toCurrency: toCurrency,
      startDate: startDate,
      intervalMonths: intervalMonths,
      status: status,
      description: description,
      merchant: merchant,
      endDate: endDate,
      generatedMonthKeys: generatedMonthKeys ?? this.generatedMonthKeys,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category_id': categoryId,
        'amount': amount,
        'currency': currency,
        'to_amount': toAmount,
        ...loanFields,
        'to_currency': toCurrency,
        'start_date': startDate.toIso8601String(),
        'interval_months': intervalMonths,
        'status': status.name,
        'description': description,
        'merchant': merchant,
        'end_date': endDate?.toIso8601String(),
        'generated_month_keys': generatedMonthKeys,
        'is_active': isActive,
      };

  factory RecurringTransactionRule.fromJson(Map<String, dynamic> json) {
    _validatePresetLoanFields(json);
    return RecurringTransactionRule(
      id: json['id'] as String,
      name: json['name'] as String? ?? '周期交易',
      type: TransactionType.values.byName(json['type'] as String),
      accountId: json['account_id'] as String,
      toAccountId: json['to_account_id'] as String?,
      categoryId: json['category_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'MYR',
      toAmount: (json['to_amount'] as num?)?.toDouble(),
      loanInstallmentNumber:
          parseLoanInstallmentNumber(json['loan_installment_number']),
      loanPaymentAmount: (json['loan_payment_amount'] as num?)?.toDouble(),
      toCurrency: json['to_currency'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      intervalMonths: () {
        final raw = json['interval_months'] ?? 1;
        if (raw is! num ||
            !raw.isFinite ||
            raw < 1 ||
            raw > 9007199254740991 ||
            raw != raw.truncate()) {
          throw FormatException('周期规则间隔月数必须是正整数：$raw');
        }
        return raw.toInt();
      }(),
      status: json['status'] == null
          ? TransactionStatus.actual
          : TransactionStatus.values.byName(json['status'] as String),
      description: json['description'] as String?,
      merchant: json['merchant'] as String?,
      endDate: json['end_date'] == null
          ? null
          : DateTime.tryParse(json['end_date'] as String),
      generatedMonthKeys: () {
        final raw = json['generated_month_keys'];
        if (raw == null) return <String>[];
        if (raw is! List || !raw.every(isRecurringMonthKey)) {
          throw const FormatException('周期规则生成月份必须是 YYYY-MM。');
        }
        return List<String>.from(raw);
      }(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
