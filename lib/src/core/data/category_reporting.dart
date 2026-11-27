import 'dart:convert';
import 'dart:typed_data';

import '../models/account.dart';
import '../models/budget.dart';
import '../models/budget_ledger.dart';
import '../models/category.dart';
import '../models/category_hierarchy.dart';
import '../models/transaction.dart';
import '../utils/currency_formatter.dart' show MoneyDecimalText;
import '../utils/month_key.dart';

/// Actual and planned amounts in base currency. Missing quotes retain their
/// original amounts and never enter an arithmetic total in another currency.
class CategoryAmounts {
  double actual = 0;
  double planned = 0;
  int actualCount = 0;
  int plannedCount = 0;
  int pricedActualCount = 0;
  int pricedPlannedCount = 0;
  final unpricedActual = <String, double>{};
  final unpricedPlanned = <String, double>{};

  void _add(FinanceTransaction tx, double? converted) {
    final isPlan = tx.status == TransactionStatus.planned;
    if (isPlan) {
      plannedCount++;
    } else {
      actualCount++;
    }
    if (converted == null) {
      final amounts = isPlan ? unpricedPlanned : unpricedActual;
      final unit = tx.currency.trim().toUpperCase();
      amounts[unit] = (amounts[unit] ?? 0) + tx.amount;
    } else if (isPlan) {
      pricedPlannedCount++;
      planned += converted;
    } else {
      pricedActualCount++;
      actual += converted;
    }
  }

  void _merge(CategoryAmounts other) {
    actual += other.actual;
    planned += other.planned;
    actualCount += other.actualCount;
    plannedCount += other.plannedCount;
    pricedActualCount += other.pricedActualCount;
    pricedPlannedCount += other.pricedPlannedCount;
    for (final e in other.unpricedActual.entries) {
      unpricedActual[e.key] = (unpricedActual[e.key] ?? 0) + e.value;
    }
    for (final e in other.unpricedPlanned.entries) {
      unpricedPlanned[e.key] = (unpricedPlanned[e.key] ?? 0) + e.value;
    }
  }
}

/// Direct buckets partition every income/expense transaction once. Subtree
/// totals are for parent drilldowns; only peer roots may be added together.
class CategoryBreakdown {
  CategoryBreakdown(this.tree, this.direct) {
    for (final entry in direct.entries) {
      all._merge(entry.value);
      final id = entry.key;
      if (id == null) continue;
      final path = tree.pathOf(id);
      for (final category in path) {
        subtree
            .putIfAbsent(category.id, CategoryAmounts.new)
            ._merge(entry.value);
      }
      if (path.isNotEmpty) roots.add(path.first.id);
    }
  }

  final CategoryHierarchy tree;
  final Map<String?, CategoryAmounts> direct;
  final subtree = <String, CategoryAmounts>{};
  final roots = <String>{};
  final all = CategoryAmounts();

  Map<String, double> get actualSubtotals => {
        for (final e in subtree.entries)
          if (e.value.actualCount > 0) e.key: e.value.actual
      };

  List<Map<String, dynamic>> rows() {
    final ids = [
      for (final category in tree.ordered)
        if (subtree.containsKey(category.id)) category.id,
      if (direct.containsKey(null)) null,
    ];
    return [
      for (final id in ids) _row(id),
    ];
  }

  Map<String, dynamic> _row(String? id) {
    final own = direct[id] ?? CategoryAmounts();
    final total = subtree[id] ?? own;
    final path = id == null ? const <Category>[] : tree.pathOf(id);
    return {
      'id': id,
      'parent_id': id == null ? null : tree.byId[id]?.parentId,
      'name': path.isEmpty ? '未分类' : path.last.name,
      'path': path.map((c) => c.name).toList(),
      'actual': own.actual,
      'planned': own.planned,
      'subtree_actual': total.actual,
      'subtree_planned': total.planned,
      if (total.unpricedActual.isNotEmpty)
        'subtree_unpriced_actual': total.unpricedActual,
      if (total.unpricedPlanned.isNotEmpty)
        'subtree_unpriced_planned': total.unpricedPlanned,
      if (own.unpricedActual.isNotEmpty) 'unpriced_actual': own.unpricedActual,
      if (own.unpricedPlanned.isNotEmpty)
        'unpriced_planned': own.unpricedPlanned,
    };
  }
}

class CategoryReportIndex {
  CategoryReportIndex(
    this.tree,
    Iterable<FinanceTransaction> transactions, {
    required this.hasRate,
    required double Function(double amount, String currency) convertToBase,
  }) {
    for (final tx in transactions) {
      final category = tree.byId[tx.categoryId];
      final type = switch (tx.type) {
        TransactionType.expense => CategoryType.expense,
        TransactionType.income => CategoryType.income,
        TransactionType.transfer ||
        TransactionType.adjustment =>
          category?.type == CategoryType.transfer ||
                  category?.type == CategoryType.investment
              ? category!.type
              : null,
      };
      if (type == null) continue;
      final month = monthKeyFromDate(tx.transactionDate);
      final id = category?.type == type ? category!.id : null;
      final direct = _months.putIfAbsent((type, month), () => {});
      final converted =
          hasRate(tx.currency) ? convertToBase(tx.amount, tx.currency) : null;
      direct.putIfAbsent(id, CategoryAmounts.new)._add(tx, converted);
    }
  }

