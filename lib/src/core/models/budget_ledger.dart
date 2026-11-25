import 'budget.dart';
import 'category_hierarchy.dart';
import 'transaction.dart';

class BudgetUsage {
  const BudgetUsage(this.actual, this.planned, this.transactions,
      {this.actualValued = true, this.plannedValued = true});

  static const empty = BudgetUsage(0, 0, []);
  final double actual;
  final double planned;
  final List<FinanceTransaction> transactions;
  final bool actualValued;
  final bool plannedValued;
}

typedef BudgetPreview = ({
  double baseAmount,
  double carried,
  double effective,
  double actual,
  double planned,
  double nextBaseAmount,
  double nextCarried,
  double nextEffective,
  bool baseValued,
  bool carriedValued,
  bool effectiveValued,
  bool actualValued,
  bool plannedValued,
  bool nextBaseValued,
  bool nextCarriedValued,
  bool nextEffectiveValued,
});

/// Month-effective budgets and their disjoint shares of spending.
/// Amounts are in the ledger's display currency; each transaction keeps its
/// original amount and currency in the detail list.
class BudgetLedger {
  BudgetLedger({
    required List<Budget> budgets,
    required Iterable<FinanceTransaction> transactions,
    required this.hierarchy,
    required this.tryConvertToBase,
  }) : _rules =
            ([...budgets]..sort((a, b) => a.monthKey.compareTo(b.monthKey))) {
    for (final entry in transactions) {
      if (entry.type == TransactionType.expense && entry.categoryId != null) {
        (_expenses[_monthKey(entry.transactionDate)] ??= []).add(entry);
      }
    }
    for (final entries in _expenses.values) {
      entries.sort((a, b) {
        final date = b.transactionDate.compareTo(a.transactionDate);
        return date != 0 ? date : a.id.compareTo(b.id);
      });
    }
  }

  final CategoryHierarchy hierarchy;
  final double? Function(double amount, String currency) tryConvertToBase;
  final List<Budget> _rules;
  final _expenses = <String, List<FinanceTransaction>>{};
  final _active = <String, Map<String, Budget>>{};
  final _usages = <String, Map<String, BudgetUsage>>{};
  final _effective = <(String, String), ({double amount, bool valued})>{};

  Map<String, Budget> _rulesAt(String month) => _active.putIfAbsent(
      month,
      () => {
            for (final rule in _rules)
              if (rule.monthKey.compareTo(month) <= 0) rule.categoryId: rule,
          });

  List<Budget> activeRules(String month) => _rulesAt(month).values.toList()
    ..sort((a, b) {
      final byName = (hierarchy.byId[a.categoryId]?.name ?? '')
          .compareTo(hierarchy.byId[b.categoryId]?.name ?? '');
      return byName != 0 ? byName : a.categoryId.compareTo(b.categoryId);
    });

  Map<String, BudgetUsage> _allocate(String month, Set<String> budgetIds) {
    final groups = <String, List<FinanceTransaction>>{};
    for (final entry in _expenses[month] ?? const <FinanceTransaction>[]) {
      final owner = hierarchy.nearestAncestorIn(entry.categoryId, budgetIds);
      if (owner != null) {
        (groups[owner] ??= []).add(entry);
      }
    }
    return groups.map((owner, entries) {
      var actual = 0.0;
      var planned = 0.0;
      var actualValued = true;
      var plannedValued = true;
      for (final entry in entries) {
        final amount = tryConvertToBase(entry.amount, entry.currency);
        if (entry.status == TransactionStatus.planned) {
          plannedValued = plannedValued && amount != null;
          planned += amount ?? 0;
        } else {
          actualValued = actualValued && amount != null;
          actual += amount ?? 0;
        }
      }
      return MapEntry(
          owner,
          BudgetUsage(actual, planned, List.unmodifiable(entries),
              actualValued: actualValued, plannedValued: plannedValued));
    });
  }

  Map<String, BudgetUsage> _usageAt(String month) => _usages.putIfAbsent(
      month, () => _allocate(month, _rulesAt(month).keys.toSet()));

  BudgetUsage usage(String categoryId, String month) =>
      _usageAt(month)[categoryId] ?? BudgetUsage.empty;

  double totalSpent(String month, {required bool planned}) => _usageAt(month)
      .values
      .fold(0.0, (sum, item) => sum + (planned ? item.planned : item.actual));

  static String _shiftMonth(String month, int offset) {
    final parts = month.split('-');
    return _monthKey(
        DateTime(int.parse(parts[0]), int.parse(parts[1]) + offset));
  }

