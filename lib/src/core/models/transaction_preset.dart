import 'transaction.dart';

class TransactionTemplate {
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
    this.toCurrency,
    this.categoryId,
    this.description,
    this.merchant,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final TransactionType type;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final double amount;
  final String currency;
  final double? toAmount;
  final String? toCurrency;
  final TransactionStatus status;
  final String? description;
  final String? merchant;
  final int sortOrder;

  factory TransactionTemplate.fromTransaction({
    required String id,
    required String name,
    required FinanceTransaction transaction,
  }) {
    return TransactionTemplate(
      id: id,
      name: name,
      type: transaction.type,
      accountId: transaction.accountId,
      toAccountId: transaction.toAccountId,
      categoryId: transaction.categoryId,
      amount: transaction.amount,
      currency: transaction.currency,
      toAmount: transaction.toAmount,
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
        'to_currency': toCurrency,
        'status': status.name,
        'description': description,
        'merchant': merchant,
        'sort_order': sortOrder,
      };

  factory TransactionTemplate.fromJson(Map<String, dynamic> json) {
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

class RecurringTransactionRule {
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
    this.toCurrency,
    this.categoryId,
    this.description,
    this.merchant,
    this.endDate,
    this.generatedMonthKeys = const [],
    this.isActive = true,
  });

  final String id;
  final String name;
  final TransactionType type;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final double amount;
  final String currency;
  final double? toAmount;
  final String? toCurrency;
  final DateTime startDate;
  final int intervalMonths;
  final TransactionStatus status;
  final String? description;
  final String? merchant;
  final DateTime? endDate;
  final List<String> generatedMonthKeys;
  final bool isActive;

  factory RecurringTransactionRule.fromTransaction({
    required String id,
    required String name,
    required FinanceTransaction transaction,
    int intervalMonths = 1,
  }) {
    return RecurringTransactionRule(
      id: id,
      name: name,
      type: transaction.type,
      accountId: transaction.accountId,
      toAccountId: transaction.toAccountId,
      categoryId: transaction.categoryId,
      amount: transaction.amount,
      currency: transaction.currency,
      toAmount: transaction.toAmount,
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
      toCurrency: json['to_currency'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      intervalMonths: (json['interval_months'] as num?)?.toInt() ?? 1,
      status: json['status'] == null
          ? TransactionStatus.actual
          : TransactionStatus.values.byName(json['status'] as String),
      description: json['description'] as String?,
      merchant: json['merchant'] as String?,
      endDate: json['end_date'] == null
          ? null
          : DateTime.tryParse(json['end_date'] as String),
      generatedMonthKeys:
          (json['generated_month_keys'] as List<dynamic>? ?? const [])
              .map((item) => '$item')
              .toList(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
