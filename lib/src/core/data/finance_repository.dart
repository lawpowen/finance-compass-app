import 'dart:convert';
import 'dart:typed_data';

import '../database/app_database.dart'
    hide Account, AssetSnapshot, Budget, Category;
import '../models/account.dart';
import '../models/asset_snapshot.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/credit_card_billing.dart';
import '../models/forecast_summary.dart';
import '../models/loan_amortization.dart';
import '../models/monthly_summary.dart';
import '../models/transaction.dart';
import '../models/transaction_preset.dart' as preset;
import '../platform/local_file_io.dart' as local_files;
import '../utils/currency_formatter.dart';
import '../utils/id_generator.dart';
import '../utils/month_key.dart';
import 'sample_data.dart';

class FinanceRepository {
  static const uncategorizedCashOutflowKey = '__cash_outflow_uncategorized__';
  static const _exchangeRatesMetaKey = 'exchange_rates_to_base_json';
  static const _currencyPriorityMetaKey = 'currency_priority_json';

  FinanceRepository._({
    required this.database,
    required List<Account> accounts,
    required List<Category> categories,
    required List<Budget> budgets,
    required List<FinanceTransaction> transactions,
    required List<AssetSnapshot> snapshots,
    required List<TransactionTemplate> transactionTemplates,
    required List<RecurringTransactionRule> recurringTransactionRules,
    required Map<String, String> metaValues,
  })  : _accounts = accounts,
        _categories = categories,
        _budgets = budgets,
        _transactions = transactions,
        _snapshots = snapshots,
        _transactionTemplates = transactionTemplates,
        _recurringTransactionRules = recurringTransactionRules,
        _metaValues = metaValues;

  final AppDatabase database;

  final List<Account> _accounts;
  final List<Category> _categories;
  final List<Budget> _budgets;
  final List<FinanceTransaction> _transactions;
  final List<AssetSnapshot> _snapshots;
  final List<TransactionTemplate> _transactionTemplates;
  final List<RecurringTransactionRule> _recurringTransactionRules;
  final Map<String, String> _metaValues;

  static FinanceRepository preview() {
    final repository = FinanceRepository._(
      database: AppDatabase(),
      accounts: SampleData.accounts(),
      categories: SampleData.categories(),
      budgets: SampleData.budgets(),
      transactions: SampleData.transactions(),
      snapshots: SampleData.snapshots(),
      transactionTemplates: const [],
      recurringTransactionRules: const [],
      metaValues: const {},
    );
    setActiveBaseCurrency(repository.baseCurrency);
    return repository;
  }

  static Future<FinanceRepository> load(AppDatabase database) async {
    final accounts = await database.fetchAccounts();
    final categories = await database.fetchCategories();
    final budgets = await database.fetchBudgets();
    final transactions = await database.fetchTransactions();
    final snapshots = await database.fetchAssetSnapshots();
    final storedTemplates = (await database.fetchTransactionTemplates())
        .map((item) => TransactionTemplate.fromJson(item.toJson()))
        .toList();
    final storedRules = (await database.fetchRecurringTransactionRules())
        .map((item) => RecurringTransactionRule.fromJson(item.toJson()))
        .toList();
    final metaValues = await database.fetchAllMetaValues();
    final transactionTemplates = storedTemplates.isNotEmpty
        ? storedTemplates
        : _legacyTemplatesFromMeta(metaValues);
    final recurringTransactionRules =
        storedRules.isNotEmpty ? storedRules : _legacyRulesFromMeta(metaValues);

    final repository = FinanceRepository._(
      database: database,
      accounts: accounts,
      categories: categories,
      budgets: budgets,
      transactions: transactions,
      snapshots: snapshots,
      transactionTemplates: transactionTemplates,
      recurringTransactionRules: recurringTransactionRules,
      metaValues: metaValues,
    );
    setActiveBaseCurrency(repository.baseCurrency);
    return repository;
  }

  Future<FinanceRepository> refresh() => FinanceRepository.load(database);

  static List<TransactionTemplate> _legacyTemplatesFromMeta(
    Map<String, String> metaValues,
  ) {
    try {
      final decoded =
          jsonDecode(metaValues['transaction_templates_json'] ?? '[]');
      return (decoded as List<dynamic>)
          .whereType<Map>()
          .map((item) => TransactionTemplate.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<RecurringTransactionRule> _legacyRulesFromMeta(
    Map<String, String> metaValues,
  ) {
    try {
      final decoded =
          jsonDecode(metaValues['recurring_transaction_rules_json'] ?? '[]');
      return (decoded as List<dynamic>)
          .whereType<Map>()
          .map((item) => RecurringTransactionRule.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Category> get categories => List.unmodifiable(_categories);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<FinanceTransaction> get transactions => List.unmodifiable(_transactions);
  List<AssetSnapshot> get snapshots => List.unmodifiable(_snapshots);
  Map<String, String> get metaValues => Map.unmodifiable(_metaValues);

  List<String> get currencyPriority {
    final raw = _metaValues[_currencyPriorityMetaKey];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final ordered = decoded
              .map((item) => normalizeCurrency('$item'))
              .where(supportedCurrencies.contains)
              .toSet()
              .toList();
          return [
            ...ordered,
            ...supportedCurrencies.where((item) => !ordered.contains(item)),
          ];
        }
      } catch (_) {
        // Keep the default order if metadata was edited manually.
      }
    }
    return List.unmodifiable(supportedCurrencies);
  }

  String get baseCurrency => currencyPriority.first;

  Map<String, double> get exchangeRatesToBase {
    final raw = _metaValues[_exchangeRatesMetaKey];
    if (raw == null || raw.trim().isEmpty) {
      return _defaultRatesForBase(baseCurrency);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final rates = {
          for (final entry in decoded.entries)
            normalizeCurrency(entry.key): entry.value is num
                ? (entry.value as num).toDouble()
                : double.tryParse('${entry.value}') ?? 1,
        };
        return normalizedExchangeRatesToBase(
          rates,
          baseCurrency: baseCurrency,
        );
      }
    } catch (_) {
      // Fall back to defaults if older metadata was edited manually.
    }
    return _defaultRatesForBase(baseCurrency);
  }

  String? get secondaryCurrency {
    final priority = currencyPriority;
    return priority.length < 2 ? null : priority[1];
  }

  double convertAmount({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) {
    return convertCurrencyAmount(
      amount: amount,
      fromCurrency: fromCurrency,
      toCurrency: toCurrency,
      ratesToBase: exchangeRatesToBase,
      baseCurrency: baseCurrency,
    );
  }

  double convertToBase(double amount, String currency) {
    return convertAmount(
      amount: amount,
      fromCurrency: currency,
      toCurrency: baseCurrency,
    );
  }

  double transactionAmountInBase(FinanceTransaction transaction) {
    return convertToBase(transaction.amount, transaction.currency);
  }

  double transferIncomingAmountInBase(FinanceTransaction transaction) {
    return convertToBase(
      transaction.transferInAmount,
      transaction.transferInCurrency,
    );
  }

  double convertFromBase(double amount, String currency) {
    return convertAmount(
      amount: amount,
      fromCurrency: baseCurrency,
      toCurrency: currency,
    );
  }

  String conversionHintForAmount(double amount, String currency) {
    final normalized = normalizeCurrency(currency);
    final targetCurrency =
        normalized == baseCurrency ? secondaryCurrency : baseCurrency;
    if (targetCurrency == null || targetCurrency == normalized) {
      return '';
    }
    return formatConversionHint(
      amount: amount,
      fromCurrency: normalized,
      toCurrency: targetCurrency,
      ratesToBase: exchangeRatesToBase,
      baseCurrency: baseCurrency,
    );
  }

  Future<FinanceRepository> updateExchangeRates(
    Map<String, double> ratesToBase,
    List<String> currencyPriority,
  ) async {
    final ordered = _normalizeCurrencyPriority(currencyPriority);
    final normalized = normalizedExchangeRatesToBase(
      ratesToBase,
      baseCurrency: ordered.first,
    );
    await database.setMetaValue(_exchangeRatesMetaKey, jsonEncode(normalized));
    await database.setMetaValue(_currencyPriorityMetaKey, jsonEncode(ordered));
    return refresh();
  }

  List<TransactionTemplate> get transactionTemplates {
    return List.unmodifiable(_transactionTemplates);
  }

  List<RecurringTransactionRule> get recurringTransactionRules {
    return List.unmodifiable(_recurringTransactionRules);
  }

  List<AssetGoal> get assetGoals {
    final raw = _metaValues['asset_goals_json'];
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(AssetGoal.fromJson)
            .toList()
          ..sort((a, b) => a.targetAmount.compareTo(b.targetAmount));
      }
      if (decoded is List<dynamic>) {
        return decoded
            .map((item) =>
                AssetGoal.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList()
          ..sort((a, b) => a.targetAmount.compareTo(b.targetAmount));
      }
    }

    final legacyAmountRaw = _metaValues['asset_goal_amount'];
    final legacyReachedAtRaw = _metaValues['asset_goal_reached_at'];
    final legacyAmount =
        legacyAmountRaw == null ? null : double.tryParse(legacyAmountRaw);
    if (legacyAmount == null || legacyAmount <= 0) {
      return const [];
    }
    return [
      AssetGoal(
        id: 'goal_legacy',
        name: '资产目标',
        targetAmount: legacyAmount,
        reachedAt: legacyReachedAtRaw == null
            ? null
            : DateTime.tryParse(legacyReachedAtRaw),
      ),
    ];
  }

  double totalAssetsByGroup(ReportGroup group) {
    return displayTotalAssetsByGroup(group);
  }

  double displayTotalAssetsByGroup(ReportGroup group, {DateTime? cutoffDate}) {
    final useCommittedCreditBalance = cutoffDate == null;
    final targetDate = cutoffDate ?? currentMonthCutoffDate();
    return _accounts.where((account) => account.reportGroup == group).fold(
          0.0,
          (sum, account) =>
              sum +
              (useCommittedCreditBalance &&
                      account.accountType == AccountType.creditCard
                  ? convertToBase(account.currentBalance, account.currency)
                  : accountBalanceAtBase(account.id, targetDate)),
        );
  }

  double totalAssets({bool includeCredit = true}) {
    return displayTotalAssets(includeCredit: includeCredit);
  }

  double displayTotalAssets({bool includeCredit = true, DateTime? cutoffDate}) {
    final useCommittedCreditBalance = cutoffDate == null;
    final targetDate = cutoffDate ?? currentMonthCutoffDate();
    return _accounts
        .where((account) =>
            includeCredit || account.reportGroup != ReportGroup.credit)
        .fold(
            0.0,
            (sum, account) =>
                sum +
                (useCommittedCreditBalance &&
                        account.accountType == AccountType.creditCard
                    ? convertToBase(account.currentBalance, account.currency)
                    : accountBalanceAtBase(account.id, targetDate)));
  }

  double totalTargetAssets() {
    return displayTotalAssets(includeCredit: false);
  }

  List<AssetGoalHistoryPoint> totalAssetHistory({
    DateTime? cutoffDate,
    bool includeCredit = true,
  }) {
    final targetCutoff = cutoffDate ?? currentMonthCutoffDate();
    final monthKeys = <String>{
      monthKeyFromDate(targetCutoff),
      ..._transactions
          .where((item) => !item.transactionDate.isAfter(targetCutoff))
          .map((item) => monthKeyFromDate(item.transactionDate)),
      ..._snapshots
          .where((item) => !item.snapshotDate.isAfter(targetCutoff))
          .map((item) => monthKeyFromDate(item.snapshotDate)),
    }.toList()
      ..sort(_compareMonthKeys);

    if (monthKeys.isEmpty) {
      final now = DateTime.now();
      return [
        AssetGoalHistoryPoint(
          date: now,
          label: '${now.year}-${now.month.toString().padLeft(2, '0')}',
          totalAssets:
              totalAssetsAt(targetCutoff, includeCredit: includeCredit),
        ),
      ];
    }

    return monthKeys.map((monthKey) {
      final parts = monthKey.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final isCutoffMonth = monthKey == monthKeyFromDate(targetCutoff);
      final date = isCutoffMonth ? targetCutoff : DateTime(year, month + 1, 0);
      return AssetGoalHistoryPoint(
        date: date,
        label: monthKey,
        totalAssets: totalAssetsAt(date, includeCredit: includeCredit),
      );
    }).toList();
  }

  List<AssetGoalProgressSummary> assetGoalSummaries({
    DateTime? cutoffDate,
  }) {
    final targetCutoff = cutoffDate ?? currentMonthCutoffDate();
    final history = totalAssetHistory(
      cutoffDate: targetCutoff,
      includeCredit: false,
    );
    final currentAssets = totalAssetsAt(
      targetCutoff,
      includeCredit: false,
    );
    final summaries = assetGoals.map((goal) {
      AssetGoalHistoryPoint? reachedPoint;
      for (final point in history) {
        if (point.totalAssets >= goal.targetAmount) {
          reachedPoint = point;
          break;
        }
      }

      return AssetGoalProgressSummary(
        goal: goal,
        currentAssets: currentAssets,
        reachedAt: reachedPoint?.date ?? goal.reachedAt,
        history: history,
      );
    }).toList();

    summaries.sort((left, right) {
      if (left.isReached != right.isReached) {
        return left.isReached ? 1 : -1;
      }
      if (left.isReached && right.isReached) {
        final leftDate = left.reachedAt ?? DateTime(9999);
        final rightDate = right.reachedAt ?? DateTime(9999);
        return leftDate.compareTo(rightDate);
      }
      return left.goal.targetAmount.compareTo(right.goal.targetAmount);
    });
    return summaries;
  }

  double expenseTotalForCategory(String categoryId, String monthKey) {
    return actualExpenseTotalForCategory(categoryId, monthKey);
  }

  double actualExpenseTotalForCategory(String categoryId, String monthKey) {
    return _transactions
        .where((transaction) =>
            transaction.type == TransactionType.expense &&
            transaction.status != TransactionStatus.planned &&
            transaction.categoryId == categoryId &&
            _monthKey(transaction.transactionDate) == monthKey)
        .fold(0,
            (sum, transaction) => sum + transactionAmountInBase(transaction));
  }

  double plannedExpenseTotalForCategory(String categoryId, String monthKey) {
    return _transactions
        .where((transaction) =>
            transaction.type == TransactionType.expense &&
            transaction.status == TransactionStatus.planned &&
            transaction.categoryId == categoryId &&
            _monthKey(transaction.transactionDate) == monthKey)
        .fold(0,
            (sum, transaction) => sum + transactionAmountInBase(transaction));
  }

  Map<String, double> expenseBreakdownForAccount(
      String accountId, String monthKey) {
    final map = <String, double>{};

    for (final transaction in _transactions.where((item) =>
        item.accountId == accountId &&
        item.type == TransactionType.expense &&
        item.status != TransactionStatus.planned &&
        _monthKey(item.transactionDate) == monthKey)) {
      final key = transaction.categoryId ?? 'uncategorized';
      map[key] = (map[key] ?? 0) + transaction.amount;
    }

    return map;
  }

  String categoryName(String categoryId) {
    return _categories.firstWhere((item) => item.id == categoryId).name;
  }

  String accountName(String accountId) {
    return _accounts.firstWhere((item) => item.id == accountId).name;
  }

  List<Category> categoriesByType(CategoryType type) {
    return _categories.where((item) => item.type == type).toList();
  }

  List<Category> sortedCategories() {
    final items = [..._categories]..sort((a, b) {
        final byType = a.type.name.compareTo(b.type.name);
        if (byType != 0) {
          return byType;
        }
        return a.name.compareTo(b.name);
      });
    return items;
  }

  List<Account> accountsByGroup(ReportGroup group) {
    return _accounts.where((item) => item.reportGroup == group).toList();
  }

  double accountBalanceAt(String accountId, DateTime date) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    return _accountBalanceAt(account, date);
  }

  double accountBalanceAtBase(String accountId, DateTime date) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    return convertToBase(_accountBalanceAt(account, date), account.currency);
  }

