import 'dart:convert';
import 'dart:typed_data';

import '../app_version.dart';
import '../database/app_database.dart'
    hide Account, AssetSnapshot, Budget, Category;
import '../models/account.dart';
import '../models/account_valuation.dart';
import '../models/asset_goal.dart';
import '../models/asset_snapshot.dart';
import '../models/budget.dart';
import '../models/budget_ledger.dart';
import '../models/category.dart';
import '../models/category_hierarchy.dart';
import '../models/credit_card_billing.dart';
import '../models/forecast_summary.dart';
import '../models/loan_amortization.dart';
import '../models/loan_settlement.dart';
import '../models/monthly_summary.dart';
import '../models/transaction.dart';
import '../models/transaction_preset.dart';
import '../platform/local_file_io.dart' as local_files;
import '../utils/currency_formatter.dart';
import '../utils/id_generator.dart';
import '../utils/month_key.dart';
import '../utils/month_range.dart' show recentMonthKeys;
import '../utils/anchored_month.dart';
import 'sample_data.dart';
import 'category_reporting.dart';

export '../models/account_valuation.dart'
    show InvestmentFlowSummary, InvestmentValuation;
export '../models/asset_goal.dart';
export '../models/transaction_preset.dart';

part 'funding_projection.dart';

class LedgerBalanceSheet {
  const LedgerBalanceSheet._(this._assets, this._overdrafts, this.cardDebt,
      this.loanDebt, this.cardCredit, this.loanCredit);

  final Map<ReportGroup, double> _assets, _overdrafts;
  final double cardDebt, loanDebt, cardCredit, loanCredit;

  double assetsIn(ReportGroup group) => _assets[group] ?? 0;
  double netIn(ReportGroup group) =>
      assetsIn(group) - (_overdrafts[group] ?? 0);
  double get overdrafts =>
      _overdrafts.values.fold(0.0, (sum, amount) => sum + amount);
  double get nonCreditAssets =>
      _assets.values.fold(0.0, (sum, amount) => sum + amount);
  double get nonCreditNet => nonCreditAssets - overdrafts;
  double get assets => nonCreditAssets + cardCredit + loanCredit;
  double get liabilities => overdrafts + cardDebt + loanDebt;
  double get netWorth => assets - liabilities;
}

class FinanceRepository with InvestmentValuationQueries, BudgetQueries {
  @override
  late final budgetLedger = BudgetLedger(
      budgets: _budgets,
      transactions: _transactions,
      hierarchy: categoryHierarchy,
      tryConvertToBase: (amount, currency) => tryConvertAmount(
          amount: amount, fromCurrency: currency, toCurrency: baseCurrency));

  AccountValuationBook? _valuations;
  @override
  AccountValuationBook get valuationBook => _valuations ??=
      AccountValuationBook(_accounts, _transactions, _snapshots);

  static const uncategorizedCashOutflowKey = '__cash_outflow_uncategorized__';
  static const _exchangeRatesMetaKey = 'exchange_rates_to_base_json';
  static const _currencyPriorityMetaKey = 'currency_priority_json';