  final CategoryHierarchy tree;
  final bool Function(String currency) hasRate;
  final _months = <(CategoryType, String), Map<String?, CategoryAmounts>>{};

  CategoryBreakdown read(CategoryType type, Iterable<String> months) {
    final direct = <String?, CategoryAmounts>{};
    for (final month in months.toSet()) {
      final buckets = _months[(type, month)];
      if (buckets == null) continue;
      for (final entry in buckets.entries) {
        direct.putIfAbsent(entry.key, CategoryAmounts.new)._merge(entry.value);
      }
    }
    return CategoryBreakdown(tree, direct);
  }

  /// Keep the original flat summary keys for single, uniquely named buckets.
  /// Duplicates use their path and stable ID; even identical paths stay distinct.
  Map<String, String> labels() {
    final counts = <String, int>{};
    for (final c in tree.ordered) {
      counts.update(c.name, (n) => n + 1, ifAbsent: () => 1);
    }
    final used = <String>{
      for (final c in tree.ordered)
        if (counts[c.name] == 1) c.name
    };
    final labels = <String, String>{};
    for (final c in tree.ordered) {
      if (counts[c.name] == 1) {
        labels[c.id] = c.name;
      } else {
        var label =
            '${tree.pathOf(c.id).map((v) => v.name).join(' / ')} [${c.id}]';
        while (!used.add(label)) {
          label += ' [${c.id}]';
        }
        labels[c.id] = label;
      }
    }
    return labels;
  }

  Map<String, dynamic> aiSummary({
    required List<String> monthKeys,
    required String baseCurrency,
    required List<String> currencyPriority,
    required Map<String, double> rates,
    required Iterable<String> unpricedCurrencies,
    required double Function(ReportGroup) assetsByGroup,
    required List<Budget> Function(String) activeBudgets,
    required double Function(Budget, String) effectiveBudget,
    required BudgetUsage Function(String, String) budgetUsage,
    required bool Function(String, String) budgetLimitIsValued,
  }) {
    final included = monthKeys
        .toSet()
        .where((m) =>
            _months.containsKey((CategoryType.income, m)) ||
            _months.containsKey((CategoryType.expense, m)))
        .toList();
    final expense = {
      for (final m in included) m: read(CategoryType.expense, [m])
    };
    final income = {
      for (final m in included) m: read(CategoryType.income, [m])
    };
    final names = labels();
    var unclassified = '未分类';
    while (names.containsValue(unclassified)) {
      unclassified += ' [unassigned]';
    }
    Map<String, double> legacyTotals(CategoryBreakdown result) => {
          for (final entry in result.direct.entries)
            if (entry.value.pricedActualCount > 0)
              (entry.key == null ? unclassified : names[entry.key]!):
                  entry.value.actual,
        };
    final expensePeriod = read(CategoryType.expense, included);
    final incomePeriod = read(CategoryType.income, included);
    final current = monthKeyFromDate(DateTime.now());
    final budgetRows = activeBudgets(current).map((b) {
      final usage = budgetUsage(b.categoryId, current);
      return {
        'id': b.id,
        'category_id': b.categoryId,
        'name': tree.byId[b.categoryId]?.name,
        'path': tree.pathOf(b.categoryId).map((c) => c.name).toList(),
        'budget_fully_valued': budgetLimitIsValued(b.categoryId, current),
        'original_currency': b.currency,
        'original_amount': b.amount,
        'budget': budgetLimitIsValued(b.categoryId, current)
            ? effectiveBudget(b, current)
            : null,
        'priced_budget': effectiveBudget(b, current),
        'spent': usage.actualValued ? usage.actual : null,
        'planned': usage.plannedValued ? usage.planned : null,
        'priced_spent': usage.actual,
        'priced_planned': usage.planned,
      };
    }).toList();
    return {
      'exported_at': DateTime.now().toIso8601String(),
      'base_currency': baseCurrency,
      'currency_priority': currencyPriority,
      'exchange_rates_to_base': rates,
      'unpriced_currencies': unpricedCurrencies.toList()..sort(),
      'valuation_scope':
          'base amounts include only priced currencies; unpriced amounts retain their original units',
      'months': included,
      'income_by_month': {for (final m in included) m: income[m]!.all.actual},
      'expense_by_month': {for (final m in included) m: expense[m]!.all.actual},
      'planned_income_by_month': {
        for (final m in included) m: income[m]!.all.planned
      },
      'planned_expense_by_month': {
        for (final m in included) m: expense[m]!.all.planned
      },
      'net_by_month': {
        for (final m in included)
          m: income[m]!.all.actual - expense[m]!.all.actual
      },
      'expense_categories_by_month': {
        for (final m in included) m: legacyTotals(expense[m]!)
      },
      'income_categories_by_month': {
        for (final m in included) m: legacyTotals(income[m]!)
      },
      'expense_category_totals': legacyTotals(expensePeriod),
      'income_category_totals': legacyTotals(incomePeriod),
      'category_rows_by_month': {
        for (final m in included)
          m: {'expense': expense[m]!.rows(), 'income': income[m]!.rows()},
      },
      'category_rows': {
        'expense': expensePeriod.rows(),
        'income': incomePeriod.rows()
      },
      'assets_by_group': {
        for (final group in ReportGroup.values) group.name: assetsByGroup(group)
      },
      'budgets_current_month': {
        for (final row in budgetRows) names[row['category_id']]!: row
      },
      'budget_rows_current_month': budgetRows,
    };
  }