  /// Credit already committed by actual/settled records, regardless of date.
  /// Planned records never affect [Account.currentBalance] and are excluded.
  double creditCardCommittedOutstandingBalance(String accountId) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    if (account.accountType != AccountType.creditCard) {
      throw ArgumentError.value(accountId, 'accountId', 'Not a credit card');
    }
    return (-account.currentBalance).clamp(0, double.infinity).toDouble();
  }

  /// Remaining balance at a statement close, including carried balance,
  /// actual charges, refunds and repayments posted on or before that day.
  double creditCardStatementBalance(
    String accountId,
    CreditCardBillingPeriod period,
  ) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    if (account.accountType != AccountType.creditCard) {
      throw ArgumentError.value(accountId, 'accountId', 'Not a credit card');
    }
    final statementCutoff = DateTime(
      period.statementDate.year,
      period.statementDate.month,
      period.statementDate.day,
      23,
      59,
      59,
      999,
    );
    return (-accountBalanceAt(accountId, statementCutoff))
        .clamp(0, double.infinity)
        .toDouble();
  }

  /// Returns an authoritative statement amount imported during reconciliation.
  ///
  /// The key is the statement close date (`yyyy-MM-dd`). Missing or malformed
  /// metadata deliberately falls back to the transaction-derived calculation.
  double? creditCardStatementAmountOverride(
    String accountId,
    DateTime statementDate,
  ) {
    final raw = _metaValues[_creditCardStatementAmountsKey(accountId)];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final amount = decoded[_statementDateKey(statementDate)];
      if (amount is num && amount.isFinite && amount >= 0) {
        return amount.toDouble();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  double transactionDeltaForAccount(
    String accountId,
    FinanceTransaction transaction,
  ) {
    return _transactionDeltaForAccount(accountId, transaction);
  }

  String? reconciledMonthForAccount(String accountId) {
    final monthKey = _metaValues[_accountReconciliationKey(accountId)];
    if (monthKey == null || monthKey.trim().isEmpty) {
      return null;
    }
    return monthKey;
  }

  bool isAccountReconciledForMonth(String accountId, String monthKey) {
    final reconciledMonth = reconciledMonthForAccount(accountId);
    if (reconciledMonth == null) {
      return false;
    }
    return _compareMonthKeys(reconciledMonth, monthKey) >= 0;
  }

  Future<FinanceRepository> setAccountReconciledMonth(
    String accountId,
    String monthKey,
  ) async {
    await database.setMetaValue(
      _accountReconciliationKey(accountId),
      monthKey,
    );
    return refresh();
  }

  Future<FinanceRepository> clearAccountReconciledMonth(
      String accountId) async {
    await database.deleteMetaValue(_accountReconciliationKey(accountId));
    return refresh();
  }

  AccountBalanceTrace accountBalanceTrace(
    String accountId,
    DateTime cutoffDate,
  ) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    final accountSnapshots = snapshotsForAccount(account.id);
    AssetSnapshot? latestSnapshotBeforeDate;
    for (final snapshot in accountSnapshots) {
      if (!snapshot.snapshotDate.isAfter(cutoffDate)) {
        latestSnapshotBeforeDate = snapshot;
      }
    }

    if (latestSnapshotBeforeDate == null && accountSnapshots.isNotEmpty) {
      return _openingBalanceTrace(account, cutoffDate);
    }

    var runningBalance =
        latestSnapshotBeforeDate?.marketValue ?? account.currentBalance;
    final traceEntries = <AccountBalanceTraceEntry>[];
    final adjustments = latestSnapshotBeforeDate != null
        ? _snapshotAnchoredAdjustments(
            account.id,
            latestSnapshotBeforeDate,
            cutoffDate,
          )
        : (_transactions
                .where((transaction) =>
                    transaction.transactionDate.isAfter(cutoffDate) &&
                    _transactionDeltaForAccount(account.id, transaction) != 0)
                .toList()
              ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate)))
            .map((transaction) => (
                  transaction: transaction,
                  appliedDelta:
                      -_transactionDeltaForAccount(account.id, transaction),
                ))
            .toList();

    for (final (:transaction, :appliedDelta) in adjustments) {
      runningBalance += appliedDelta;
      traceEntries.add(
        AccountBalanceTraceEntry(
          transactionId: transaction.id,
          date: transaction.transactionDate,
          title: _traceTitleForTransaction(transaction),
          subtitle: _traceSubtitleForTransaction(account.id, transaction),
          delta: appliedDelta,
          runningBalance: runningBalance,
        ),
      );
    }

    final sourceLabel = latestSnapshotBeforeDate == null
        ? '当前账户余额'
        : '资产快照 ${_dateLabel(latestSnapshotBeforeDate.snapshotDate)}';
    return AccountBalanceTrace(
      account: account,
      cutoffDate: cutoffDate,
      sourceLabel: sourceLabel,
      sourceAmount:
          latestSnapshotBeforeDate?.marketValue ?? account.currentBalance,
      entries: traceEntries,
      endingBalance: runningBalance,
    );
  }

  /// Trace for a cutoff before the account's first snapshot: start from
  /// [Account.initialBalance] and apply every transaction up to the cutoff.
  AccountBalanceTrace _openingBalanceTrace(
    Account account,
    DateTime cutoffDate,
  ) {
    var runningBalance = account.initialBalance;
    final traceEntries = <AccountBalanceTraceEntry>[];
    final applyingTransactions = _transactions
        .where((transaction) =>
            !transaction.transactionDate.isAfter(cutoffDate) &&
            _transactionDeltaForAccount(account.id, transaction) != 0)
        .toList()
      ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));

    for (final transaction in applyingTransactions) {
      final appliedDelta = _transactionDeltaForAccount(account.id, transaction);
      runningBalance += appliedDelta;
      traceEntries.add(
        AccountBalanceTraceEntry(
          transactionId: transaction.id,
          date: transaction.transactionDate,
          title: _traceTitleForTransaction(transaction),
          subtitle: _traceSubtitleForTransaction(account.id, transaction),
          delta: appliedDelta,
          runningBalance: runningBalance,
        ),
      );
    }

    return AccountBalanceTrace(
      account: account,
      cutoffDate: cutoffDate,
      sourceLabel: '账户期初余额（首张资产快照之前）',
      sourceAmount: account.initialBalance,
      entries: traceEntries,
      endingBalance: runningBalance,
    );
  }

  List<Account> investmentAccounts() {
    return _accounts
        .where(
          (item) =>
              item.reportGroup == ReportGroup.investment ||
              item.reportGroup == ReportGroup.retirement,
        )
        .toList();
  }

  AssetSnapshot? latestSnapshotForAccount(String accountId) {
    final items = _snapshots
        .where((item) => item.accountId == accountId)
        .toList()
      ..sort((a, b) => b.snapshotDate.compareTo(a.snapshotDate));
    return items.isEmpty ? null : items.first;
  }

  AssetSnapshot? latestSnapshotForAccountUpTo(String accountId, DateTime date) {
    final items = _snapshots
        .where((item) =>
            item.accountId == accountId && !item.snapshotDate.isAfter(date))
        .toList()
      ..sort((a, b) => b.snapshotDate.compareTo(a.snapshotDate));
    return items.isEmpty ? null : items.first;
  }

  List<AssetSnapshot> snapshotsForAccount(String accountId) {
    final items = _snapshots
        .where((item) => item.accountId == accountId)
        .toList()
      ..sort((a, b) => a.snapshotDate.compareTo(b.snapshotDate));
    return items;
  }

  List<AssetSnapshot> snapshotsForAccountUpTo(String accountId, DateTime date) {
    final items = _snapshots
        .where((item) =>
            item.accountId == accountId && !item.snapshotDate.isAfter(date))
        .toList()
      ..sort((a, b) => a.snapshotDate.compareTo(b.snapshotDate));
    return items;
  }

  AssetSnapshot? firstSnapshotForAccount(String accountId) {
    final items = snapshotsForAccount(accountId);
    return items.isEmpty ? null : items.first;
  }

  double costBasisForAccount(
    String accountId, {
    DateTime? upToDate,
  }) {
    final targetDate = upToDate ?? currentMonthCutoffDate();
    final firstSnapshot = firstSnapshotForAccount(accountId);
    if (firstSnapshot == null) {
      return investmentFlowSummaryForAccount(
        accountId,
        upToDate: targetDate,
      ).contribution;
    }

    if (targetDate.isBefore(firstSnapshot.snapshotDate)) {
      // The first snapshot's baseline is not known yet at [targetDate].
      return investmentFlowSummaryForAccount(
        accountId,
        upToDate: targetDate,
      ).contribution;
    }

    final deltaFlow = investmentFlowSummaryForAccount(
      accountId,
      fromDateExclusive: firstSnapshot.snapshotDate,
      upToDate: targetDate,
    );
    return (firstSnapshot.costBasis + deltaFlow.contribution)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double snapshotCostBasis(AssetSnapshot snapshot) {
    return costBasisForAccount(
      snapshot.accountId,
      upToDate: snapshot.snapshotDate,
    );
  }

  double cashBalanceForAccount(
    String accountId, {
    DateTime? upToDate,
  }) {
    final targetDate = upToDate ?? currentMonthCutoffDate();
    final account = _accounts.firstWhere((item) => item.id == accountId);
    final latestSnapshot = latestSnapshotForAccountUpTo(accountId, targetDate);
    if (latestSnapshot == null) {
      return _accountBalanceAt(account, targetDate)
          .clamp(0, double.infinity)
          .toDouble();
    }

    var cashBalance = latestSnapshot.cashBalance;
    for (final transaction in _transactions) {
      if (!transaction.transactionDate.isAfter(targetDate) ||
          !transaction.transactionDate.isAfter(latestSnapshot.snapshotDate)) {
        continue;
      }
      cashBalance -= _cashDeltaForAccount(accountId, transaction);
    }
    return cashBalance.clamp(0, double.infinity).toDouble();
  }

  double remainingCostBasisForAccount(
    String accountId, {
    DateTime? upToDate,
  }) {
    final targetDate = upToDate ?? currentMonthCutoffDate();
    final cumulativeCost = costBasisForAccount(
      accountId,
      upToDate: targetDate,
    );
    final firstSnapshot = firstSnapshotForAccount(accountId);
    final flow = investmentFlowSummaryForAccount(
      accountId,
      fromDateExclusive: firstSnapshot != null &&
              !targetDate.isBefore(firstSnapshot.snapshotDate)
          ? firstSnapshot.snapshotDate
          : null,
      upToDate: targetDate,
    );
    return (cumulativeCost - flow.withdrawal)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double snapshotRemainingCostBasis(AssetSnapshot snapshot) {
    return remainingCostBasisForAccount(
      snapshot.accountId,
      upToDate: snapshot.snapshotDate,
    );
  }

  double snapshotUnrealizedPnl(AssetSnapshot snapshot) {
    return snapshot.marketValue - snapshotRemainingCostBasis(snapshot);
  }

  double snapshotPnlRatio(AssetSnapshot snapshot) {
    final costBasis = snapshotRemainingCostBasis(snapshot);
    if (costBasis == 0) {
      return 0;
    }
    return snapshotUnrealizedPnl(snapshot) / costBasis;
  }

  double totalAssetsAt(DateTime date, {bool includeCredit = true}) {
    return _accounts
        .where((account) =>
            includeCredit || account.reportGroup != ReportGroup.credit)
        .fold(
          0.0,
          (sum, account) =>
              sum +
              convertToBase(_accountBalanceAt(account, date), account.currency),
        );
  }

  InvestmentFlowSummary investmentFlowSummaryForAccount(
    String accountId, {
    DateTime? fromDateExclusive,
    DateTime? upToDate,
  }) {
    final targetDate = upToDate ?? currentMonthCutoffDate();
    double contribution = 0;
    double withdrawal = 0;

    for (final transaction in _transactions) {
      if (!transaction.affectsBalance) {
        continue;
      }
      if (fromDateExclusive != null &&
          !transaction.transactionDate.isAfter(fromDateExclusive)) {
        continue;
      }
      if (transaction.transactionDate.isAfter(targetDate)) {
        continue;
      }

      if (transaction.type == TransactionType.transfer) {
        if (transaction.toAccountId == accountId) {
          contribution += transaction.transferInAmount;
        }
        if (transaction.accountId == accountId) {
          withdrawal += transaction.amount;
        }
      }

      if (transaction.type == TransactionType.adjustment &&
          transaction.accountId == accountId) {
        if (transaction.amount >= 0) {
          contribution += transaction.amount;
        } else {
          withdrawal += transaction.amount.abs();
        }
      }
    }

    return InvestmentFlowSummary(
      contribution: contribution,
      withdrawal: withdrawal,
    );
  }

  List<FinanceTransaction> recentTransactions({int limit = 5}) {
    final items = [..._transactions]
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return items.take(limit).toList();
  }

  List<FinanceTransaction> upcomingExpenseTransactions({int limit = 8}) {
    final now = DateTime.now();
    final items = _transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              item.transactionDate
                  .isAfter(DateTime(now.year, now.month, now.day)),
        )
        .toList()
      ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    return items.take(limit).toList();
  }

  double totalFutureExpense({int monthsAhead = 3}) {
    final now = DateTime.now();
    final lastDate = DateTime(now.year, now.month + monthsAhead, 1);
    return _transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              item.transactionDate
                  .isAfter(DateTime(now.year, now.month, now.day - 1)) &&
              item.transactionDate.isBefore(lastDate),
        )
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  List<MonthlySummary> futureExpenseSummaries({int months = 3}) {
    final now = DateTime.now();
    return List.generate(months, (index) {
      final date = DateTime(now.year, now.month + index + 1);
      final monthKey = _monthKey(date);
      return MonthlySummary(
        monthKey: monthKey,
        income: totalIncomeForMonth(monthKey) + plannedIncomeForMonth(monthKey),
        expense:
            totalExpenseForMonth(monthKey) + plannedExpenseForMonth(monthKey),
      );
    });
  }

  List<CashFlowProjectionPoint> futureCashFlowProjection({
    int months = 6,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final todayCutoff = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );
    final startMonth = DateTime(now.year, now.month);
    var runningCash = displayTotalAssetsByGroup(
      ReportGroup.cash,
      cutoffDate: todayCutoff,
    );

    return List.generate(months, (index) {
      final monthDate = DateTime(startMonth.year, startMonth.month + index);
      final monthKey = _monthKey(monthDate);
      var income = 0.0;
      var expense = 0.0;
      var transfers = 0.0;

      for (final transaction in _transactions.where(
        (item) => _monthKey(item.transactionDate) == monthKey,
      )) {
        if (!transaction.transactionDate.isAfter(todayCutoff) &&
            transaction.status != TransactionStatus.planned) {
          continue;
        }
        final delta = _actualCashFlowDelta(transaction);
        if (delta == 0) {
          continue;
        }
        if (delta > 0) {
          income += delta;
        } else {
          expense += -delta;
        }
      }

      final net = income - expense + transfers;
      runningCash += net;
      return CashFlowProjectionPoint(
        monthKey: monthKey,
        income: income,
        expense: expense,
        transfers: transfers,
        net: net,
        endingCash: runningCash,
      );
    });
  }

  /// Net cash-account movement for transactions dated inside an exact
  /// calendar window. Both planned and future-dated actual records are
  /// included because this method is used by forward-looking UI projections.
  double cashFlowNetBetween({
    required DateTime startInclusive,
    required DateTime endInclusive,
  }) {
    final start = DateTime(
      startInclusive.year,
      startInclusive.month,
      startInclusive.day,
    );
    final end = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
      23,
      59,
      59,
      999,
    );
    return _transactions.where((transaction) {
      final date = transaction.transactionDate;
      return !date.isBefore(start) && !date.isAfter(end);
    }).fold<double>(
      0,
      (sum, transaction) => sum + _actualCashFlowDelta(transaction),
    );
  }

  /// Actual movement of cash-group accounts for the requested months.
  ///
  /// Credit-card purchases are excluded until cash is used to repay the card.
  /// Transfers between two cash accounts net to zero. Planned records are
  /// excluded unless [includePlanned] is explicitly enabled. Optional filters
  /// select the same transaction set shown by the transactions page before the
  /// cash movement is calculated.
  CashFlowSummary actualCashFlowSummaryForMonths(
    Iterable<String> monthKeys, {
    bool includePlanned = false,
    String? accountId,
    TransactionType? type,
    String? categoryId,
  }) {
    final allowedMonths = monthKeys.toSet();
    var inflow = 0.0;
    var outflow = 0.0;
    for (final transaction in _transactions) {
      if (!allowedMonths.contains(_monthKey(transaction.transactionDate)) ||
          (!includePlanned &&
              transaction.status == TransactionStatus.planned) ||
          (accountId != null &&
              transaction.accountId != accountId &&
              transaction.toAccountId != accountId) ||
          (type != null && transaction.type != type) ||
          (categoryId != null && transaction.categoryId != categoryId)) {
        continue;
      }
      final delta = _actualCashFlowDelta(transaction);
      if (delta >= 0) {
        inflow += delta;
      } else {
        outflow += -delta;
      }
    }
    return CashFlowSummary(inflow: inflow, outflow: outflow);
  }

  CashFlowSummary actualCashFlowSummaryForMonth(
    String monthKey, {
    bool includePlanned = false,
    String? accountId,
    TransactionType? type,
    String? categoryId,
  }) {
    return actualCashFlowSummaryForMonths(
      [monthKey],
      includePlanned: includePlanned,
      accountId: accountId,
      type: type,
      categoryId: categoryId,
    );
  }

  /// Total cash that must be available for a calendar month.
  ///
  /// Known cash outflow already includes actual transfers and, when requested,
  /// planned transfers. Credit-card and loan instalments that are due in the
  /// month are added only when no matching payment is already represented in
  /// that cash outflow, so repayments are never counted twice.
  MonthlyFundingNeed monthlyFundingNeedForMonth(
    String monthKey, {
    bool includePlanned = true,
  }) {
    final parts = monthKey.split('-');
    if (parts.length != 2) {
      throw ArgumentError.value(monthKey, 'monthKey', 'Expected YYYY-MM');
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      throw ArgumentError.value(monthKey, 'monthKey', 'Expected YYYY-MM');
    }

    final monthStart = DateTime(year, month);
    final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59, 999);
    final cashFlow = actualCashFlowSummaryForMonth(
      monthKey,
      includePlanned: includePlanned,
    );

    final creditDueByAccount = <String, _CreditDueSnapshot>{};
    final checkpoints = <DateTime>{monthStart};
    for (final account in _accounts.where(
      (item) =>
          item.isActive &&
          item.accountType == AccountType.creditCard &&
          item.hasCompleteCreditCardProfile,
    )) {
      checkpoints.add(_clampedMonthDay(year, month, account.statementDay!));
    }
    final orderedCheckpoints = checkpoints.toList()..sort();
    for (final checkpoint in orderedCheckpoints) {
      for (final reminder in creditCardPaymentReminders(asOf: checkpoint)) {
        if (reminder.dueDate.year != year || reminder.dueDate.month != month) {
          continue;
        }
        creditDueByAccount[reminder.account.id] = _CreditDueSnapshot(
          amount: convertToBase(
            reminder.amountDue,
            reminder.account.currency,
          ),
          asOf: checkpoint,
        );
      }
    }

    var creditDue = 0.0;
    var creditCovered = 0.0;
    for (final entry in creditDueByAccount.entries) {
      final due = entry.value.amount;
      creditDue += due;
      final covered = _transactions.where((transaction) {
        final date = transaction.transactionDate;
        if (transaction.type != TransactionType.transfer ||
            transaction.toAccountId != entry.key ||
            date.isBefore(monthStart) ||
            date.isAfter(monthEnd)) {
          return false;
        }
        if (transaction.status == TransactionStatus.planned) {
          return includePlanned;
        }
        return date.isAfter(entry.value.asOf);
      }).fold<double>(
        0,
        (sum, transaction) => sum + transferIncomingAmountInBase(transaction),
      );
      creditCovered += covered.clamp(0.0, due).toDouble();
    }

    var loanDue = 0.0;
    var loanCovered = 0.0;
    for (final loan in _accounts.where(
      (item) =>
          item.isActive &&
          item.accountType == AccountType.loan &&
          item.hasCompleteLoanProfile,
    )) {
      LoanAmortizationSchedule schedule;
      try {
        schedule = calculateLoanAmortization(
          principal: loan.loanPrincipal!,
          annualInterestRatePercent: loan.loanAnnualInterestRate!,
          termMonths: loan.loanTermMonths!,
          startDate: loan.loanTrackingStartDate ?? loan.loanStartDate!,
          paymentDay: loan.loanPaymentDay!,
          method: loan.loanRepaymentMethod!,
          quotedMonthlyPayment: loan.loanQuotedMonthlyPayment,
          openingPrincipal: loan.initialBalance.abs(),
        );
      } on ArgumentError {
        continue;
      }

      for (final installment in schedule.installments.where(
        (item) => item.dueDate.year == year && item.dueDate.month == month,
      )) {
        final paidBeforeMonth = _transactions.any((transaction) =>
            transaction.status != TransactionStatus.planned &&
            transaction.transactionDate.isBefore(monthStart) &&
            _isLoanInstallmentTransfer(
                transaction, loan.id, installment.number));
        if (paidBeforeMonth) continue;

        final due = convertToBase(installment.payment, loan.currency);
        loanDue += due;
        final covered = _loanInstallmentCoverageInMonth(
          loanId: loan.id,
          installmentNumber: installment.number,
          monthStart: monthStart,
          monthEnd: monthEnd,
          includePlanned: includePlanned,
        );
        loanCovered += covered.clamp(0.0, due).toDouble();
      }
    }

    return MonthlyFundingNeed(
      monthKey: monthKey,
      cashInflow: cashFlow.inflow,
      knownCashOutflow: cashFlow.outflow,
      creditDue: creditDue,
      loanDue: loanDue,
      coveredDebtPayments: creditCovered + loanCovered,
    );
  }

  double _loanInstallmentCoverageInMonth({
    required String loanId,
    required int installmentNumber,
    required DateTime monthStart,
    required DateTime monthEnd,
    required bool includePlanned,
  }) {
    final matchingTransfers = _transactions.where((transaction) {
      final date = transaction.transactionDate;
      return !date.isBefore(monthStart) &&
          !date.isAfter(monthEnd) &&
          (includePlanned || transaction.status != TransactionStatus.planned) &&
          transaction.type == TransactionType.transfer &&
          transaction.toAccountId == loanId;
    }).toList();
    var covered = matchingTransfers.fold<double>(
      0,
      (sum, transaction) => sum + transactionAmountInBase(transaction),
    );

    // Legacy plans stored principal and interest as two records. The transfer
    // identifies the loan; the companion interest expense shares source, date
    // and instalment number and must also cover the due payment.
    for (final transfer in matchingTransfers.where(
      (item) => item.description == '贷款本金 #$installmentNumber',
    )) {
      covered += _transactions.where((transaction) {
        final date = transaction.transactionDate;
        return transaction.type == TransactionType.expense &&
            transaction.accountId == transfer.accountId &&
            transaction.description == '贷款利息 #$installmentNumber' &&
            _sameDay(date, transfer.transactionDate) &&
            !date.isBefore(monthStart) &&
            !date.isAfter(monthEnd) &&
            (includePlanned || transaction.status != TransactionStatus.planned);
      }).fold<double>(
        0,
        (sum, transaction) => sum + transactionAmountInBase(transaction),
      );
    }
    return covered;
  }

  bool _isLoanInstallmentTransfer(
    FinanceTransaction transaction,
    String loanId,
    int installmentNumber,
  ) {
    if (transaction.type != TransactionType.transfer ||
        transaction.toAccountId != loanId) {
      return false;
    }
    final description = transaction.description ?? '';
    return description == '贷款月供 #$installmentNumber' ||
        description == '贷款本金 #$installmentNumber';
  }

  DateTime _clampedMonthDay(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay));
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  Map<String, double> actualCashOutflowByCategoryForMonths(
    Iterable<String> monthKeys,
  ) {
    final keys = monthKeys.toList();
    final result = <String, double>{};
    for (final category in _categories) {
      final outflow = actualCashFlowSummaryForMonths(
        keys,
        categoryId: category.id,
      ).outflow;
      if (outflow > 0) {
        result[category.id] = outflow;
      }
    }
    final total = actualCashFlowSummaryForMonths(keys).outflow;
    final categorized =
        result.values.fold<double>(0, (sum, item) => sum + item);
    final uncategorized = total - categorized;
    if (uncategorized > .005) {
      result[uncategorizedCashOutflowKey] = uncategorized;
    }
    return result;
  }

  Map<String, double> actualCashOutflowByAccountForMonth(String monthKey) {
    final result = <String, double>{};
    for (final account in _accounts.where(
      (item) => item.reportGroup == ReportGroup.cash,
    )) {
      final outflow = actualCashFlowSummaryForMonth(
        monthKey,
        accountId: account.id,
      ).outflow;
      if (outflow > 0) {
        result[account.id] = outflow;
      }
    }
    return result;
  }

  List<CreditCardPaymentReminder> creditCardPaymentReminders({
    DateTime? asOf,
  }) {
    final reference = asOf ?? DateTime.now();
    final cutoff = DateTime(
      reference.year,
      reference.month,
      reference.day,
      23,
      59,
      59,
      999,
    );
    return _accounts
        .where((account) => account.accountType == AccountType.creditCard)
        .map((account) {
          final summary = calculateCreditCardBilling(
            account: account,
            transactions: _transactions,
            now: reference,
            balanceAtCutoff: accountBalanceAt(account.id, cutoff),
          );
          return CreditCardPaymentReminder(
            account: account,
            amountDue: summary.billedBalance,
            dueDate: summary.dueDate,
          );
        })
        .where((item) => item.amountDue > 0)
        .toList()
      ..sort((a, b) => b.amountDue.compareTo(a.amountDue));
  }

  List<FinanceTransaction> transactionsForCategory(
    String categoryId, {
    String? monthKey,
  }) {
    final items = _transactions.where((item) => item.categoryId == categoryId);
    final filtered = monthKey == null
        ? items
        : items.where((item) => _monthKey(item.transactionDate) == monthKey);
    final list = filtered.toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return list;
  }

  List<MonthlySummary> monthlySummaries({required int months}) {
    final monthKeys = _recentMonthKeys(months);
    return monthKeys.map(
      (monthKey) {
        final cashFlow = actualCashFlowSummaryForMonth(monthKey);
        return MonthlySummary(
          monthKey: monthKey,
          income: cashFlow.inflow,
          expense: cashFlow.outflow,
        );
      },
    ).toList();
  }

  List<Budget> reusableBudgets() {
    final items = [..._budgets]..sort((a, b) {
        final categoryCompare =
            categoryName(a.categoryId).compareTo(categoryName(b.categoryId));
        if (categoryCompare != 0) {
          return categoryCompare;
        }
        return _compareMonthKeys(b.monthKey, a.monthKey);
      });
    return items;
  }

  List<Budget> activeBudgetsForMonth(String monthKey) {
    final latestByCategory = <String, Budget>{};
    for (final budget in _budgets) {
      if (_compareMonthKeys(budget.monthKey, monthKey) > 0) {
        continue;
      }
      final existing = latestByCategory[budget.categoryId];
      if (existing == null ||
          _compareMonthKeys(budget.monthKey, existing.monthKey) > 0) {
        latestByCategory[budget.categoryId] = budget;
      }
    }
    final items = latestByCategory.values.toList()
      ..sort((a, b) =>
          categoryName(a.categoryId).compareTo(categoryName(b.categoryId)));
    return items;
  }

  List<String> budgetMonthKeys({int futureMonths = 6}) {
    final now = DateTime.now();
    final monthKeys = <String>{
      monthKeyFromDate(now),
      ..._transactions.map((item) => monthKeyFromDate(item.transactionDate)),
      ..._budgets.map((item) => item.monthKey),
      ...List.generate(
          futureMonths,
          (index) =>
              monthKeyFromDate(DateTime(now.year, now.month + index + 1))),
    }.toList()
      ..sort((a, b) => _compareMonthKeys(b, a));
    return monthKeys;
  }

  double totalBudgetAmount({String? monthKey}) {
    final items = monthKey == null ? _budgets : activeBudgetsForMonth(monthKey);
    return items.fold(0, (sum, item) => sum + budgetAmountInBase(item));
  }

  double budgetAmountInBase(Budget budget) {
    return convertToBase(budget.amount, budget.currency);
  }

  double totalBudgetExpenseForMonth(String monthKey) {
    final budgetCategoryIds =
        activeBudgetsForMonth(monthKey).map((item) => item.categoryId).toSet();
    return _transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              item.status != TransactionStatus.planned &&
              item.categoryId != null &&
              budgetCategoryIds.contains(item.categoryId) &&
              _monthKey(item.transactionDate) == monthKey,
        )
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  double totalPlannedBudgetExpenseForMonth(String monthKey) {
    final budgetCategoryIds =
        activeBudgetsForMonth(monthKey).map((item) => item.categoryId).toSet();
    return _transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              item.status == TransactionStatus.planned &&
              item.categoryId != null &&
              budgetCategoryIds.contains(item.categoryId) &&
              _monthKey(item.transactionDate) == monthKey,
        )
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  double effectiveBudgetForMonth(Budget budget, String monthKey) {
    if (_compareMonthKeys(monthKey, budget.monthKey) < 0) {
      return 0;
    }

    final categoryBudgets = _budgets
        .where((item) => item.categoryId == budget.categoryId)
        .toList()
      ..sort((a, b) => _compareMonthKeys(a.monthKey, b.monthKey));
    if (categoryBudgets.isEmpty) {
      return 0;
    }

    final firstBudget = categoryBudgets.first;
    var carry = 0.0;
    for (final currentMonthKey
        in _monthKeyRange(firstBudget.monthKey, monthKey)) {
      final activeBudget =
          _budgetForCategoryInMonth(budget.categoryId, currentMonthKey);
      if (activeBudget == null) {
        carry = 0.0;
        continue;
      }
      final effective = budgetAmountInBase(activeBudget) + carry;
      if (currentMonthKey == monthKey) {
        return effective;
      }
      final spent =
          expenseTotalForCategory(activeBudget.categoryId, currentMonthKey);
      carry = activeBudget.rolloverEnabled ? (effective - spent) : 0.0;
    }
    return 0;
  }

  double totalEffectiveBudgetForMonth(String monthKey) {
    return activeBudgetsForMonth(monthKey)
        .fold(0, (sum, item) => sum + effectiveBudgetForMonth(item, monthKey));
  }

  Map<String, double> categoryTotalsForMonths({
    required CategoryType type,
    required List<String> monthKeys,
  }) {
    final allowedIds = categoriesByType(type).map((item) => item.id).toSet();
    final totals = <String, double>{};
    for (final transaction in _transactions) {
      final categoryId = transaction.categoryId;
      if (categoryId == null || !allowedIds.contains(categoryId)) {
        continue;
      }
      if (!monthKeys.contains(_monthKey(transaction.transactionDate))) {
        continue;
      }
      if (transaction.status == TransactionStatus.planned) {
        continue;
      }
      if (type == CategoryType.expense &&
          transaction.type != TransactionType.expense) {
        continue;
      }
      if (type == CategoryType.income &&
          transaction.type != TransactionType.income) {
        continue;
      }
      totals[categoryId] =
          (totals[categoryId] ?? 0) + transactionAmountInBase(transaction);
    }
    return totals;
  }

  ForecastSummary forecastSummary({int months = 3}) {
    final summaries = monthlySummaries(months: 12)
        .where((item) => item.income != 0 || item.expense != 0)
        .take(months)
        .toList();
    if (summaries.isEmpty) {
      return const ForecastSummary(
        averageMonthlyIncome: 0,
        averageMonthlyExpense: 0,
        averageMonthlySavings: 0,
        projectedSavingsInThreeMonths: 0,
        projectedSavingsInSixMonths: 0,
      );
    }

    final averageIncome =
        summaries.fold<double>(0, (sum, item) => sum + item.income) /
            summaries.length;
    final averageExpense =
        summaries.fold<double>(0, (sum, item) => sum + item.expense) /
            summaries.length;
    final averageSavings = averageIncome - averageExpense;
    final currentSavingsBase = totalAssetsByGroup(ReportGroup.cash) +
        totalAssetsByGroup(ReportGroup.investment) +
        totalAssetsByGroup(ReportGroup.retirement) +
        totalAssetsByGroup(ReportGroup.credit);

    return ForecastSummary(
      averageMonthlyIncome: averageIncome,
      averageMonthlyExpense: averageExpense,
      averageMonthlySavings: averageSavings,
      projectedSavingsInThreeMonths: currentSavingsBase + (averageSavings * 3),
      projectedSavingsInSixMonths: currentSavingsBase + (averageSavings * 6),
    );
  }

  double totalIncomeForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.income &&
            item.status != TransactionStatus.planned &&
            _monthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  double totalExpenseForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.expense &&
            item.status != TransactionStatus.planned &&
            _monthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  double plannedIncomeForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.income &&
            item.status == TransactionStatus.planned &&
            _monthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  double plannedExpenseForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.expense &&
            item.status == TransactionStatus.planned &&
            _monthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + transactionAmountInBase(item));
  }

  Future<FinanceRepository> addAccount(Account account) async {
    await database.insertAccount(account);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> updateExistingAccount(Account account) async {
    await database.updateAccount(account);
    return _refreshWithGoalSync();
  }

  Future<bool> canDeleteAccount(String accountId) {
    return database
        .accountHasLinkedData(accountId)
        .then((hasLinks) => !hasLinks);
  }

  Future<FinanceRepository?> deleteAccountIfSafe(String accountId) async {
    final deleted = await database.deleteAccountIfSafe(accountId);
    if (!deleted) {
      return null;
    }
    await database.deleteMetaValue(_accountReconciliationKey(accountId));
    return refresh();
  }

  Future<FinanceRepository> clearAllData() async {
    await database.clearAllUserData();
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> loadExampleData() async {
    await database.replaceAllWithSeedData(
      accountItems: SampleData.accounts(),
      categoryItems: SampleData.categories(),
      budgetItems: SampleData.budgets(),
      transactionItems: SampleData.transactions(),
      snapshotItems: SampleData.snapshots(),
    );
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> addAssetGoal({
    required String name,
    required double amount,
  }) async {
    final nextGoals = [
      ...assetGoals,
      AssetGoal(
        id: buildId('goal'),
        name: name,
        targetAmount: amount,
      ),
    ];
    await _saveAssetGoals(nextGoals);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> updateAssetGoal(AssetGoal goal) async {
    final nextGoals =
        assetGoals.map((item) => item.id == goal.id ? goal : item).toList();
    await _saveAssetGoals(nextGoals);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> deleteAssetGoal(String goalId) async {
    final nextGoals = assetGoals.where((item) => item.id != goalId).toList();
    await _saveAssetGoals(nextGoals);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> addTransactionTemplate({
    required String name,
    required FinanceTransaction transaction,
  }) async {
    final template = TransactionTemplate.fromTransaction(
      id: buildId('tpl'),
      name: name,
      transaction: transaction,
    );
    await _saveTransactionTemplates([
      ...transactionTemplates.where((item) => item.name != name),
      template,
    ]);
    return refresh();
  }

  Future<FinanceRepository> deleteTransactionTemplate(String templateId) async {
    await _saveTransactionTemplates(
      transactionTemplates.where((item) => item.id != templateId).toList(),
    );
    return refresh();
  }

  Future<FinanceRepository> saveTransactionTemplate(
    TransactionTemplate template,
  ) async {
    await _saveTransactionTemplates([
      ...transactionTemplates.where((item) => item.id != template.id),
      template,
    ]);
    return refresh();
  }

  Future<FinanceRepository> reorderTransactionTemplates(
    List<String> orderedTemplateIds,
  ) async {
    final templatesById = {
      for (final template in transactionTemplates) template.id: template,
    };
    if (orderedTemplateIds.length != templatesById.length ||
        orderedTemplateIds.toSet().length != templatesById.length ||
        orderedTemplateIds.any((id) => !templatesById.containsKey(id))) {
      throw ArgumentError.value(
        orderedTemplateIds,
        'orderedTemplateIds',
        'Template order must contain every template exactly once.',
      );
    }

    final reordered = orderedTemplateIds.indexed.map((entry) {
      final template = templatesById[entry.$2]!;
      return TransactionTemplate(
        id: template.id,
        name: template.name,
        type: template.type,
        accountId: template.accountId,
        toAccountId: template.toAccountId,
        categoryId: template.categoryId,
        amount: template.amount,
        currency: template.currency,
        toAmount: template.toAmount,
        toCurrency: template.toCurrency,
        status: template.status,
        description: template.description,
        merchant: template.merchant,
        sortOrder: entry.$1,
      );
    }).toList();
    await _saveTransactionTemplates(reordered);
    return refresh();
  }

  Future<FinanceRepository> addRecurringTransactionRule({
    required String name,
    required FinanceTransaction transaction,
    int intervalMonths = 1,
  }) async {
    final rule = RecurringTransactionRule.fromTransaction(
      id: buildId('rule'),
      name: name,
      transaction: transaction,
      intervalMonths: intervalMonths,
    );
    await _saveRecurringTransactionRules([
      ...recurringTransactionRules.where((item) => item.name != name),
      rule,
    ]);
    final refreshed = await refresh();
    return refreshed.generateRecurringTransactions(
      rule.id,
      monthsAhead: 3,
    );
  }

  Future<FinanceRepository> deleteRecurringTransactionRule(
      String ruleId) async {
    await _saveRecurringTransactionRules(
      recurringTransactionRules.where((item) => item.id != ruleId).toList(),
    );
    return refresh();
  }

  Future<FinanceRepository> saveRecurringTransactionRule(
    RecurringTransactionRule rule,
  ) async {
    await _saveRecurringTransactionRules([
      ...recurringTransactionRules.where((item) => item.id != rule.id),
      rule,
    ]);
    return refresh();
  }

  Future<FinanceRepository> generateRecurringTransactions(
    String ruleId, {
    int monthsAhead = 6,
  }) async {
    final rules = recurringTransactionRules;
    RecurringTransactionRule? rule;
    for (final item in rules) {
      if (item.id == ruleId) {
        rule = item;
        break;
      }
    }
    final activeRule = rule;
    if (activeRule == null || !activeRule.isActive) {
      return refresh();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(now.year, now.month + monthsAhead + 1, 0);
    final generatedKeys = {...activeRule.generatedMonthKeys};
    final transactions = <FinanceTransaction>[];
    var generatedCount = 0;
    var cursor = DateTime(
      activeRule.startDate.year,
      activeRule.startDate.month,
      activeRule.startDate.day,
    );

    while (!cursor.isAfter(endDate)) {
      final currentMonthKey = _monthKey(cursor);
      if (cursor.isAfter(today) &&
          !generatedKeys.contains(currentMonthKey) &&
          (activeRule.endDate == null ||
              !cursor.isAfter(activeRule.endDate!))) {
        transactions.add(
          activeRule.toTransaction(
            id: '${buildId('txn')}_${generatedCount++}',
            date: cursor,
            status: TransactionStatus.planned,
          ),
        );
        generatedKeys.add(currentMonthKey);
      }
      cursor = DateTime(
        cursor.year,
        cursor.month + activeRule.intervalMonths,
        cursor.day,
      );
    }

    if (transactions.isNotEmpty) {
      await database.insertTransactions(transactions);
    }
    final nextRules = rules
        .map(
          (item) => item.id == activeRule.id
              ? item.copyWith(generatedMonthKeys: generatedKeys.toList())
              : item,
        )
        .toList();
    await _saveRecurringTransactionRules(nextRules);
    return _refreshWithGoalSync();
  }

  Future<Map<String, dynamic>> buildJsonSnapshotPayload() async {
    final metaValues = await database.fetchAllMetaValues();
    final exportableMeta = Map<String, String>.from(metaValues)
      ..remove('data_migration_version')
      ..remove('transaction_templates_json')
      ..remove('recurring_transaction_rules_json');
    return {
      'format_version': 3,
      'transaction_date_semantics': 'occurrence_date',
      'app_version': '0.8.0',
      'schema_version': 9,
      'exported_at': DateTime.now().toIso8601String(),
      'meta': exportableMeta,
      'accounts': _accounts
          .map(
            (item) => {
              'id': item.id,
              'name': item.name,
              'account_type': item.accountType.name,
              'report_group': item.reportGroup.name,
              'currency': item.currency,
              'initial_balance': item.initialBalance,
              'current_balance': item.currentBalance,
              'institution': item.institution,
              'note': item.note,
              'is_active': item.isActive,
              'credit_limit': item.creditLimit,
              'statement_day': item.statementDay,
              'payment_due_day': item.paymentDueDay,
              'loan_principal': item.loanPrincipal,
              'loan_annual_interest_rate': item.loanAnnualInterestRate,
              'loan_term_months': item.loanTermMonths,
              'loan_start_date': item.loanStartDate?.toIso8601String(),
              'loan_tracking_start_date':
                  item.loanTrackingStartDate?.toIso8601String(),
              'loan_payment_day': item.loanPaymentDay,
              'loan_repayment_method': item.loanRepaymentMethod?.name,
              'loan_quoted_monthly_payment': item.loanQuotedMonthlyPayment,
            },
          )
          .toList(),
      'categories': _categories
          .map(
            (item) => {
              'id': item.id,
              'name': item.name,
              'type': item.type.name,
              'parent_id': item.parentId,
              'icon_key': item.iconKey,
              'color_value': item.colorValue,
              'sort_order': item.sortOrder,
              'is_archived': item.isArchived,
            },
          )
          .toList(),
      'budgets': _budgets
          .map(
            (item) => {
              'id': item.id,
              'category_id': item.categoryId,
              'month_key': item.monthKey,
              'amount': item.amount,
              'currency': item.currency,
              'alert_threshold': item.alertThreshold,
              'rollover_enabled': item.rolloverEnabled,
            },
          )
          .toList(),
      'transactions': _transactions
          .map(
            (item) => {
              'id': item.id,
              'type': item.type.name,
              'account_id': item.accountId,
              'to_account_id': item.toAccountId,
              'category_id': item.categoryId,
              'amount': item.amount,
              'currency': item.currency,
              'to_amount': item.toAmount,
              'to_currency': item.toCurrency,
              'record_date': item.recordDate.toIso8601String(),
              'transaction_date': item.transactionDate.toIso8601String(),
              'status': item.status.name,
              'recurring_rule_id': item.recurringRuleId,
              'description': item.description,
              'merchant': item.merchant,
            },
          )
          .toList(),
      'asset_snapshots': _snapshots
          .map(
            (item) => {
              'id': item.id,
              'account_id': item.accountId,
              'snapshot_date': item.snapshotDate.toIso8601String(),
              'market_value': item.marketValue,
              'cost_basis': item.costBasis,
              'cash_balance': item.cashBalance,
              'unrealized_pnl': item.unrealizedPnl,
            },
          )
          .toList(),
      'transaction_templates':
          transactionTemplates.map((item) => item.toJson()).toList(),
      'recurring_transaction_rules':
          recurringTransactionRules.map((item) => item.toJson()).toList(),
    };
  }

  Future<Uint8List> exportJsonSnapshotBytes() async {
    final payload = await buildJsonSnapshotPayload();
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  Future<String> exportJsonSnapshot([String? targetPath]) async {
    final payload = await buildJsonSnapshotPayload();
    return local_files.writeUtf8Text(
      targetPath ?? await local_files.defaultExportPath(),
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Map<String, dynamic> buildAiSummaryPayload(
      {required List<String> monthKeys}) {
    final includedMonths = monthKeys.where((monthKey) {
      return totalIncomeForMonth(monthKey) != 0 ||
          totalExpenseForMonth(monthKey) != 0 ||
          plannedIncomeForMonth(monthKey) != 0 ||
          plannedExpenseForMonth(monthKey) != 0;
    }).toList();
    final currentMonth = monthKeyFromDate(DateTime.now());
    return {
      'exported_at': DateTime.now().toIso8601String(),
      'base_currency': baseCurrency,
      'currency_priority': currencyPriority,
      'exchange_rates_to_base': exchangeRatesToBase,
      'months': includedMonths,
      'income_by_month': {
        for (final monthKey in includedMonths)
          monthKey: totalIncomeForMonth(monthKey),
      },
      'expense_by_month': {
        for (final monthKey in includedMonths)
          monthKey: totalExpenseForMonth(monthKey),
      },
      'planned_income_by_month': {
        for (final monthKey in includedMonths)
          monthKey: plannedIncomeForMonth(monthKey),
      },
      'planned_expense_by_month': {
        for (final monthKey in includedMonths)
          monthKey: plannedExpenseForMonth(monthKey),
      },
      'net_by_month': {
        for (final monthKey in includedMonths)
          monthKey:
              totalIncomeForMonth(monthKey) - totalExpenseForMonth(monthKey),
      },
      'expense_categories_by_month': {
        for (final monthKey in includedMonths)
          monthKey: {
            for (final entry in categoryTotalsForMonths(
              type: CategoryType.expense,
              monthKeys: [monthKey],
            ).entries)
              categoryName(entry.key): entry.value,
          },
      },
      'income_categories_by_month': {
        for (final monthKey in includedMonths)
          monthKey: {
            for (final entry in categoryTotalsForMonths(
              type: CategoryType.income,
              monthKeys: [monthKey],
            ).entries)
              categoryName(entry.key): entry.value,
          },
      },
      'expense_category_totals': {
        for (final entry in categoryTotalsForMonths(
          type: CategoryType.expense,
          monthKeys: includedMonths,
        ).entries)
          categoryName(entry.key): entry.value,
      },
      'income_category_totals': {
        for (final entry in categoryTotalsForMonths(
          type: CategoryType.income,
          monthKeys: includedMonths,
        ).entries)
          categoryName(entry.key): entry.value,
      },
      'assets_by_group': {
        'cash': totalAssetsByGroup(ReportGroup.cash),
        'credit': totalAssetsByGroup(ReportGroup.credit),
        'investment': totalAssetsByGroup(ReportGroup.investment),
        'retirement': totalAssetsByGroup(ReportGroup.retirement),
      },
      'budgets_current_month': {
        for (final budget in activeBudgetsForMonth(currentMonth))
          categoryName(budget.categoryId): {
            'budget': effectiveBudgetForMonth(budget, currentMonth),
            'spent': expenseTotalForCategory(budget.categoryId, currentMonth),
          },
      },
    };
  }

  Uint8List exportAiSummaryBytes({required List<String> monthKeys}) {
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(
          buildAiSummaryPayload(monthKeys: monthKeys),
        ),
      ),
    );
  }

  Uint8List exportFuturePlanningCsvBytes({int months = 24}) {
    final now = DateTime.now();
    final monthKeys = List.generate(
      months,
      (index) => monthKeyFromDate(DateTime(now.year, now.month + index + 1)),
    );

    final categoryIds = <String>{
      ...categoriesByType(CategoryType.expense).map((item) => item.id),
    }.where((categoryId) {
      final hasBudget = _budgets.any((item) => item.categoryId == categoryId);
      final hasFutureExpense = monthKeys.any(
        (monthKey) =>
            expenseTotalForCategory(categoryId, monthKey) != 0 ||
            plannedExpenseTotalForCategory(categoryId, monthKey) != 0,
      );
      return hasBudget || hasFutureExpense;
    }).toList()
      ..sort((a, b) => categoryName(a).compareTo(categoryName(b)));

    final lines = <List<String>>[];
    lines.add([
      'Category',
      'Base Budget',
      ...monthKeys,
      'Planned Total',
    ]);

    for (final categoryId in categoryIds) {
      final budget = _budgets
          .where((item) => item.categoryId == categoryId)
          .toList()
        ..sort((a, b) => _compareMonthKeys(b.monthKey, a.monthKey));
      final baseBudget =
          budget.isEmpty ? 0.0 : budgetAmountInBase(budget.first);
      final monthValues = monthKeys
          .map((monthKey) =>
              expenseTotalForCategory(categoryId, monthKey) +
              plannedExpenseTotalForCategory(categoryId, monthKey))
          .toList();
      final plannedTotal =
          monthValues.fold<double>(0, (sum, item) => sum + item);
      lines.add([
        categoryName(categoryId),
        _csvMoney(baseBudget),
        ...monthValues.map(_csvMoney),
        _csvMoney(plannedTotal),
      ]);
    }

    final monthlyTotals = monthKeys
        .map(
          (monthKey) => categoryIds.fold<double>(
            0,
            (sum, categoryId) =>
                sum +
                expenseTotalForCategory(categoryId, monthKey) +
                plannedExpenseTotalForCategory(categoryId, monthKey),
          ),
        )
        .toList();
    final monthlyBudgets = monthKeys
        .map(
          (monthKey) => activeBudgetsForMonth(monthKey).fold<double>(
            0,
            (sum, budget) => sum + effectiveBudgetForMonth(budget, monthKey),
          ),
        )
        .toList();

    lines.add([
      'Total Planned',
      '',
      ...monthlyTotals.map(_csvMoney),
      _csvMoney(monthlyTotals.fold<double>(0, (sum, item) => sum + item)),
    ]);
    lines.add([
      'Total Budget',
      '',
      ...monthlyBudgets.map(_csvMoney),
      _csvMoney(monthlyBudgets.fold<double>(0, (sum, item) => sum + item)),
    ]);

    final csv = lines.map((row) => row.map(_csvEscape).join(',')).join('\n');
    return Uint8List.fromList(utf8.encode(csv));
  }

  Future<String> exportAiSummaryJson(String targetPath,
      {required List<String> monthKeys}) async {
    final payload = buildAiSummaryPayload(monthKeys: monthKeys);
    return local_files.writeUtf8Text(
      targetPath,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<FinanceRepository> importJsonSnapshot(String path) async {
    return importJsonSnapshotBytes(await local_files.readFileBytes(path));
  }

  /// Browser imports use picker bytes, avoiding a fake filesystem path.
  Future<FinanceRepository> importJsonSnapshotBytes(Uint8List bytes) async {
    final payload = _decodeImportPayload(bytes);
    final metaPayload = payload['meta'] as Map<String, dynamic>? ?? const {};

    final accountItems = (payload['accounts'] as List<dynamic>? ?? const [])
        .map(
          (item) => Account(
            id: item['id'] as String,
            name: item['name'] as String,
            accountType:
                AccountType.values.byName(item['account_type'] as String),
            reportGroup:
                ReportGroup.values.byName(item['report_group'] as String),
            currency: item['currency'] as String? ?? 'MYR',
            initialBalance: (item['initial_balance'] as num?)?.toDouble() ?? 0,
            currentBalance: (item['current_balance'] as num?)?.toDouble() ?? 0,
            institution: item['institution'] as String?,
            note: item['note'] as String?,
            isActive: item['is_active'] as bool? ?? true,
            creditLimit: (item['credit_limit'] as num?)?.toDouble(),
            statementDay: (item['statement_day'] as num?)?.toInt(),
            paymentDueDay: (item['payment_due_day'] as num?)?.toInt(),
            loanPrincipal: (item['loan_principal'] as num?)?.toDouble(),
            loanAnnualInterestRate:
                (item['loan_annual_interest_rate'] as num?)?.toDouble(),
            loanTermMonths: (item['loan_term_months'] as num?)?.toInt(),
            loanStartDate: item['loan_start_date'] == null
                ? null
                : DateTime.parse(item['loan_start_date'] as String),
            loanTrackingStartDate: item['loan_tracking_start_date'] == null
                ? null
                : DateTime.parse(item['loan_tracking_start_date'] as String),
            loanPaymentDay: (item['loan_payment_day'] as num?)?.toInt(),
            loanRepaymentMethod: item['loan_repayment_method'] == null
                ? null
                : LoanRepaymentMethod.values
                    .byName(item['loan_repayment_method'] as String),
            loanQuotedMonthlyPayment:
                (item['loan_quoted_monthly_payment'] as num?)?.toDouble(),
          ),
        )
        .toList();
    final creditCardAccountIds = accountItems
        .where((item) => item.accountType == AccountType.creditCard)
        .map((item) => item.id)
        .toSet();
    final formatVersion = (payload['format_version'] as num?)?.toInt() ?? 1;
    final usesLegacySettlementDates = formatVersion < 3;
    final categoryItems = (payload['categories'] as List<dynamic>? ?? const [])
        .map(
          (item) => Category(
            id: item['id'] as String,
            name: item['name'] as String,
            type: CategoryType.values.byName(item['type'] as String),
            parentId: item['parent_id'] as String?,
            iconKey: item['icon_key'] as String?,
            colorValue: (item['color_value'] as num?)?.toInt(),
            sortOrder: (item['sort_order'] as num?)?.toInt() ?? 0,
            isArchived: item['is_archived'] as bool? ?? false,
          ),
        )
        .toList();
    final budgetItems = (payload['budgets'] as List<dynamic>? ?? const [])
        .map(
          (item) => Budget(
            id: item['id'] as String,
            categoryId: item['category_id'] as String,
            monthKey: item['month_key'] as String,
            amount: (item['amount'] as num).toDouble(),
            currency: item['currency'] as String? ?? 'MYR',
            alertThreshold:
                (item['alert_threshold'] as num?)?.toDouble() ?? 0.8,
            rolloverEnabled: item['rollover_enabled'] as bool? ?? false,
          ),
        )
        .toList();
    final transactionItems =
        (payload['transactions'] as List<dynamic>? ?? const []).map((item) {
      final recordDate = DateTime.parse(
        (item['record_date'] as String?) ?? item['transaction_date'] as String,
      );
      final accountId = item['account_id'] as String;
      final toAccountId = item['to_account_id'] as String?;
      final involvesCreditCard = creditCardAccountIds.contains(accountId) ||
          (toAccountId != null && creditCardAccountIds.contains(toAccountId));
      return FinanceTransaction(
        id: item['id'] as String,
        type: TransactionType.values.byName(item['type'] as String),
        accountId: accountId,
        toAccountId: toAccountId,
        categoryId: item['category_id'] as String?,
        amount: (item['amount'] as num).toDouble(),
        currency: item['currency'] as String? ?? 'MYR',
        toAmount: (item['to_amount'] as num?)?.toDouble(),
        toCurrency: item['to_currency'] as String?,
        recordDate: recordDate,
        transactionDate: usesLegacySettlementDates && involvesCreditCard
            ? recordDate
            : DateTime.parse(item['transaction_date'] as String),
        status: item['status'] == null
            ? TransactionStatus.actual
            : TransactionStatus.values.byName(item['status'] as String),
        recurringRuleId: item['recurring_rule_id'] as String?,
        description: item['description'] as String?,
        merchant: item['merchant'] as String?,
      );
    }).toList();
    final legacyTemplatePayload = metaPayload['transaction_templates_json'];
    final legacyRulePayload = metaPayload['recurring_transaction_rules_json'];
    final templatePayload =
        payload['transaction_templates'] as List<dynamic>? ??
            (legacyTemplatePayload is String && legacyTemplatePayload.isNotEmpty
                ? jsonDecode(legacyTemplatePayload) as List<dynamic>
                : const []);
    final recurringRulePayload =
        payload['recurring_transaction_rules'] as List<dynamic>? ??
            (legacyRulePayload is String && legacyRulePayload.isNotEmpty
                ? jsonDecode(legacyRulePayload) as List<dynamic>
                : const []);
    final templateItems = templatePayload
        .whereType<Map>()
        .map((item) => preset.TransactionTemplate.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
    final recurringRuleItems = recurringRulePayload
        .whereType<Map>()
        .map((item) => preset.RecurringTransactionRule.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
    final snapshotItems =
        (payload['asset_snapshots'] as List<dynamic>? ?? const [])
            .map(
              (item) => AssetSnapshot(
                id: item['id'] as String,
                accountId: item['account_id'] as String,
                snapshotDate: DateTime.parse(item['snapshot_date'] as String),
                marketValue: (item['market_value'] as num).toDouble(),
                costBasis: (item['cost_basis'] as num?)?.toDouble() ?? 0,
                cashBalance: (item['cash_balance'] as num?)?.toDouble() ?? 0,
                unrealizedPnl:
                    (item['unrealized_pnl'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList();

    _validateImportReferences(
      accounts: accountItems,
      categories: categoryItems,
      budgets: budgetItems,
      transactions: transactionItems,
      snapshots: snapshotItems,
      templates: templateItems,
      recurringRules: recurringRuleItems,
    );

    final hasAnyData = accountItems.isNotEmpty ||
        categoryItems.isNotEmpty ||
        budgetItems.isNotEmpty ||
        transactionItems.isNotEmpty ||
        snapshotItems.isNotEmpty;
    if (!hasAnyData) {
      throw const FormatException(
          'Import file does not contain any finance data.');
    }

    final restorePoint = await local_files.importRestorePointPath();
    if (restorePoint != null) await exportJsonSnapshot(restorePoint);

    await database.replaceAllWithSeedData(
      accountItems: accountItems,
      categoryItems: categoryItems,
      budgetItems: budgetItems,
      transactionItems: transactionItems,
      snapshotItems: snapshotItems,
      templateItems: templateItems,
      recurringRuleItems: recurringRuleItems,
      metaValues: {
        for (final entry in metaPayload.entries) entry.key: '${entry.value}',
      },
    );
    return refresh();
  }

  Future<ImportPreview> previewImportJson(String path) async {
    return previewImportBytes(await local_files.readFileBytes(path));
  }

  Future<ImportPreview> previewImportBytes(Uint8List bytes) async {
    final payload = _decodeImportPayload(bytes);
    return ImportPreview(
      accounts: (payload['accounts'] as List<dynamic>? ?? const []).length,
      categories: (payload['categories'] as List<dynamic>? ?? const []).length,
      budgets: (payload['budgets'] as List<dynamic>? ?? const []).length,
      transactions:
          (payload['transactions'] as List<dynamic>? ?? const []).length,
      assetSnapshots:
          (payload['asset_snapshots'] as List<dynamic>? ?? const []).length,
      exportedAt: payload['exported_at'] as String?,
    );
  }

  Map<String, dynamic> _decodeImportPayload(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('所选 JSON 是空文件（0 KB），没有导入任何数据。');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw FormatException('JSON 内容不完整或已损坏：${error.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('Finance Compass JSON 顶层必须是对象。');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final formatVersion = (payload['format_version'] as num?)?.toInt() ?? 1;
    if (formatVersion < 1 || formatVersion > 3) {
      throw FormatException('不支持的备份格式版本：$formatVersion。');
    }
    const listFields = [
      'accounts',
      'categories',
      'budgets',
      'transactions',
      'asset_snapshots',
      'transaction_templates',
      'recurring_transaction_rules',
    ];
    for (final field in listFields) {
      final value = payload[field];
      if (value != null && value is! List) {
        throw FormatException('JSON 字段 "$field" 必须是数组。');
      }
    }
    if (payload['meta'] != null && payload['meta'] is! Map) {
      throw const FormatException('JSON 字段 "meta" 必须是对象。');
    }
    return payload;
  }

  void _validateImportReferences({
    required List<Account> accounts,
    required List<Category> categories,
    required List<Budget> budgets,
    required List<FinanceTransaction> transactions,
    required List<AssetSnapshot> snapshots,
    required List<preset.TransactionTemplate> templates,
    required List<preset.RecurringTransactionRule> recurringRules,
  }) {
    Set<String> uniqueIds(Iterable<String> ids, String label) {
      final values = <String>{};
      for (final id in ids) {
        if (id.trim().isEmpty || !values.add(id)) {
          throw FormatException('$label包含空白或重复 ID：$id');
        }
      }
      return values;
    }

    final accountIds = uniqueIds(accounts.map((item) => item.id), '账户');
    final categoryIds = uniqueIds(categories.map((item) => item.id), '类别');
    uniqueIds(budgets.map((item) => item.id), '预算');
    uniqueIds(transactions.map((item) => item.id), '交易');
    uniqueIds(snapshots.map((item) => item.id), '资产快照');
    uniqueIds(templates.map((item) => item.id), '快速模板');
    final recurringRuleIds =
        uniqueIds(recurringRules.map((item) => item.id), '周期规则');

    void requireAccount(String id, String owner) {
      if (!accountIds.contains(id)) {
        throw FormatException('$owner 引用了不存在的账户：$id');
      }
    }

    void requireCategory(String? id, String owner) {
      if (id != null && !categoryIds.contains(id)) {
        throw FormatException('$owner 引用了不存在的类别：$id');
      }
    }

    for (final category in categories) {
      requireCategory(category.parentId, '类别 ${category.id}');
    }
    for (final budget in budgets) {
      requireCategory(budget.categoryId, '预算 ${budget.id}');
    }
    for (final transaction in transactions) {
      requireAccount(transaction.accountId, '交易 ${transaction.id}');
      if (transaction.toAccountId case final String targetId) {
        requireAccount(targetId, '交易 ${transaction.id}');
      }
      requireCategory(transaction.categoryId, '交易 ${transaction.id}');
      if (transaction.recurringRuleId case final String ruleId) {
        if (!recurringRuleIds.contains(ruleId)) {
          throw FormatException('交易 ${transaction.id} 引用了不存在的周期规则：$ruleId');
        }
      }
    }
    for (final snapshot in snapshots) {
      requireAccount(snapshot.accountId, '资产快照 ${snapshot.id}');
    }
    for (final template in templates) {
      requireAccount(template.accountId, '快速模板 ${template.id}');
      if (template.toAccountId case final String targetId) {
        requireAccount(targetId, '快速模板 ${template.id}');
      }
      requireCategory(template.categoryId, '快速模板 ${template.id}');
    }
    for (final rule in recurringRules) {
      requireAccount(rule.accountId, '周期规则 ${rule.id}');
      if (rule.toAccountId case final String targetId) {
        requireAccount(targetId, '周期规则 ${rule.id}');
      }
      requireCategory(rule.categoryId, '周期规则 ${rule.id}');
    }
  }

  Future<FinanceRepository> addCategory(Category category) async {
    await database.insertCategory(category);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> updateExistingCategory(Category category) async {
    await database.updateCategory(category);
    return _refreshWithGoalSync();
  }

  Future<bool> canDeleteCategory(String categoryId) {
    return database
        .categoryHasLinkedData(categoryId)
        .then((hasLinks) => !hasLinks);
  }

  Future<FinanceRepository?> deleteCategoryIfSafe(String categoryId) async {
    final deleted = await database.deleteCategoryIfSafe(categoryId);
    if (!deleted) {
      return null;
    }
    return refresh();
  }

  Future<FinanceRepository> addBudget(Budget budget) async {
    await database.upsertBudget(budget);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> deleteExistingBudget(String budgetId) async {
    await database.deleteBudget(budgetId);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> addTransaction(
      FinanceTransaction transaction) async {
    await database.insertTransaction(transaction);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> addTransactions(
      List<FinanceTransaction> transactions) async {
    if (transactions.isEmpty) {
      return refresh();
    }
    await database.insertTransactions(transactions);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> updateExistingTransaction(
      FinanceTransaction transaction) async {
    await database.updateTransaction(transaction);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> deleteExistingTransaction(
      String transactionId) async {
    await database.deleteTransaction(transactionId);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> deleteExistingTransactions(
      Iterable<String> transactionIds) async {
    await database.deleteTransactionsByIds(transactionIds);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> addAssetSnapshot(AssetSnapshot snapshot) async {
    await database.insertAssetSnapshot(snapshot);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> updateExistingAssetSnapshot(
      AssetSnapshot snapshot) async {
    await database.updateAssetSnapshot(snapshot);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> deleteExistingAssetSnapshot(
      String snapshotId) async {
    await database.deleteAssetSnapshot(snapshotId);
    return _refreshWithGoalSync();
  }

  String _monthKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  int _compareMonthKeys(String left, String right) {
    final leftParts = left.split('-');
    final rightParts = right.split('-');
    if (leftParts.length != 2 || rightParts.length != 2) {
      return left.compareTo(right);
    }
    final leftYear = int.tryParse(leftParts[0]) ?? 0;
    final leftMonth = int.tryParse(leftParts[1]) ?? 0;
    final rightYear = int.tryParse(rightParts[0]) ?? 0;
    final rightMonth = int.tryParse(rightParts[1]) ?? 0;
    return DateTime(leftYear, leftMonth)
        .compareTo(DateTime(rightYear, rightMonth));
  }

  Budget? _budgetForCategoryInMonth(String categoryId, String monthKey) {
    Budget? latest;
    for (final budget
        in _budgets.where((item) => item.categoryId == categoryId)) {
      if (_compareMonthKeys(budget.monthKey, monthKey) > 0) {
        continue;
      }
      if (latest == null ||
          _compareMonthKeys(budget.monthKey, latest.monthKey) > 0) {
        latest = budget;
      }
    }
    return latest;
  }

  List<String> _monthKeyRange(String startMonthKey, String endMonthKey) {
    final startParts = startMonthKey.split('-');
    final endParts = endMonthKey.split('-');
    if (startParts.length != 2 || endParts.length != 2) {
      return [endMonthKey];
    }
    final start = DateTime(int.parse(startParts[0]), int.parse(startParts[1]));
    final end = DateTime(int.parse(endParts[0]), int.parse(endParts[1]));
    final result = <String>[];
    var current = start;
    while (!current.isAfter(end)) {
      result.add(_monthKey(current));
      current = DateTime(current.year, current.month + 1);
    }
    return result;
  }

  List<String> _recentMonthKeys(int count) {
    final now = DateTime.now();
    return List.generate(count, (index) {
      final date = DateTime(now.year, now.month - (count - index - 1));
      return _monthKey(date);
    });
  }

  Future<FinanceRepository> _refreshWithGoalSync() async {
    final refreshed = await refresh();
    await refreshed._syncAssetGoalReachedAt();
    return FinanceRepository.load(database);
  }

  Future<void> _syncAssetGoalReachedAt() async {
    if (assetGoals.isEmpty) {
      await database.deleteMetaValue('asset_goals_json');
      await database.deleteMetaValue('asset_goal_amount');
      await database.deleteMetaValue('asset_goal_reached_at');
      return;
    }
    final syncedGoals = assetGoalSummaries(cutoffDate: currentMonthCutoffDate())
        .map(
          (summary) => summary.goal.copyWith(
            reachedAt: summary.reachedAt == null
                ? null
                : DateTime(
                    summary.reachedAt!.year,
                    summary.reachedAt!.month,
                    summary.reachedAt!.day,
                  ),
          ),
        )
        .toList();
    await _saveAssetGoals(syncedGoals);
    await database.deleteMetaValue('asset_goal_amount');
    await database.deleteMetaValue('asset_goal_reached_at');
  }

  Future<void> _saveAssetGoals(List<AssetGoal> goals) async {
    if (goals.isEmpty) {
      await database.deleteMetaValue('asset_goals_json');
      return;
    }
    await database.setMetaValue(
      'asset_goals_json',
      jsonEncode(goals.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _saveTransactionTemplates(
    List<TransactionTemplate> templates,
  ) async {
    await database.replaceTransactionTemplates(
      templates
          .map((item) => preset.TransactionTemplate.fromJson(item.toJson()))
          .toList(),
    );
    await database.setMetaValue(
      'transaction_templates_json',
      jsonEncode(templates.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _saveRecurringTransactionRules(
    List<RecurringTransactionRule> rules,
  ) async {
    await database.replaceRecurringTransactionRules(
      rules
          .map(
              (item) => preset.RecurringTransactionRule.fromJson(item.toJson()))
          .toList(),
    );
    await database.setMetaValue(
      'recurring_transaction_rules_json',
      jsonEncode(rules.map((item) => item.toJson()).toList()),
    );
  }

  List<String> _normalizeCurrencyPriority(List<String> currencies) {
    final ordered = currencies
        .map(normalizeCurrency)
        .where(supportedCurrencies.contains)
        .toSet()
        .toList();
    return [
      ...ordered,
      ...supportedCurrencies.where((item) => !ordered.contains(item)),
    ];
  }

  Map<String, double> _defaultRatesForBase(String baseCurrency) {
    final base = normalizeCurrency(baseCurrency);
    final converted = <String, double>{};
    for (final currency in supportedCurrencies) {
      converted[currency] = convertCurrencyAmount(
        amount: 1,
        fromCurrency: currency,
        toCurrency: base,
        ratesToBase: defaultExchangeRatesToBase,
        baseCurrency: baseCurrencyCode,
      );
    }
    converted[base] = 1;
    return normalizedExchangeRatesToBase(converted, baseCurrency: base);
  }

  double _accountBalanceAt(Account account, DateTime date) {
    final accountSnapshots = snapshotsForAccount(account.id);
    AssetSnapshot? latestSnapshotBeforeDate;
    for (final snapshot in accountSnapshots) {
      if (!snapshot.snapshotDate.isAfter(date)) {
        latestSnapshotBeforeDate = snapshot;
      }
    }

    if (latestSnapshotBeforeDate != null) {
      return _snapshotAnchoredAdjustments(
        account.id,
        latestSnapshotBeforeDate,
        date,
      ).fold(
        latestSnapshotBeforeDate.marketValue,
        (balance, item) => balance + item.appliedDelta,
      );
    }

    if (accountSnapshots.isNotEmpty) {
      // Before the first snapshot, currentBalance already reflects future
      // snapshots, so rebuild the pre-snapshot ledger forward instead.
      var balance = account.initialBalance;
      for (final transaction in _transactions) {
        if (!transaction.transactionDate.isAfter(date)) {
          balance += _transactionDeltaForAccount(account.id, transaction);
        }
      }
      return balance;
    }

    var balance = account.currentBalance;
    for (final transaction in _transactions) {
      if (transaction.transactionDate.isAfter(date)) {
        balance -= _transactionDeltaForAccount(account.id, transaction);
      }
    }
    return balance;
  }

  /// Adjustments from [anchor]'s market value to the balance at [date].
  ///
  /// Transfers/adjustments are folded into the latest snapshot's market value
  /// when recorded, so those dated after [date] are taken back out. Income and
  /// expense are never folded, so those in (anchor date, [date]] are added and
  /// later ones are ignored. Forward items come first (oldest first), then
  /// reversals (newest first).
  List<({FinanceTransaction transaction, double appliedDelta})>
      _snapshotAnchoredAdjustments(
    String accountId,
    AssetSnapshot anchor,
    DateTime date,
  ) {
    final forward = <({FinanceTransaction transaction, double appliedDelta})>[];
    final reversed =
        <({FinanceTransaction transaction, double appliedDelta})>[];
    for (final transaction in _transactions) {
      if (!transaction.transactionDate.isAfter(anchor.snapshotDate)) {
        continue;
      }
      final delta = _transactionDeltaForAccount(accountId, transaction);
      if (delta == 0) {
        continue;
      }
      final afterDate = transaction.transactionDate.isAfter(date);
      if (_foldsIntoSnapshot(transaction)) {
        if (afterDate) {
          reversed.add((transaction: transaction, appliedDelta: -delta));
        }
      } else if (!afterDate) {
        forward.add((transaction: transaction, appliedDelta: delta));
      }
    }
    forward.sort((a, b) =>
        a.transaction.transactionDate.compareTo(b.transaction.transactionDate));
    reversed.sort((a, b) =>
        b.transaction.transactionDate.compareTo(a.transaction.transactionDate));
    return [...forward, ...reversed];
  }

  bool _foldsIntoSnapshot(FinanceTransaction transaction) {
    return transaction.type == TransactionType.transfer ||
        transaction.type == TransactionType.adjustment;
  }

  double _transactionDeltaForAccount(
      String accountId, FinanceTransaction transaction) {
    if (!transaction.affectsBalance) {
      return 0;
    }
    switch (transaction.type) {
      case TransactionType.income:
        return transaction.accountId == accountId ? transaction.amount : 0;
      case TransactionType.expense:
        return transaction.accountId == accountId ? -transaction.amount : 0;
      case TransactionType.adjustment:
        return transaction.accountId == accountId ? transaction.amount : 0;
      case TransactionType.transfer:
        if (transaction.accountId == accountId) {
          return -transaction.amount;
        }
        if (transaction.toAccountId == accountId) {
          return transaction.transferInAmount;
        }
        return 0;
    }
  }

  double _cashDeltaForAccount(
      String accountId, FinanceTransaction transaction) {
    if (!transaction.affectsBalance) {
      return 0;
    }
    switch (transaction.type) {
      case TransactionType.adjustment:
        return transaction.accountId == accountId ? transaction.amount : 0;
      case TransactionType.transfer:
        if (transaction.accountId == accountId) {
          return -transaction.amount;
        }
        if (transaction.toAccountId == accountId) {
          return transaction.transferInAmount;
        }
        return 0;
      case TransactionType.income:
      case TransactionType.expense:
        return 0;
    }
  }

  double _actualCashFlowDelta(FinanceTransaction transaction) {
    Account? accountFor(String accountId) {
      for (final account in _accounts) {
        if (account.id == accountId) return account;
      }
      return null;
    }

    final source = accountFor(transaction.accountId);
    final target = transaction.toAccountId == null
        ? null
        : accountFor(transaction.toAccountId!);
    final amount = transactionAmountInBase(transaction);
    switch (transaction.type) {
      case TransactionType.income:
        return source?.reportGroup == ReportGroup.cash ? amount : 0;
      case TransactionType.expense:
        return source?.reportGroup == ReportGroup.cash ? -amount : 0;
      case TransactionType.adjustment:
        return source?.reportGroup == ReportGroup.cash ? amount : 0;
      case TransactionType.transfer:
        var delta = 0.0;
        if (source?.reportGroup == ReportGroup.cash) delta -= amount;
        if (target?.reportGroup == ReportGroup.cash) {
          delta += transferIncomingAmountInBase(transaction);
        }
        return delta;
    }
  }

  String _accountReconciliationKey(String accountId) {
    return 'account_reconciled_month_$accountId';
  }

  String _creditCardStatementAmountsKey(String accountId) {
    return 'credit_card_statement_amounts_${accountId}_json';
  }

  String _statementDateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _traceTitleForTransaction(FinanceTransaction transaction) {
    final description = transaction.description?.trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }
    final merchant = transaction.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) {
      return merchant;
    }
    final categoryId = transaction.categoryId;
    if (categoryId != null) {
      return _categoryNameOrFallback(categoryId);
    }
    return _transactionTypeLabel(transaction.type);
  }

  String _traceSubtitleForTransaction(
    String accountId,
    FinanceTransaction transaction,
  ) {
    final parts = <String>[_transactionTypeLabel(transaction.type)];
    final categoryId = transaction.categoryId;
    if (categoryId != null) {
      parts.add(_categoryNameOrFallback(categoryId));
    }
    if (transaction.type == TransactionType.transfer &&
        transaction.toAccountId != null) {
      parts.add(
        '${_accountNameOrFallback(transaction.accountId)} -> '
        '${_accountNameOrFallback(transaction.toAccountId!)}',
      );
    } else {
      parts.add(_accountNameOrFallback(transaction.accountId));
    }
    parts.add(transaction.toAccountId == accountId ? '流入账户' : '影响账户');
    return parts.join(' · ');
  }

  String _transactionTypeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return '收入';
      case TransactionType.expense:
        return '支出';
      case TransactionType.transfer:
        return '转账';
      case TransactionType.adjustment:
        return '调整';
    }
  }

  String _categoryNameOrFallback(String categoryId) {
    for (final category in _categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }
    return '未命名类别';
  }

  String _accountNameOrFallback(String accountId) {
    for (final account in _accounts) {
      if (account.id == accountId) {
        return account.name;
      }
    }
    return '未知账户';
  }

  String _dateLabel(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _csvMoney(double value) => value == 0 ? '' : value.toStringAsFixed(2);

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  DateTime currentMonthCutoffDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
  }

  // ── AI analysis config ──────────────────────────────────────────────
  String get aiGatewayUrl => _metaValues['ai_gateway_url'] ?? '';

  Future<void> saveAiGatewayUrl(String gatewayUrl) async {
    await database.setMetaValue('ai_gateway_url', gatewayUrl);
  }
}

class ImportPreview {
  const ImportPreview({
    required this.accounts,
    required this.categories,
    required this.budgets,
    required this.transactions,
    required this.assetSnapshots,
    required this.exportedAt,
  });

  final int accounts;
  final int categories;
  final int budgets;
  final int transactions;
  final int assetSnapshots;
  final String? exportedAt;
}

class InvestmentFlowSummary {
  const InvestmentFlowSummary({
    required this.contribution,
    required this.withdrawal,
  });

  final double contribution;
  final double withdrawal;

  double get netContribution => contribution - withdrawal;
}

class AccountBalanceTrace {
  const AccountBalanceTrace({
    required this.account,
    required this.cutoffDate,
    required this.sourceLabel,
    required this.sourceAmount,
    required this.entries,
    required this.endingBalance,
  });

  final Account account;
  final DateTime cutoffDate;
  final String sourceLabel;
  final double sourceAmount;
  final List<AccountBalanceTraceEntry> entries;
  final double endingBalance;
}

class AccountBalanceTraceEntry {
  const AccountBalanceTraceEntry({
    required this.transactionId,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.delta,
    required this.runningBalance,
  });

  final String transactionId;
  final DateTime date;
  final String title;
  final String subtitle;
  final double delta;
  final double runningBalance;
}

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

class CashFlowProjectionPoint {
  const CashFlowProjectionPoint({
    required this.monthKey,
    required this.income,
    required this.expense,
    required this.transfers,
    required this.net,
    required this.endingCash,
  });

  final String monthKey;
  final double income;
  final double expense;
  final double transfers;
  final double net;
  final double endingCash;
}

class CashFlowSummary {
  const CashFlowSummary({
    required this.inflow,
    required this.outflow,
  });

  final double inflow;
  final double outflow;

  double get net => inflow - outflow;
}

class MonthlyFundingNeed {
  const MonthlyFundingNeed({
    required this.monthKey,
    required this.cashInflow,
    required this.knownCashOutflow,
    required this.creditDue,
    required this.loanDue,
    required this.coveredDebtPayments,
  });

  final String monthKey;
  final double cashInflow;
  final double knownCashOutflow;
  final double creditDue;
  final double loanDue;

  /// Portion of [totalDebtDue] already represented by a payment transaction.
  final double coveredDebtPayments;

  double get totalDebtDue => creditDue + loanDue;

  double get uncoveredDebtDue => (totalDebtDue - coveredDebtPayments)
      .clamp(0.0, double.infinity)
      .toDouble();

  /// Cash outflow already recorded for the month plus debt due without a
  /// matching payment transaction. Repayments already in cash outflow are not
  /// added for a second time.
  double get totalCashRequired => knownCashOutflow + uncoveredDebtDue;

  double get projectedNetAfterFunding => cashInflow - totalCashRequired;
}

class _CreditDueSnapshot {
  const _CreditDueSnapshot({required this.amount, required this.asOf});

  final double amount;
  final DateTime asOf;
}

class CreditCardPaymentReminder {
  const CreditCardPaymentReminder({
    required this.account,
    required this.amountDue,
    required this.dueDate,
  });

  final Account account;
  final double amountDue;
  final DateTime dueDate;
}

class AssetGoalHistoryPoint {
  const AssetGoalHistoryPoint({
    required this.date,
    required this.label,
    required this.totalAssets,
  });

  final DateTime date;
  final String label;
  final double totalAssets;
}

class AssetGoal {
  const AssetGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.reachedAt,
  });

  final String id;
  final String name;
  final double targetAmount;
  final DateTime? reachedAt;

  AssetGoal copyWith({
    String? id,
    String? name,
    double? targetAmount,
    DateTime? reachedAt,
    bool clearReachedAt = false,
  }) {
    return AssetGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      reachedAt: clearReachedAt ? null : (reachedAt ?? this.reachedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target_amount': targetAmount,
        'reached_at': reachedAt?.toIso8601String(),
      };

  factory AssetGoal.fromJson(Map<String, dynamic> json) {
    return AssetGoal(
      id: json['id'] as String,
      name: json['name'] as String? ?? '资产目标',
      targetAmount: (json['target_amount'] as num).toDouble(),
      reachedAt: json['reached_at'] == null
          ? null
          : DateTime.tryParse(json['reached_at'] as String),
    );
  }
}

class AssetGoalProgressSummary {
  const AssetGoalProgressSummary({
    required this.goal,
    required this.currentAssets,
    required this.reachedAt,
    required this.history,
  });

  final AssetGoal goal;
  final double currentAssets;
  final DateTime? reachedAt;
  final List<AssetGoalHistoryPoint> history;

  double get progressRatio {
    if (goal.targetAmount <= 0) {
      return 0;
    }
    return currentAssets / goal.targetAmount;
  }

  bool get isReached {
    return goal.targetAmount > 0 && currentAssets >= goal.targetAmount;
  }
}