  /// Read model over an already captured ledger revision (e.g. a service
  /// adapter). Production reads use [load] to capture all tables together.
  factory FinanceRepository.fromSnapshot({
    required AppDatabase database,
    List<Account> accounts = const [],
    List<Category> categories = const [],
    List<Budget> budgets = const [],
    List<FinanceTransaction> transactions = const [],
    List<AssetSnapshot> snapshots = const [],
    List<TransactionTemplate> transactionTemplates = const [],
    List<RecurringTransactionRule> recurringTransactionRules = const [],
    Map<String, String> metaValues = const {},
  }) =>
      FinanceRepository._(
        database: database,
        accounts: List.unmodifiable(accounts),
        categories: List.unmodifiable(categories),
        budgets: List.unmodifiable(budgets),
        transactions: List.unmodifiable(transactions),
        snapshots: List.unmodifiable(snapshots),
        transactionTemplates: List.unmodifiable(transactionTemplates),
        recurringTransactionRules: List.unmodifiable(recurringTransactionRules),
        metaValues: Map.unmodifiable(metaValues),
      );

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
    final snapshot = await database.transaction(() async {
      final accounts = await database.fetchAccounts();
      final categories = await database.fetchCategories();
      final budgets = await database.fetchBudgets();
      final transactions = await database.fetchTransactions();
      final snapshots = await database.fetchAssetSnapshots();
      final storedTemplates = await database.fetchTransactionTemplates();
      final storedRules = await database.fetchRecurringTransactionRules();
      final metaValues = await database.fetchAllMetaValues();
      return (
        accounts: accounts,
        categories: categories,
        budgets: budgets,
        transactions: transactions,
        snapshots: snapshots,
        storedTemplates: storedTemplates,
        storedRules: storedRules,
        metaValues: metaValues,
      );
    });
    final repository = FinanceRepository._(
      database: database,
      accounts: snapshot.accounts,
      categories: snapshot.categories,
      budgets: snapshot.budgets,
      transactions: snapshot.transactions,
      snapshots: snapshot.snapshots,
      transactionTemplates: snapshot.storedTemplates,
      recurringTransactionRules: snapshot.storedRules,
      metaValues: snapshot.metaValues,
    );
    setActiveBaseCurrency(repository.baseCurrency);
    return repository;
  }

  Future<FinanceRepository> refresh() => FinanceRepository.load(database);

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Category> get categories => List.unmodifiable(_categories);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<FinanceTransaction> get transactions => List.unmodifiable(_transactions);
  List<AssetSnapshot> get snapshots => List.unmodifiable(_snapshots);
  Map<String, String> get metaValues => Map.unmodifiable(_metaValues);

  late final _storedOrder =
      storedCurrencyOrder(_metaValues[_currencyPriorityMetaKey]);
  String get baseCurrency => _storedOrder.first;

  late final Map<String, double> exchangeRatesToBase =
      readCurrencyQuotes(_metaValues[_exchangeRatesMetaKey], baseCurrency);

  late final Set<String> _ledgerCurrencies = Set.unmodifiable({
    for (final a in _accounts) normalizeCurrency(a.currency),
    for (final b in _budgets) normalizeCurrency(b.currency),
    for (final g in assetGoals) normalizeCurrency(g.currency),
    for (final row in <LoanInstallmentFields>[
      ..._transactions,
      ..._transactionTemplates,
      ..._recurringTransactionRules,
    ]) ...{
      normalizeCurrency(row.currency),
      if (row.type == TransactionType.transfer && row.toCurrency != null)
        normalizeCurrency(row.toCurrency!),
    },
  });

  late final List<String> currencyPriority = List.unmodifiable({
    ..._storedOrder,
    ..._ledgerCurrencies.where((code) => code.isNotEmpty),
    ...exchangeRatesToBase.keys,
  });

  bool hasExchangeRate(String currency) =>
      exchangeRatesToBase.containsKey(normalizeCurrency(currency));

  late final Set<String> unpricedCurrencies = Set.unmodifiable(
      _ledgerCurrencies.where((code) => !hasExchangeRate(code)));

  double? tryConvertAmount(
          {required double amount,
          required String fromCurrency,
          required String toCurrency}) =>
      tryConvertCurrencyAmount(
          amount: amount,
          fromCurrency: fromCurrency,
          toCurrency: toCurrency,
          ratesToBase: exchangeRatesToBase,
          baseCurrency: baseCurrency);

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

  /// Contribution to a base-currency aggregate. [unpricedCurrencies] lists
  /// currencies omitted from those totals. Individual estimates use [tryConvertAmount].
  double convertToBase(double amount, String currency) =>
      tryConvertAmount(
          amount: amount, fromCurrency: currency, toCurrency: baseCurrency) ??
      0;

  double transactionAmountInBase(FinanceTransaction transaction) {
    return convertToBase(transaction.amount, transaction.currency);
  }

  double transferIncomingAmountInBase(FinanceTransaction transaction) {
    return convertToBase(
      valuationBook.incomingFor(transaction),
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
    final ordered = normalizedCurrencyOrder(currencyPriority);
    final normalized = Map.of(normalizedExchangeRatesToBase(
      ratesToBase,
      baseCurrency: ordered.first,
    ));
    // Older callers submit only the built-in rates. Keep any previously
    // quoted historical codes in the same economic units when rebasing.
    final bridge = normalized[baseCurrency] ??
        (exchangeRatesToBase[ordered.first] == null
            ? null
            : 1 / exchangeRatesToBase[ordered.first]!);
    if (bridge != null) {
      for (final entry in exchangeRatesToBase.entries) {
        if (supportedCurrencies.contains(entry.key) ||
            normalized.containsKey(entry.key)) {
          continue;
        }
        final rebased = entry.value * bridge;
        if (rebased.isFinite && rebased > 0) normalized[entry.key] = rebased;
      }
    }
    return database.transaction(() async {
      // Bind currency-less goals from older backups to the pre-switch base.
      final goals = assetGoals;
      if (ordered.first != baseCurrency && goals.isNotEmpty) {
        await _saveAssetGoals(goals);
      }
      await database.setMetaValue(
          _exchangeRatesMetaKey, jsonEncode(normalized));
      await database.setMetaValue(
          _currencyPriorityMetaKey, jsonEncode(ordered));
      return _refreshWithGoalSync();
    });
  }

  List<TransactionTemplate> get transactionTemplates {
    return List.unmodifiable(_transactionTemplates);
  }

  List<RecurringTransactionRule> get recurringTransactionRules {
    return List.unmodifiable(_recurringTransactionRules);
  }

  List<AssetGoal> get assetGoals =>
      AssetGoal.readMetadata(_metaValues, baseCurrency);

  double totalAssetsByGroup(ReportGroup group) {
    return displayTotalAssetsByGroup(group);
  }

  double displayTotalAssetsByGroup(
    ReportGroup group, {
    DateTime? cutoffDate,
    bool positiveOnly = false,
  }) {
    final targetDate = cutoffDate ?? currentMonthCutoffDate();
    return _accounts
        .where((account) => account.effectiveReportGroup == group)
        .fold(
      0.0,
      (sum, account) {
        final balance = convertToBase(
            _accountBalanceAt(account, targetDate), account.currency);
        return sum + (positiveOnly && balance < 0 ? 0 : balance);
      },
    );
  }

  double totalAssets({bool includeCredit = true}) {
    return displayTotalAssets(includeCredit: includeCredit);
  }

  double displayTotalAssets({bool includeCredit = true, DateTime? cutoffDate}) {
    return totalAssetsAt(cutoffDate ?? currentMonthCutoffDate(),
        includeCredit: includeCredit);
  }

  double totalTargetAssets() {
    return displayTotalAssets(includeCredit: false);
  }

  // Chart months include all ledger activity, even planned or credit-only
  // entries. Only the valuation at each displayed cutoff excludes those.
  late final List<DateTime> _activityMonths = {
    for (final tx in _transactions)
      DateTime(tx.transactionDate.year, tx.transactionDate.month),
    for (final snapshot in _snapshots)
      DateTime(snapshot.snapshotDate.year, snapshot.snapshotDate.month),
  }.toList()
    ..sort();

  List<AssetGoalHistoryPoint> totalAssetHistory({
    DateTime? cutoffDate,
    bool includeCredit = true,
  }) {
    final cutoff = cutoffDate ?? currentMonthCutoffDate();
    final endMonth = DateTime(cutoff.year, cutoff.month);
    AssetGoalHistoryPoint point(DateTime at) => AssetGoalHistoryPoint(
        date: at,
        label: monthKeyFromDate(at),
        totalAssets: totalAssetsAt(at, includeCredit: includeCredit));
    return [
      for (final month
          in _activityMonths.takeWhile((m) => m.isBefore(endMonth)))
        point(DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999)),
      point(cutoff),
    ];
  }

  /// Cutoff for asset-goal figures: [requested] (default: now), but never
  /// later than the end of today, so future-dated actual transactions and
  /// snapshots are not counted as assets already held.
  DateTime assetGoalCutoffDate([DateTime? requested]) {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    if (requested == null || requested.isAfter(endOfToday)) {
      return endOfToday;
    }
    return requested;
  }

  AssetGoalTimeline? _timeline;
  AssetGoalTimeline get _goalTimeline =>
      _timeline ??= valuationBook.goalTimeline(convertToBase);

  /// Inclusive asset progress at the requested cutoff, capped at today's end.
  List<AssetGoalProgressSummary> assetGoalSummaries({DateTime? cutoffDate}) {
    final goals = assetGoals;
    if (goals.isEmpty) return const [];
    final cutoff = assetGoalCutoffDate(cutoffDate);
    return _summariesForGoals(goals, cutoff,
        history: totalAssetHistory(cutoffDate: cutoff, includeCredit: false));
  }

  List<AssetGoalProgressSummary> _summariesForGoals(
      List<AssetGoal> goals, DateTime cutoff,
      {List<AssetGoalHistoryPoint> history = const []}) {
    return summarizeAssetGoals(
      goals: goals,
      assetsPriced: _accounts
          .where((a) => a.effectiveReportGroup != ReportGroup.credit)
          .every((a) => hasExchangeRate(a.currency)),
      hasExchangeRate: hasExchangeRate,
      cutoff: cutoff,
      timeline: _goalTimeline,
      convertToBase: convertToBase,
      history: history,
    );
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

  late final categoryHierarchy = CategoryHierarchy(_categories);

  late final _accountNames = {
    for (final account in _accounts) account.id: account.name
  };

  String categoryName(String categoryId) =>
      categoryHierarchy.byId[categoryId]?.name ?? '已删除类别';

  String accountName(String accountId) => _accountNames[accountId] ?? '已删除账户';

  List<Category> categoriesByType(CategoryType type) {
    return _categories.where((item) => item.type == type).toList();
  }

  List<Category> sortedCategories() => categoryHierarchy.ordered;

  List<Category> categoryOptions(CategoryType type,
          {String? originalCategoryId}) =>
      _categoryOptions({type}, originalCategoryId);

  List<Category> transactionCategoryOptions(TransactionType type,
          {String? originalCategoryId}) =>
      _categoryOptions(allowedCategoryTypes(type), originalCategoryId);

  List<Category> _categoryOptions(
          Set<CategoryType> types, String? originalCategoryId) =>
      categoryHierarchy.ordered
          .where((item) =>
              types.contains(item.type) &&
              (!item.isArchived || item.id == originalCategoryId))
          .toList();

  /// Historical editors can retain the original account for each transaction leg.
  List<Account> entryAccounts({String? originalAccountId}) =>
      _accounts.where((a) => a.isActive || a.id == originalAccountId).toList();

  List<Account> repaymentSources(String debtId) {
    final debt = _accounts.where((a) => a.id == debtId).firstOrNull;
    if (debt == null ||
        !debt.isActive ||
        (debt.accountType != AccountType.creditCard &&
            debt.accountType != AccountType.loan)) {
      return [];
    }
    return entryAccounts()
        .where((source) =>
            source.id != debtId &&
            source.effectiveReportGroup == ReportGroup.cash &&
            normalizeCurrency(source.currency) ==
                normalizeCurrency(debt.currency))
        .toList();
  }

  List<Account> accountsByGroup(ReportGroup group) {
    return _accounts
        .where((item) => item.effectiveReportGroup == group)
        .toList();
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

  /// Debt shown as a card's "当前欠款" and counted in credit liabilities.
  ///
  /// Live views omit [cutoffDate] and receive the committed balance. Historical
  /// views pass their cutoff and receive the balance at that moment. A positive
  /// (overpaid) card balance is a credit, not debt, so the result is never
  /// negative.
  double creditCardOutstandingBalance(String accountId,
      {DateTime? cutoffDate}) {
    if (cutoffDate == null) {
      return creditCardCommittedOutstandingBalance(accountId);
    }
    final account = _accounts.firstWhere((item) => item.id == accountId);
    if (account.accountType != AccountType.creditCard) {
      throw ArgumentError.value(accountId, 'accountId', 'Not a credit card');
    }
    return (-accountBalanceAt(accountId, cutoffDate))
        .clamp(0, double.infinity)
        .toDouble();
  }

  /// Credit and loan liabilities in base currency, calculated per account.
  ({double credit, double loans}) accountLiabilities({DateTime? cutoffDate}) {
    final sheet = balanceSheetAt(cutoffDate ?? currentMonthCutoffDate());
    return (credit: sheet.cardDebt, loans: sheet.loanDebt);
  }

  /// Overpaid (positive) card balance, the counterpart of
  /// [creditCardOutstandingBalance].
  ///
  /// It is not debt, cash or a goal asset, but it is still the user's money,
  /// so net assets add it back after credit liabilities are clamped to zero.
  /// Live views omit [cutoffDate] and read [Account.currentBalance];
  /// historical views read the balance at the cutoff.
  double creditCardCreditBalance(String accountId, {DateTime? cutoffDate}) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    if (account.accountType != AccountType.creditCard) {
      throw ArgumentError.value(accountId, 'accountId', 'Not a credit card');
    }
    final balance = cutoffDate == null
        ? account.currentBalance
        : accountBalanceAt(accountId, cutoffDate);
    return balance.clamp(0, double.infinity).toDouble();
  }

  double totalCreditCardCredit({DateTime? cutoffDate}) {
    return _accounts
        .where((account) => account.accountType == AccountType.creditCard)
        .fold<double>(
          0,
          (sum, account) =>
              sum +
              convertToBase(
                creditCardCreditBalance(account.id, cutoffDate: cutoffDate),
                account.currency,
              ),
        );
  }

  /// Billing summary shared by the account list and the card detail page.
  ///
  /// Live views omit [cutoffDate]: the whole ledger is used so committed
  /// next-cycle records count, and the balance is read at the end of the
  /// reference day because billing buckets compare whole dates. Historical
  /// views pass their cutoff: records after it are ignored and the balance is
  /// read at exactly the same moment, so a later record on the cutoff day
  /// cannot leak into the historical debt.
  CreditCardBillingSummary creditCardBillingSummary(
    String accountId, {
    DateTime? cutoffDate,
    DateTime? now,
  }) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    final reference = cutoffDate ?? now ?? DateTime.now();
    return calculateCreditCardBilling(
      account: account,
      transactions: cutoffDate == null
          ? _transactions
          : _transactions
              .where((item) => !item.transactionDate.isAfter(cutoffDate)),
      now: reference,
      balanceAtCutoff: accountBalanceAt(
        accountId,
        cutoffDate ??
            DateTime(
              reference.year,
              reference.month,
              reference.day,
              23,
              59,
              59,
              999,
            ),
      ),
    );
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
      String accountId, DateTime cutoffDate) {
    final account = _accounts.firstWhere((item) => item.id == accountId);
    final projection = valuationBook.projection(accountId, cutoffDate);
    var balance = projection.sourceAmount;
    final entries = <AccountBalanceTraceEntry>[];
    for (final movement in projection.movements) {
      final transaction = movement.transaction;
      balance += movement.delta;
      entries.add(AccountBalanceTraceEntry(
        transactionId: transaction.id,
        date: transaction.transactionDate,
        title: _traceTitleForTransaction(transaction),
        subtitle: _traceSubtitleForTransaction(accountId, transaction),
        delta: movement.delta,
        runningBalance: balance,
      ));
    }
    return AccountBalanceTrace(
      account: account,
      cutoffDate: cutoffDate,
      sourceLabel: projection.sourceLabel,
      sourceAmount: projection.sourceAmount,
      entries: entries,
      endingBalance: balance,
    );
  }

  List<Account> investmentAccounts() {
    return _accounts
        .where(
          (item) =>
              item.effectiveReportGroup == ReportGroup.investment ||
              item.effectiveReportGroup == ReportGroup.retirement,
        )
        .toList();
  }

  double totalAssetsAt(DateTime date, {bool includeCredit = true}) {
    return includeCredit
        ? balanceSheetAt(date).netWorth
        : _goalTimeline.valueAt(date);
  }

  /// Values all accounts at the same instant and in the ledger's base currency.
  LedgerBalanceSheet balanceSheetAt(DateTime cutoff) {
    final assets = <ReportGroup, double>{};
    final overdrafts = <ReportGroup, double>{};
    var cardDebt = 0.0, loanDebt = 0.0, cardCredit = 0.0, loanCredit = 0.0;
    for (final account in _accounts) {
      final balance =
          convertToBase(_accountBalanceAt(account, cutoff), account.currency);
      if (account.accountType == AccountType.creditCard) {
        if (balance < 0) {
          cardDebt -= balance;
        } else {
          cardCredit += balance;
        }
      } else if (account.accountType == AccountType.loan) {
        if (balance < 0) {
          loanDebt -= balance;
        } else {
          loanCredit += balance;
        }
      } else {
        final group = account.effectiveReportGroup;
        if (balance < 0) {
          overdrafts[group] = (overdrafts[group] ?? 0) - balance;
        } else {
          assets[group] = (assets[group] ?? 0) + balance;
        }
      }
    }
    return LedgerBalanceSheet._(
        assets, overdrafts, cardDebt, loanDebt, cardCredit, loanCredit);
  }

  List<FinanceTransaction> recentTransactions({int limit = 5}) {
    final items = [..._transactions]
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return items.take(limit).toList();
  }

  Iterable<FinanceTransaction> _upcomingExpenses(DateTime asOf) {
    final tomorrow = DateTime(asOf.year, asOf.month, asOf.day + 1);
    return _transactions.where((item) =>
        item.type == TransactionType.expense &&
        !item.transactionDate.isBefore(tomorrow));
  }

  List<FinanceTransaction> upcomingExpenseTransactions({
    int limit = 8,
    DateTime? asOf,
  }) {
    final items = _upcomingExpenses(asOf ?? DateTime.now()).toList()
      ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    return items.take(limit).toList();
  }

  double totalFutureExpense({int monthsAhead = 3, DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final endExclusive = DateTime(now.year, now.month + monthsAhead);
    return _upcomingExpenses(now)
        .where((item) => item.transactionDate.isBefore(endExclusive))
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

  /// From the end-of-day cash balance, add future actual and planned cash
  /// movements. Transfers are signed net cash movements in their own column.
  List<CashFlowProjectionPoint> futureCashFlowProjection({
    int months = 6,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    RangeError.checkNotNegative(months, 'months');
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final endExclusive = DateTime(now.year, now.month + months);
    var runningCash = displayTotalAssetsByGroup(
      ReportGroup.cash,
      cutoffDate: tomorrow.subtract(const Duration(microseconds: 1)),
    );
    final incomes = List.filled(months, 0.0);
    final expenses = List.filled(months, 0.0);
    final transfersByMonth = List.filled(months, 0.0);
    for (final transaction in _transactions) {
      final date = transaction.transactionDate;
      if (date.isBefore(tomorrow) || !date.isBefore(endExclusive)) continue;
      final index = (date.year - now.year) * 12 + date.month - now.month;
      final delta = _actualCashFlowDelta(transaction);
      if (transaction.type == TransactionType.transfer) {
        transfersByMonth[index] += delta;
      } else if (delta > 0) {
        incomes[index] += delta;
      } else {
        expenses[index] -= delta;
      }
    }
    return List.generate(months, (index) {
      final monthKey = _monthKey(DateTime(now.year, now.month + index));
      final income = incomes[index];
      final expense = expenses[index];
      final transfers = transfersByMonth[index];
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
    DateTime? cutoffDate,
    String? accountId,
    TransactionType? type,
    String? categoryId,
  }) {
    final allowedMonths = monthKeys.toSet();
    var inflow = 0.0;
    var outflow = 0.0;
    for (final transaction in _transactions) {
      if (!allowedMonths.contains(_monthKey(transaction.transactionDate)) ||
          (cutoffDate != null &&
              transaction.transactionDate.isAfter(cutoffDate)) ||
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
    DateTime? cutoffDate,
    String? accountId,
    TransactionType? type,
    String? categoryId,
  }) {
    return actualCashFlowSummaryForMonths(
      [monthKey],
      includePlanned: includePlanned,
      cutoffDate: cutoffDate,
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
    DateTime? asOf,
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

    final today = _fundingDay(asOf ?? DateTime.now());
    final dayBeforeMonth = DateTime(year, month, 0);
    final origin = today.isBefore(dayBeforeMonth) ? today : dayBeforeMonth;
    final firstPlanDay = today.isBefore(monthStart)
        ? DateTime(today.year, today.month, today.day + 1)
        : monthStart;
    final cardFunding = _cardFundingWindow(
      start: monthStart,
      openingAsOf: origin,
      firstPlanDay: firstPlanDay,
      includeOverdue: false,
      includePlanned: includePlanned,
    ).timeline(monthEnd)(monthEnd);
    // Keep prior actual settlements in both ledgers. Within this month only
    // actual non-cash settlements can reduce debt without covering a cash
    // outflow; planned non-cash transfers never stand in for available cash.
    final afterCash = _transactions.where((t) =>
        t.affectsBalance ||
        (includePlanned &&
            !t.transactionDate.isBefore(firstPlanDay) &&
            _cashAccountIds.contains(t.accountId)));
    final beforeCash = afterCash.where((t) =>
        t.transactionDate.isBefore(monthStart) ||
        !_cashAccountIds.contains(t.accountId));
    var loanDue = 0.0;
    var loanUncovered = 0.0;
    for (final loan in _accounts.where((a) =>
        a.isActive &&
        a.accountType == AccountType.loan &&
        a.hasCompleteLoanProfile)) {
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
      final before = LoanSettlement.forLoan(
          loanId: loan.id,
          currency: loan.currency,
          transactions: beforeCash,
          cutoff: monthEnd,
          includePlanned: includePlanned);
      final after = LoanSettlement.forLoan(
          loanId: loan.id,
          currency: loan.currency,
          transactions: afterCash,
          cutoff: monthEnd,
          includePlanned: includePlanned);
      for (final installment in schedule.installments
          .where((i) => i.dueDate.year == year && i.dueDate.month == month)) {
        final gross = before.remaining(installment).payment;
        final remaining = after.remaining(installment).payment;
        loanDue +=
            convertToBase(gross < remaining ? remaining : gross, loan.currency);
        loanUncovered += convertToBase(remaining, loan.currency);
      }
    }
    return MonthlyFundingNeed(
      monthKey: monthKey,
      cashInflow: cashFlow.inflow,
      knownCashOutflow: cashFlow.outflow,
      creditDue: cardFunding.due,
      loanDue: loanDue,
      coveredDebtPayments:
          (cardFunding.due - cardFunding.uncovered) + (loanDue - loanUncovered),
    );
  }

  _CardFundingWindow _cardFundingWindow(
          {required DateTime start,
          required DateTime openingAsOf,
          required DateTime firstPlanDay,
          required bool includeOverdue,
          required bool includePlanned}) =>
      _CardFundingWindow(
          start: start,
          openingAsOf: openingAsOf,
          firstPlanDay: firstPlanDay,
          includeOverdue: includeOverdue,
          includePlanned: includePlanned,
          accounts: _accounts,
          transactions: _transactions,
          balanceAt: accountBalanceAt,
          convertToBase: convertToBase);

  CashFundingForecast cashForecast(
      {required DateTime asOf, required DateTime endInclusive}) {
    final today = _fundingDay(asOf);
    final end = _fundingDay(endInclusive);
    if (end.isBefore(today)) {
      throw ArgumentError.value(endInclusive, 'endInclusive');
    }
    final start = DateTime(today.year, today.month, today.day + 1);
    final opening = displayTotalAssetsByGroup(ReportGroup.cash,
        cutoffDate: _fundingDayEnd(today));
    final creditTimeline = _cardFundingWindow(
            start: start,
            openingAsOf: today,
            firstPlanDay: start,
            includeOverdue: true,
            includePlanned: true)
        .timeline(end);
    return CashFundingForecast._(opening, today, end, (day) {
      final funding = creditTimeline(day);
      final known =
          cashFlowNetBetween(startInclusive: start, endInclusive: day);
      return (
        balance: opening + known - funding.uncovered,
        cardFunding: funding
      );
    });
  }

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

  List<CreditCardPaymentReminder> creditCardPaymentReminders(
          {DateTime? asOf}) =>
      buildCreditCardPaymentReminders(
          accounts: _accounts,
          transactions: _transactions,
          asOf: asOf ?? DateTime.now(),
          balanceAt: accountBalanceAt,
          convertToBase: convertToBase);

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
    final monthKeys = recentMonthKeys(count: months);
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

  late final categoryReports = CategoryReportIndex(
    categoryHierarchy,
    _transactions,
    hasRate: hasExchangeRate,
    convertToBase: convertToBase,
  );

  /// Each ID includes its descendants. Sum peer roots for a disjoint total.
  Map<String, double> categoryTotalsForMonths({
    required CategoryType type,
    required List<String> monthKeys,
  }) =>
      categoryReports.read(type, monthKeys).actualSubtotals;

  /// Extrapolate the most recent active, completed calendar months within
  /// the past year. A partial current month is never used as a monthly sample.
  ForecastSummary forecastSummary({int months = 3, DateTime? asOf}) {
    RangeError.checkNotNegative(months, 'months');
    final now = asOf ?? DateTime.now();
    final historicalMonths = recentMonthKeys(
      count: 12,
      anchor: DateTime(now.year, now.month - 1),
    );
    final sample = historicalMonths.reversed
        .map((key) => actualCashFlowSummaryForMonth(key))
        .where((flow) => flow.inflow != 0 || flow.outflow != 0)
        .take(months)
        .toList();
    final averageIncome = sample.isEmpty
        ? 0.0
        : sample.fold<double>(0, (sum, flow) => sum + flow.inflow) /
            sample.length;
    final averageExpense = sample.isEmpty
        ? 0.0
        : sample.fold<double>(0, (sum, flow) => sum + flow.outflow) /
            sample.length;
    final averageSavings = averageIncome - averageExpense;
    final dayEnd = DateTime(now.year, now.month, now.day + 1)
        .subtract(const Duration(microseconds: 1));
    final baseline = totalAssetsAt(dayEnd);
    return ForecastSummary(
      averageMonthlyIncome: averageIncome,
      averageMonthlyExpense: averageExpense,
      averageMonthlySavings: averageSavings,
      projectedSavingsInThreeMonths: baseline + averageSavings * 3,
      projectedSavingsInSixMonths: baseline + averageSavings * 6,
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

  Future<FinanceRepository> updateExistingAccount(Account account,
      {bool preserveActivity = false}) async {
    await database.updateAccount(account, preserveActivity: preserveActivity);
    return _refreshWithGoalSync();
  }

  Future<FinanceRepository> setAccountActive(
      String accountId, bool active) async {
    await database.setAccountActive(accountId, active);
    return refresh();
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
    return _refreshWithGoalSync();
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
    String? currency,
  }) =>
      _changeGoals((ledger) => [
            ...ledger.assetGoals,
            AssetGoal(
                id: buildId('goal'),
                name: name,
                targetAmount: amount,
                currency: currency ?? ledger.baseCurrency),
          ]);

  Future<FinanceRepository> updateAssetGoal(AssetGoal goal) =>
      _changeGoals((ledger) => [
            for (final item in ledger.assetGoals)
              item.id == goal.id ? goal : item,
          ]);

  Future<FinanceRepository> deleteAssetGoal(String goalId) =>
      _changeGoals((ledger) => [
            for (final item in ledger.assetGoals)
              if (item.id != goalId) item,
          ]);

  Future<FinanceRepository> addTransactionTemplate({
    required String name,
    required FinanceTransaction transaction,
    PresetCategoryChoice? categoryChoice,
    bool fromStoredTransaction = false,
  }) =>
      database.transaction(() async {
        final ledger = await refresh();
        final source = fromStoredTransaction
            ? ledger._transactions
                .where((row) => row.id == transaction.id)
                .firstOrNull
            : transaction;
        if (source == null) throw const FormatException('原交易已删除，请重新选择。');
        final template = TransactionTemplate.fromTransaction(
          id: buildId('tpl'),
          name: name,
          transaction: source,
          categoryChoice: categoryChoice,
        );
        await ledger._saveTransactionTemplates([
          ...ledger.transactionTemplates.where((item) => item.name != name),
          template,
        ]);
        return refresh();
      });

  void _checkPresetRevision(
      Map<String, dynamic>? expected, Map<String, dynamic>? current) {
    if (expected != null &&
        (current == null || jsonEncode(expected) != jsonEncode(current))) {
      throw const FormatException('此记录已更新或删除，请核对当前草稿。');
    }
  }

  Future<FinanceRepository> deleteTransactionTemplate(String templateId,
          {TransactionTemplate? expected}) =>
      database.transaction(() async {
        final rows = await database.fetchTransactionTemplates();
        _checkPresetRevision(expected?.toJson(),
            rows.where((t) => t.id == templateId).firstOrNull?.toJson());
        await _saveTransactionTemplates(
            rows.where((t) => t.id != templateId).toList());
        return refresh();
      });

  Future<FinanceRepository> saveTransactionTemplate(
          TransactionTemplate template,
          {TransactionTemplate? expected}) =>
      database.transaction(() async {
        final rows = await database.fetchTransactionTemplates();
        _checkPresetRevision(expected?.toJson(),
            rows.where((t) => t.id == template.id).firstOrNull?.toJson());
        await _saveTransactionTemplates(
            [...rows.where((t) => t.id != template.id), template]);
        return refresh();
      });

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
        loanInstallmentNumber: template.loanInstallmentNumber,
        loanPaymentAmount: template.loanPaymentAmount,
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

  static const _retiredRulePrefix = 'retired-recurring-rule/';

  // Deleting a rule retains its ledger rows. Keep only the identity and used
  // months so recreating that name cannot repeat old or user-deleted entries.
  static ({String id, List<String> months}) _readRetiredRule(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        value['months'] is! List ||
        (value['months'] as List).any((k) => !isRecurringMonthKey(k))) {
      throw const FormatException('周期规则的生成历史无效。');
    }
    return (
      id: value['id'] as String,
      months: List<String>.from(value['months'] as List)
    );
  }

  Future<FinanceRepository> addRecurringTransactionRule({
    required String name,
    required FinanceTransaction transaction,
    int intervalMonths = 1,
    PresetCategoryChoice? categoryChoice,
    bool fromStoredTransaction = false,
  }) =>
      database.transaction(() async {
        final ledger = await refresh();
        final seed = ledger._transactions
            .where((t) => t.id == transaction.id)
            .firstOrNull;
        if (seed == null && fromStoredTransaction) {
          throw const FormatException('原交易已删除，请重新选择。');
        }
        final rules = ledger.recurringTransactionRules;
        final label = name.trim();
        final named = rules.where((r) => r.name.trim() == label).toList();
        final linked =
            rules.where((r) => seed?.recurringRuleId == r.id).firstOrNull;
        if (linked != null && linked.name.trim() != label) {
          throw FormatException('这笔交易已属于周期规则「${linked.name}」，请从规则中心修改原规则。');
        }
        if (named.length > 1) {
          throw const FormatException('存在同名周期规则，请先核对规则名称。');
        }
        final existing = linked ?? named.firstOrNull;
        final historyKey = '$_retiredRulePrefix$label';
        final rawHistory = ledger._metaValues[historyKey];
        final retired = existing == null && rawHistory != null
            ? _readRetiredRule(rawHistory)
            : null;
        if (retired != null && rules.any((r) => r.id == retired.id)) {
          throw const FormatException('同名规则的历史归属有冲突，请先核对规则。');
        }
        final rule = RecurringTransactionRule.fromTransaction(
          id: existing?.id ?? retired?.id ?? buildId('rule'),
          name: label,
          transaction: seed ?? transaction,
          categoryChoice: categoryChoice,
          intervalMonths: intervalMonths,
        );
        return ledger._writeRecurringRule(rule, monthsAhead: 3, seed: seed);
      });

  String _nominalMonth(FinanceTransaction tx, String ruleId) =>
      nominalOccurrenceMonth(ruleId, tx.id, tx.transactionDate,
          _metaValues[occurrenceKey(ruleId, tx.id)]);

  Set<String> _knownRuleMonths(String ruleId) {
    final prefix = occurrenceKeyPrefix(ruleId);
    return {
      for (final entry in _metaValues.entries)
        if (entry.key.startsWith(prefix)) entry.value,
      for (final tx in _transactions)
        if (tx.recurringRuleId == ruleId) _nominalMonth(tx, ruleId),
    };
  }

  Future<FinanceRepository> deleteRecurringTransactionRule(String ruleId,
          {RecurringTransactionRule? expected}) =>
      database.transaction(() async {
        final ledger = await refresh();
        final rule = ledger.recurringTransactionRules
            .where((r) => r.id == ruleId)
            .firstOrNull;
        _checkPresetRevision(expected?.toJson(), rule?.toJson());
        if (rule == null) return ledger;
        final months = {
          ...rule.generatedMonthKeys,
          ...ledger._knownRuleMonths(ruleId)
        };
        if (months.isNotEmpty) {
          await database.setMetaValue('$_retiredRulePrefix${rule.name.trim()}',
              jsonEncode({'id': rule.id, 'months': months.toList()..sort()}));
        }
        await ledger._saveRecurringTransactionRules(ledger
            .recurringTransactionRules
            .where((r) => r.id != ruleId)
            .toList());
        return refresh();
      });

  Future<FinanceRepository> saveRecurringTransactionRule(
          RecurringTransactionRule rule,
          {int? generateMonthsAhead,
          bool requireExisting = false,
          RecurringTransactionRule? expected}) =>
      database.transaction(() async {
        final ledger = await refresh();
        final latest = ledger.recurringTransactionRules
            .where((r) => r.id == rule.id)
            .firstOrNull;
        _checkPresetRevision(expected?.toJson(), latest?.toJson());
        if ((requireExisting ||
                _recurringTransactionRules.any((r) => r.id == rule.id)) &&
            latest == null) {
          throw const FormatException('这条周期规则已删除，请重新选择。');
        }
        return ledger._writeRecurringRule(rule,
            monthsAhead: generateMonthsAhead);
      });

  Future<FinanceRepository> generateRecurringTransactions(String ruleId,
          {int monthsAhead = 6,
          DateTime? asOf,
          RecurringTransactionRule? expected}) =>
      database.transaction(() async {
        final ledger = await refresh();
        final rule = ledger.recurringTransactionRules
            .where((r) => r.id == ruleId)
            .firstOrNull;
        _checkPresetRevision(expected?.toJson(), rule?.toJson());
        if (rule == null || !rule.isActive || rule.intervalMonths <= 0) {
          return ledger;
        }
        return ledger._writeRecurringRule(rule,
            monthsAhead: monthsAhead, asOf: asOf);
      });

  // Caller holds the write transaction and supplied the latest ledger revision.
  Future<FinanceRepository> _writeRecurringRule(RecurringTransactionRule rule,
      {int? monthsAhead, FinanceTransaction? seed, DateTime? asOf}) async {
    if (rule.intervalMonths <= 0 || rule.intervalMonths > 9007199254740991) {
      throw ArgumentError.value(
          rule.intervalMonths, 'intervalMonths', '间隔月数必须是有效的正整数');
    }
    final previous =
        recurringTransactionRules.where((r) => r.id == rule.id).firstOrNull;
    if (rule.generatedMonthKeys.any((key) => !isRecurringMonthKey(key))) {
      throw const FormatException('周期规则生成月份必须是 YYYY-MM。');
    }
    if (rule.name.trim().isEmpty ||
        (previous?.name.trim() != rule.name.trim() &&
            recurringTransactionRules.any(
                (r) => r.id != rule.id && r.name.trim() == rule.name.trim()))) {
      throw const FormatException('请输入唯一的周期规则名称。');
    }
    if (rule.categoryId != null &&
        previous?.categoryId != rule.categoryId &&
        _categories.any((c) => c.id == rule.categoryId && c.isArchived)) {
      throw const FormatException('该类别已归档，请使用有效类别建立规则。');
    }
    final historyKey = '$_retiredRulePrefix${rule.name.trim()}';
    final rawHistory = _metaValues[historyKey];
    final retired = rawHistory == null ? null : _readRetiredRule(rawHistory);
    if (retired != null) {
      if (retired.id != rule.id) {
        throw const FormatException('这个名称已有其他规则的生成历史。请使用不同名称，或从新增入口恢复同名规则。');
      }
      await database.deleteMetaValue(historyKey);
    }
    // Prior markers survive deletions, moved transactions and stale editor drafts.
    // Existing pre-marker rows (including converted actuals) also occupy a month.
    final keys = {
      ...?previous?.generatedMonthKeys,
      ...?retired?.months,
      ...rule.generatedMonthKeys,
      ..._knownRuleMonths(rule.id),
    };
    if (seed != null && seed.recurringRuleId != rule.id) {
      final key = recurringMonthKey(seed.transactionDate);
      if (_transactions.any((t) =>
          t.recurringRuleId == rule.id &&
          _nominalMonth(t, rule.id) == key &&
          t.id != seed.id)) {
        throw const FormatException('该规则在这笔交易的月份已有记录，请先核对已有实例。');
      }
      await database.linkTransactionToRecurringRule(seed.id, rule.id);
      await database.setMetaValue(occurrenceKey(rule.id, seed.id), key);
      keys.add(key);
    }

    final additions = <FinanceTransaction>[];
    if (monthsAhead != null && rule.isActive) {
      final now = asOf ?? DateTime.now();
      final through = DateTime(now.year, now.month + monthsAhead + 1, 0);
      for (final date in recurringDates(
          start: rule.startDate,
          intervalMonths: rule.intervalMonths,
          after: now,
          through: through,
          end: rule.endDate)) {
        final key = recurringMonthKey(date);
        if (!keys.add(key)) continue;
        additions.add(rule.toTransaction(
            id: recurringInstanceId(rule.id, key),
            date: date,
            status: TransactionStatus.planned));
      }
    }
    if (additions.isNotEmpty) {
      if (rule.categoryId != null &&
          _categories.any((c) => c.id == rule.categoryId && c.isArchived)) {
        throw const FormatException('该周期规则的类别已归档，请先修改类别。');
      }
      await database.insertTransactions(additions);
    }
    await _saveRecurringTransactionRules([
      ...recurringTransactionRules.where((r) => r.id != rule.id),
      rule.copyWith(generatedMonthKeys: keys.toList()..sort()),
    ]);
    // Only planned rows and rule links changed; asset-goal balances are intact.
    return refresh();
  }

  Future<Map<String, dynamic>> buildJsonSnapshotPayload() async {
    final metaValues = await database.fetchAllMetaValues();
    final exportableMeta = Map<String, String>.from(metaValues)
      ..removeWhere((key, _) => key.startsWith('loan_installment/'))
      ..remove('data_migration_version')
      ..remove('account_report_groups_v1')
      ..remove(AppDatabase.presetTablesMarker)
      ..remove(AppDatabase.legacyTemplatesKey)
      ..remove(AppDatabase.legacyRulesKey);
    return {
      'format_version': 3,
      'transaction_date_semantics': 'occurrence_date',
      'app_version': appVersion,
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
              ...item.loanFields,
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
          {required List<String> monthKeys}) =>
      categoryReports.aiSummary(
        monthKeys: monthKeys,
        baseCurrency: baseCurrency,
        currencyPriority: currencyPriority,
        rates: exchangeRatesToBase,
        unpricedCurrencies: unpricedCurrencies,
        assetsByGroup: totalAssetsByGroup,
        activeBudgets: activeBudgetsForMonth,
        effectiveBudget: effectiveBudgetForMonth,
        budgetUsage: budgetUsageFor,
        budgetLimitIsValued: budgetLimitIsValued,
      );

  Uint8List exportAiSummaryBytes({required List<String> monthKeys}) {
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(
          buildAiSummaryPayload(monthKeys: monthKeys),
        ),
      ),
    );
  }

  Uint8List exportFuturePlanningCsvBytes({int months = 24}) =>
      categoryReports.planningCsv(
          months: months,
          currency: baseCurrency,
          activeBudgets: activeBudgetsForMonth,
          effectiveBudget: effectiveBudgetForMonth,
          budgetLimitIsValued: budgetLimitIsValued);

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
  Future<FinanceRepository> importJsonSnapshotBytes(
    Uint8List bytes, {
    bool detachUnresolvedCategoryParents = false,
  }) async {
    final payload = _decodeImportPayload(bytes);
    final repairs = _repairImportCategoryParents(payload);
    if (!detachUnresolvedCategoryParents) {
      final unresolved = repairs.where((repair) => repair.parentName == null);
      if (unresolved.firstOrNull case final repair?) {
        throw FormatException(
          '「${repair.categoryName}」的上级分类「${repair.originalParent}」无法确认。'
          '请在导入预览中确认保留为顶层分类。',
        );
      }
    }
    return _restoreSnapshot(payload, fromSync: false);
  }

  /// Rebuilds the isolated browser cache from a server revision.
  Future<FinanceRepository> restoreSyncedSnapshot(
      Map<String, dynamic> snapshot) async {
    final validated = _decodeImportPayload(
      Uint8List.fromList(utf8.encode(jsonEncode(snapshot))),
      requireAllSections: true,
    );
    return _restoreSnapshot(validated, fromSync: true);
  }

  Future<FinanceRepository> _restoreSnapshot(
    Map<String, dynamic> payload, {
    required bool fromSync,
  }) async {
    final metaPayload = payload['meta'] as Map<String, dynamic>? ?? const {};
    final formatVersion = (payload['format_version'] as num?)?.toInt() ?? 1;

    final accountItems =
        (payload['accounts'] as List<dynamic>? ?? const []).map((item) {
      final type = AccountType.values.byName(item['account_type'] as String);
      final group = ReportGroup.values
          .where((g) => g.name == item['report_group'])
          .firstOrNull;
      if (group == null && formatVersion >= 3) {
        throw FormatException('账户报表分组无效：${item['id']}');
      }
      return Account(
        id: item['id'] as String,
        name: item['name'] as String,
        accountType: type,
        reportGroup: group ?? allowedReportGroups(type).first,
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
      );
    }).toList();
    final creditCardAccountIds = accountItems
        .where((item) => item.accountType == AccountType.creditCard)
        .map((item) => item.id)
        .toSet();
    final usesLegacySettlementDates = formatVersion < 3;
    final categoryItems = _importCategories(payload);
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
        loanInstallmentNumber:
            parseLoanInstallmentNumber(item['loan_installment_number']),
        loanPaymentAmount: (item['loan_payment_amount'] as num?)?.toDouble(),
        legacyLoanPartNumber:
            parseLoanInstallmentNumber(item['legacy_loan_part_number']),
        legacyLoanId: item['legacy_loan_id'] as String?,
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
    final legacyTemplatePayload = metaPayload[AppDatabase.legacyTemplatesKey];
    final legacyRulePayload = metaPayload[AppDatabase.legacyRulesKey];
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
    final templateItems = templatePayload.map((item) {
      if (item is! Map) {
        throw const FormatException('快速模板数据格式无效，每项必须是对象。');
      }
      return TransactionTemplate.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
    final recurringRuleItems = recurringRulePayload.map((item) {
      if (item is! Map) {
        throw const FormatException('周期规则数据格式无效，每项必须是对象。');
      }
      return RecurringTransactionRule.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
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
    if (!hasAnyData && !fromSync) {
      throw const FormatException(
          'Import file does not contain any finance data.');
    }

    final encodedMeta = {
      for (final entry in metaPayload.entries)
        if (!entry.key.startsWith('loan_installment/') &&
            entry.key != AppDatabase.legacyTemplatesKey &&
            entry.key != AppDatabase.legacyRulesKey &&
            entry.key != AppDatabase.presetTablesMarker &&
            entry.key != 'account_report_groups_v1')
          entry.key: '${entry.value}',
    };
    _validateImportMeta(encodedMeta);

    if (!fromSync) {
      final restorePoint = await local_files.importRestorePointPath();
      if (restorePoint != null) await exportJsonSnapshot(restorePoint);
    }

    await database.replaceAllWithSeedData(
      accountItems: accountItems,
      categoryItems: categoryItems,
      budgetItems: budgetItems,
      transactionItems: transactionItems,
      snapshotItems: snapshotItems,
      templateItems: templateItems,
      recurringRuleItems: recurringRuleItems,
      metaValues: encodedMeta,
    );
    return _refreshWithGoalSync();
  }

  Future<ImportPreview> previewImportJson(String path) async {
    return previewImportBytes(await local_files.readFileBytes(path));
  }

  Future<ImportPreview> previewImportBytes(Uint8List bytes) async {
    final payload = _decodeImportPayload(bytes);
    final categoryParentRepairs = _repairImportCategoryParents(payload);
    CategoryHierarchy(_importCategories(payload)).validate();
    return ImportPreview(
      accounts: (payload['accounts'] as List<dynamic>? ?? const []).length,
      categories: (payload['categories'] as List<dynamic>? ?? const []).length,
      budgets: (payload['budgets'] as List<dynamic>? ?? const []).length,
      transactions:
          (payload['transactions'] as List<dynamic>? ?? const []).length,
      assetSnapshots:
          (payload['asset_snapshots'] as List<dynamic>? ?? const []).length,
      exportedAt: payload['exported_at'] as String?,
      categoryParentRepairs: categoryParentRepairs,
    );
  }

  List<Category> _importCategories(Map<String, dynamic> payload) {
    return (payload['categories'] as List<dynamic>? ?? const [])
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
  }

  List<CategoryParentImportRepair> _repairImportCategoryParents(
    Map<String, dynamic> payload,
  ) {
    final rows = (payload['categories'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final byId = {for (final row in rows) row['id'] as String: row};
    final names = <({String type, String name}), List<String>>{};
    final parents = <String, String?>{};
    for (final row in rows) {
      final id = row['id'] as String;
      final type = row['type'] as String;
      final name = (row['name'] as String).trim();
      final parent = row['parent_id'] as String?;
      names.putIfAbsent((type: type, name: name), () => []).add(id);
      if (byId.containsKey(parent)) parents[id] = parent;
    }

    final repairs = <CategoryParentImportRepair>[];
    for (final row in rows) {
      final parent = row['parent_id'] as String?;
      if (parent == null || byId.containsKey(parent)) continue;

      final childId = row['id'] as String;
      final type = row['type'] as String;
      final candidates = names[(type: type, name: parent.trim())] ?? const [];
      final candidate = candidates.length == 1 ? candidates.single : null;
      final resolved = candidate != null &&
              !categoryParentWouldCycle(childId, candidate, parents)
          ? candidate
          : null;
      row['parent_id'] = resolved;
      parents[childId] = resolved;
      repairs.add((
        categoryName: row['name'] as String,
        originalParent: parent,
        parentName: byId[resolved]?['name'] as String?,
      ));
    }
    return List.unmodifiable(repairs);
  }

  Map<String, dynamic> _decodeImportPayload(
    Uint8List bytes, {
    bool requireAllSections = false,
  }) {
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
    final requiredSections = requireAllSections
        ? listFields.toSet()
        : (formatVersion == 3
            ? const {'accounts', 'transactions'}
            : const <String>{});
    for (final field in listFields) {
      final value = payload[field];
      if (value == null) {
        if (requiredSections.contains(field)) {
          throw FormatException('备份文件缺少必需的数据段 "$field"，无法导入。');
        }
        continue;
      }
      if (value is! List) {
        throw FormatException('JSON 字段 "$field" 必须是数组。');
      }
      for (final item in value) {
        if (item is! Map) {
          throw FormatException('JSON 字段 "$field" 中包含无效的非对象项。');
        }
      }
    }
    if (payload['meta'] != null && payload['meta'] is! Map) {
      throw const FormatException('JSON 字段 "meta" 必须是对象。');
    }
    return payload;
  }

  void _validateImportMeta(Map<String, String> meta) {
    for (final entry in meta.entries) {
      if (entry.key.startsWith(_retiredRulePrefix)) {
        _readRetiredRule(entry.value);
      }
      if (entry.key.startsWith(recurringOccurrenceMetaPrefix) &&
          !isRecurringMonthKey(entry.value)) {
        throw const FormatException('周期实例的名义月份无效。');
      }
    }
    final goalsRaw = meta['asset_goals_json'];
    if (goalsRaw != null && goalsRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(goalsRaw);
        if (decoded is! List) {
          throw const FormatException('asset_goals_json 必须是数组');
        }
        for (final item in decoded) {
          if (item is! Map) {
            throw const FormatException('asset_goals_json 包含非对象项');
          }
          // Currency-less goals acquire the restored ledger's base on load.
          final goal = AssetGoal.fromJson(Map<String, dynamic>.from(item),
              legacyCurrency: baseCurrencyCode);
          if (!goal.targetAmount.isFinite || goal.targetAmount <= 0) {
            throw const FormatException('目标金额必须大于 0');
          }
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('导入文件中的资产目标数据损坏。');
      }
    }

    final priorityRaw = meta[_currencyPriorityMetaKey];
    if (priorityRaw != null && priorityRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(priorityRaw);
        if (decoded is! List ||
            decoded.any((v) => v is! String || v.trim().isEmpty)) {
          throw const FormatException('货币优先级必须是非空币种代码的数组。');
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('导入文件中的货币优先级数据损坏。');
      }
    }

    readCurrencyQuotes(meta[_exchangeRatesMetaKey], baseCurrencyCode,
        strict: true);
  }

  static final RegExp _monthKeyPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  bool _isValidMonthKey(String value) => _monthKeyPattern.hasMatch(value);

  void _validateImportReferences({
    required List<Account> accounts,
    required List<Category> categories,
    required List<Budget> budgets,
    required List<FinanceTransaction> transactions,
    required List<AssetSnapshot> snapshots,
    required List<TransactionTemplate> templates,
    required List<RecurringTransactionRule> recurringRules,
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

    for (final account in accounts) {
      if (!account.initialBalance.isFinite ||
          !account.currentBalance.isFinite) {
        throw FormatException('账户 ${account.id} 的余额包含无效数值。');
      }
      if (account.accountType == AccountType.loan) {
        if (account.loanStartDate != null &&
            account.loanTrackingStartDate != null &&
            !validLoanTrackingDate(
                account.loanStartDate!, account.loanTrackingStartDate!)) {
          throw FormatException('贷款账户 ${account.id} 的开始记账日早于合同开始日。');
        }
        if (account.loanTermMonths != null &&
            (account.loanTermMonths! <= 0 || account.loanTermMonths! > 1200)) {
          throw FormatException(
            '贷款账户 ${account.id} 的期数无效：${account.loanTermMonths}',
          );
        }
        if ((account.loanPrincipal != null &&
                !account.loanPrincipal!.isFinite) ||
            (account.loanAnnualInterestRate != null &&
                !account.loanAnnualInterestRate!.isFinite) ||
            (account.loanQuotedMonthlyPayment != null &&
                !account.loanQuotedMonthlyPayment!.isFinite)) {
          throw FormatException('贷款账户 ${account.id} 的利率或金额包含无效数值。');
        }
        if (account.hasCompleteLoanProfile &&
            account.initialBalance.abs() > 0) {
          try {
            calculateLoanAmortization(
              principal: account.loanPrincipal!,
              annualInterestRatePercent: account.loanAnnualInterestRate!,
              termMonths: account.loanTermMonths!,
              startDate:
                  account.loanTrackingStartDate ?? account.loanStartDate!,
              paymentDay: account.loanPaymentDay!,
              method: account.loanRepaymentMethod!,
              quotedMonthlyPayment: account.loanQuotedMonthlyPayment,
              openingPrincipal: account.initialBalance.abs(),
            );
          } on ArgumentError catch (error) {
            throw FormatException(
              '贷款账户 ${account.id} 的合同参数无效：${error.message}',
            );
          }
        }
      }
    }
    CategoryHierarchy(categories).validate();
    final budgetKeys = <String>{};
    for (final budget in budgets) {
      requireCategory(budget.categoryId, '预算 ${budget.id}');
      if (!_isValidMonthKey(budget.monthKey)) {
        throw FormatException('预算 ${budget.id} 的月份格式无效：${budget.monthKey}');
      }
      if (!budget.amount.isFinite ||
          budget.amount < 0 ||
          !budget.alertThreshold.isFinite ||
          budget.alertThreshold <= 0) {
        throw FormatException('预算 ${budget.id} 的金额或阈值无效。');
      }
      final key = '${budget.categoryId}|${budget.monthKey}';
      if (!budgetKeys.add(key)) {
        throw FormatException(
          '预算存在重复的类别和月份规则：${budget.categoryId} (${budget.monthKey})',
        );
      }
    }
    for (final transaction in transactions) {
      requireAccount(transaction.accountId, '交易 ${transaction.id}');
      if (transaction.toAccountId case final String targetId) {
        requireAccount(targetId, '交易 ${transaction.id}');
      }
      requireCategory(transaction.categoryId, '交易 ${transaction.id}');
      // Deleting a recurring rule intentionally retains its transaction history.
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
      if (rule.intervalMonths <= 0) {
        throw FormatException(
          '周期规则 ${rule.id} 的间隔月数必须大于 0：${rule.intervalMonths}',
        );
      }
    }
  }

  Future<FinanceRepository> addCategory(Category category) async {
    await database.insertCategory(category);
    return refresh();
  }

  Future<FinanceRepository> updateExistingCategory(Category category) async {
    await database.updateCategory(category);
    return refresh();
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
    if (!_isValidMonthKey(budget.monthKey)) {
      throw FormatException('预算月份格式无效：${budget.monthKey}');
    }
    if (!budget.amount.isFinite ||
        budget.amount < 0 ||
        !budget.alertThreshold.isFinite ||
        budget.alertThreshold <= 0) {
      throw const FormatException('预算金额或提醒阈值无效。');
    }
    await database.upsertBudget(budget);
    return refresh();
  }

  Future<FinanceRepository> deleteExistingBudget(String budgetId) async {
    await database.deleteBudget(budgetId);
    return refresh();
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

  Future<FinanceRepository> replaceExistingTransactions({
    required Iterable<String> deleteIds,
    required List<FinanceTransaction> insertItems,
  }) async {
    await database.replaceTransactions(
      deleteIds: deleteIds,
      insertItems: insertItems,
    );
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

  Future<FinanceRepository> _refreshWithGoalSync() =>
      _changeGoals((ledger) => ledger.assetGoals);

  /// The returned revision contains the newly persisted milestone metadata
  /// and the same finance rows used to derive it.
  Future<FinanceRepository> _changeGoals(
      List<AssetGoal> Function(FinanceRepository) change) {
    return database.transaction(() async {
      final ledger = await refresh();
      final goals = change(ledger);
      final summaries = goals.isEmpty
          ? const <AssetGoalProgressSummary>[]
          : ledger._summariesForGoals(goals, ledger.assetGoalCutoffDate());
      final byId = {for (final summary in summaries) summary.goal.id: summary};
      final synced = [
        for (final goal in goals)
          if (byId[goal.id]!.valuationAvailable)
            goal.copyWith(
                reachedAt: byId[goal.id]!.reachedAt,
                clearReachedAt: byId[goal.id]!.reachedAt == null)
          else
            goal,
      ]..sort((a, b) {
          final byTarget = a.targetAmount.compareTo(b.targetAmount);
          return byTarget == 0 ? a.id.compareTo(b.id) : byTarget;
        });
      final meta = await ledger._saveAssetGoals(synced);
      if (meta == null) return ledger;
      // Goal dates alone do not invalidate the rows, FX rates or valuation indexes.
      return FinanceRepository._(
        database: database,
        accounts: ledger._accounts,
        categories: ledger._categories,
        budgets: ledger._budgets,
        transactions: ledger._transactions,
        snapshots: ledger._snapshots,
        transactionTemplates: ledger._transactionTemplates,
        recurringTransactionRules: ledger._recurringTransactionRules,
        metaValues: Map.unmodifiable(meta),
      )
        .._valuations = ledger._valuations
        .._timeline = ledger._timeline;
    });
  }

  /// Called inside a write transaction. A null result means that all
  /// persisted values already matched, including removal of legacy keys.
  Future<Map<String, String>?> _saveAssetGoals(List<AssetGoal> goals) async {
    final encoded = goals.isEmpty
        ? null
        : jsonEncode(goals.map((goal) => goal.toJson()).toList());
    final old = _metaValues;
    const key = 'asset_goals_json';
    final obsolete = ['asset_goal_amount', 'asset_goal_reached_at']
        .where(old.containsKey)
        .toList();
    if (old[key] == encoded && obsolete.isEmpty) return null;
    final next = Map.of(old);
    if (old[key] != encoded) {
      if (encoded == null) {
        await database.deleteMetaValue(key);
        next.remove(key);
      } else {
        await database.setMetaValue(key, encoded);
        next[key] = encoded;
      }
    }
    for (final legacy in obsolete) {
      await database.deleteMetaValue(legacy);
      next.remove(legacy);
    }
    return next;
  }

  Future<void> _saveTransactionTemplates(
    List<TransactionTemplate> templates,
  ) =>
      database.replaceTransactionTemplates(templates);

  Future<void> _saveRecurringTransactionRules(
    List<RecurringTransactionRule> rules,
  ) =>
      database.replaceRecurringTransactionRules(rules);

  double _accountBalanceAt(Account account, DateTime date) =>
      valuationBook.projection(account.id, date).balance;

  double _transactionDeltaForAccount(
          String accountId, FinanceTransaction transaction) =>
      valuationBook.deltaFor(accountId, transaction);

  late final Set<String> _cashAccountIds = {
    for (final account in _accounts)
      if (account.effectiveReportGroup == ReportGroup.cash) account.id,
  };

  double _actualCashFlowDelta(FinanceTransaction transaction) {
    final amount = transactionAmountInBase(transaction);
    final sourceIsCash = _cashAccountIds.contains(transaction.accountId);
    switch (transaction.type) {
      case TransactionType.income:
      case TransactionType.adjustment:
        return sourceIsCash ? amount : 0;
      case TransactionType.expense:
        return sourceIsCash ? -amount : 0;
      case TransactionType.transfer:
        final incoming = _cashAccountIds.contains(transaction.toAccountId)
            ? transferIncomingAmountInBase(transaction)
            : 0.0;
        return incoming - (sourceIsCash ? amount : 0);
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
      return categoryName(categoryId);
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
      parts.add(categoryName(categoryId));
    }
    if (transaction.type == TransactionType.transfer &&
        transaction.toAccountId != null) {
      parts.add(
        '${accountName(transaction.accountId)} -> '
        '${accountName(transaction.toAccountId!)}',
      );
    } else {
      parts.add(accountName(transaction.accountId));
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

  @override
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

typedef CategoryParentImportRepair = ({
  String categoryName,
  String originalParent,
  String? parentName,
});

class ImportPreview {
  const ImportPreview({
    required this.accounts,
    required this.categories,
    required this.budgets,
    required this.transactions,
    required this.assetSnapshots,
    required this.exportedAt,
    this.categoryParentRepairs = const [],
  });

  final int accounts;
  final int categories;
  final int budgets;
  final int transactions;
  final int assetSnapshots;
  final String? exportedAt;
  final List<CategoryParentImportRepair> categoryParentRepairs;

  bool get hasUnresolvedCategoryParents =>
      categoryParentRepairs.any((repair) => repair.parentName == null);
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