  Uint8List planningCsv({
    required int months,
    required String currency,
    required List<Budget> Function(String month) activeBudgets,
    required double Function(Budget, String month) effectiveBudget,
    required bool Function(String, String) budgetLimitIsValued,
  }) {
    final now = DateTime.now();
    final keys = List.generate(
        months, (i) => monthKeyFromDate(DateTime(now.year, now.month + i + 1)));
    final reports = [
      for (final key in keys) read(CategoryType.expense, [key])
    ];
    final budgets = {
      for (final key in keys)
        key: {for (final b in activeBudgets(key)) b.categoryId: b}
    };
    final lines = <List<String>>[
      ['Category', 'Category ID', 'Measure', 'Currency', ...keys, 'Total']
    ];
    void row(String label, String? id, String measure, String unit,
        List<double?> amounts) {
      lines.add([
        label,
        id ?? '',
        measure,
        unit,
        ...amounts.map((a) => a?.toMoneyDecimal() ?? ''),
        if (amounts.every((a) => a == null))
          ''
        else
          amounts
              .whereType<double>()
              .fold(0.0, (double a, b) => a + b)
              .toMoneyDecimal()
      ]);
    }

    final ids = [
      for (final c in tree.ordered)
        if (c.type == CategoryType.expense) c.id,
      null,
    ];
    for (final id in ids) {
      final label = id == null
          ? 'Uncategorized'
          : tree.pathOf(id).map((v) => v.name).join(' / ');
      final amounts = [
        for (final r in reports) r.direct[id] ?? CategoryAmounts()
      ];
      if (amounts.any((a) => a.pricedActualCount > 0)) {
        row(label, id, 'Actual', currency, [for (final a in amounts) a.actual]);
      }
      if (amounts.any((a) => a.pricedPlannedCount > 0)) {
        row(label, id, 'Planned', currency,
            [for (final a in amounts) a.planned]);
      }
      final missing = {
        for (final a in amounts) ...[
          ...a.unpricedActual.keys,
          ...a.unpricedPlanned.keys
        ]
      };
      for (final unit in missing.toList()..sort()) {
        if (amounts.any((a) => a.unpricedActual.containsKey(unit))) {
          row(label, id, 'Unpriced actual', unit,
              [for (final a in amounts) a.unpricedActual[unit] ?? 0]);
        }
        if (amounts.any((a) => a.unpricedPlanned.containsKey(unit))) {
          row(label, id, 'Unpriced planned', unit,
              [for (final a in amounts) a.unpricedPlanned[unit] ?? 0]);
        }
      }
      if (id != null && budgets.values.any((rules) => rules.containsKey(id))) {
        final partial = keys.any(
            (m) => budgets[m]!.containsKey(id) && !budgetLimitIsValued(id, m));
        row(label, id, partial ? 'Budget (priced subtotal)' : 'Budget',
            currency, [
          for (final key in keys)
            if (budgets[key]![id] case final b?)
              (hasRate(b.currency) ? effectiveBudget(b, key) : null)
            else
              0
        ]);
        final missingUnits = {
          for (final rules in budgets.values)
            if (rules[id] case final b?)
              if (!hasRate(b.currency)) b.currency
        };
        for (final unit in missingUnits.toList()..sort()) {
          row(label, id, 'Unpriced base budget', unit, [
            for (final key in keys)
              if (budgets[key]![id] case final b? when b.currency == unit)
                b.amount
              else
                0
          ]);
        }
      }
    }
    row('Total Actual', null, 'Actual', currency,
        [for (final r in reports) r.all.actual]);
    row('Total Planned', null, 'Planned', currency,
        [for (final r in reports) r.all.planned]);
    row('Total Known', null, 'Actual + Planned', currency,
        [for (final r in reports) r.all.actual + r.all.planned]);
    final partialBudget = keys
        .any((m) => budgets[m]!.keys.any((id) => !budgetLimitIsValued(id, m)));
    row('Total Budget', null,
        partialBudget ? 'Budget (priced subtotal)' : 'Budget', currency, [
      for (final key in keys)
        budgets[key]!
            .values
            .fold<double>(0.0, (sum, b) => sum + effectiveBudget(b, key))
    ]);
    String escape(String cell) => cell.contains(RegExp('[,"\r\n]'))
        ? '"${cell.replaceAll('"', '""')}"'
        : cell;
    return Uint8List.fromList(
        utf8.encode(lines.map((r) => r.map(escape).join(',')).join('\n')));
  }
}