  static String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  ({double amount, bool valued}) _effectiveAmount(
      String categoryId, String month) {
    final cached = _effective[(categoryId, month)];
    if (cached != null) return cached;
    final months = <String>[];
    var cursor = month;
    var carry = 0.0;
    var carryValued = true;
    while (_rulesAt(cursor).containsKey(categoryId)) {
      months.add(cursor);
      final previous = _shiftMonth(cursor, -1);
      if (_rulesAt(previous)[categoryId]?.rolloverEnabled != true) break;
      final previousEffective = _effective[(categoryId, previous)];
      if (previousEffective != null) {
        final spent = usage(categoryId, previous);
        carry = previousEffective.amount - spent.actual;
        carryValued = previousEffective.valued && spent.actualValued;
        break;
      }
      cursor = previous;
    }
    for (final key in months.reversed) {
      final rule = _rulesAt(key)[categoryId]!;
      final pricedBase = tryConvertToBase(rule.amount, rule.currency);
      final effective = (pricedBase ?? 0) + carry;
      final valued = pricedBase != null && carryValued;
      _effective[(categoryId, key)] = (amount: effective, valued: valued);
      if (key != month) {
        final spent = usage(categoryId, key);
        carry = effective - spent.actual;
        carryValued = valued && spent.actualValued;
      }
    }
    return _effective[(categoryId, month)] ?? (amount: 0.0, valued: true);
  }

  double effectiveAmount(String categoryId, String month) =>
      _effectiveAmount(categoryId, month).amount;

  bool limitIsValued(String categoryId, String month) =>
      _effectiveAmount(categoryId, month).valued;

  BudgetPreview preview(Budget draft) {
    final id = draft.categoryId;
    final month = draft.monthKey;
    final previous = _shiftMonth(month, -1);
    final previousRule = _rulesAt(previous)[id];
    final carried = previousRule?.rolloverEnabled == true
        ? effectiveAmount(id, previous) - usage(id, previous).actual
        : 0.0;
    final carriedValued = previousRule?.rolloverEnabled != true ||
        (limitIsValued(id, previous) && usage(id, previous).actualValued);
    final pricedBase = tryConvertToBase(draft.amount, draft.currency);
    final baseValued = pricedBase != null;
    final effectiveValued = baseValued && carriedValued;
    final baseAmount = pricedBase ?? 0.0;
    final effective = baseAmount + carried;
    final existing = _rulesAt(month);
    final spent = existing.containsKey(id)
        ? usage(id, month)
        : _allocate(month, {...existing.keys, id})[id] ?? BudgetUsage.empty;
    final next = _shiftMonth(month, 1);
    final nextRule = _rulesAt(next)[id];
    final pricedNextBase = nextRule != null && nextRule.monthKey == next
        ? tryConvertToBase(nextRule.amount, nextRule.currency)
        : pricedBase;
    final nextBase = pricedNextBase ?? 0.0;
    final nextCarriedValued = !draft.rolloverEnabled ||
        (effectiveValued && spent.actualValued && spent.plannedValued);
    final nextCarry =
        draft.rolloverEnabled ? effective - spent.actual - spent.planned : 0.0;
    return (
      baseAmount: baseAmount,
      carried: carried,
      effective: effective,
      actual: spent.actual,
      planned: spent.planned,
      nextBaseAmount: nextBase,
      nextCarried: nextCarry,
      nextEffective: nextBase + nextCarry,
      baseValued: baseValued,
      carriedValued: carriedValued,
      effectiveValued: effectiveValued,
      actualValued: spent.actualValued,
      plannedValued: spent.plannedValued,
      nextBaseValued: pricedNextBase != null,
      nextCarriedValued: nextCarriedValued,
      nextEffectiveValued: pricedNextBase != null && nextCarriedValued
    );
  }
}

mixin BudgetQueries {
  BudgetLedger get budgetLedger;

  List<Budget> activeBudgetsForMonth(String monthKey) =>
      budgetLedger.activeRules(monthKey);
  BudgetUsage budgetUsageFor(String categoryId, String monthKey) =>
      budgetLedger.usage(categoryId, monthKey);
  bool budgetLimitIsValued(String categoryId, String monthKey) =>
      budgetLedger.limitIsValued(categoryId, monthKey);
  bool budgetMonthIsValued(String monthKey) =>
      activeBudgetsForMonth(monthKey).every((rule) {
        final usage = budgetUsageFor(rule.categoryId, monthKey);
        return budgetLimitIsValued(rule.categoryId, monthKey) &&
            usage.actualValued &&
            usage.plannedValued;
      });
  BudgetPreview previewBudget(Budget draft) => budgetLedger.preview(draft);
  double totalBudgetExpenseForMonth(String monthKey) =>
      budgetLedger.totalSpent(monthKey, planned: false);
  double totalPlannedBudgetExpenseForMonth(String monthKey) =>
      budgetLedger.totalSpent(monthKey, planned: true);
  double effectiveBudgetForMonth(Budget budget, String monthKey) =>
      monthKey.compareTo(budget.monthKey) < 0
          ? 0
          : budgetLedger.effectiveAmount(budget.categoryId, monthKey);
  double totalEffectiveBudgetForMonth(String monthKey) =>
      activeBudgetsForMonth(monthKey).fold(
          0.0,
          (sum, rule) =>
              sum + budgetLedger.effectiveAmount(rule.categoryId, monthKey));
}
