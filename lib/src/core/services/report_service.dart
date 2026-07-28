import '../data/finance_repository.dart';
import '../models/account.dart';

import '../models/category.dart';
import '../models/forecast_summary.dart';
import '../models/monthly_summary.dart';
import '../models/transaction.dart';

import 'account_service.dart';
import 'budget_service.dart';
import 'currency_service.dart';
import 'service_helpers.dart';

/// 月度汇总、预测分析与现金流投影服务。
///
/// 提供收入/支出月度统计、未来支出预测、
/// 现金流投影以及信用卡还款提醒。
class ReportService {
  ReportService({
    required List<Account> accounts,
    required List<FinanceTransaction> transactions,
    required List<Category> categories,
    required this.accountService,
    required this.budgetService,
    required this.currencyService,
  })  : _accounts = accounts,
        _transactions = transactions,
        _categories = categories;

  final List<Account> _accounts;
  final List<FinanceTransaction> _transactions;
  final List<Category> _categories;
  final AccountService accountService;
  final BudgetService budgetService;
  final CurrencyService currencyService;

  // ---------------------------------------------------------------------------
  // 月度汇总
  // ---------------------------------------------------------------------------

  /// 最近 [months] 个月的月度汇总（实际现金流入/流出）。
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

  /// 未来 [months] 个月的支出预测（含计划交易）。
  List<MonthlySummary> futureExpenseSummaries({int months = 3}) {
    final now = DateTime.now();
    return List.generate(months, (index) {
      final date = DateTime(now.year, now.month + index + 1);
      final monthKey = serviceMonthKey(date);
      return MonthlySummary(
        monthKey: monthKey,
        income: totalIncomeForMonth(monthKey) + plannedIncomeForMonth(monthKey),
        expense:
            totalExpenseForMonth(monthKey) + plannedExpenseForMonth(monthKey),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // 分类汇总
  // ---------------------------------------------------------------------------

  /// 按分类汇总指定月份的金额（基准货币）。
  Map<String, double> categoryTotalsForMonths({
    required CategoryType type,
    required List<String> monthKeys,
  }) {
    final allowedIds =
        _categories.where((c) => c.type == type).map((item) => item.id).toSet();
    final totals = <String, double>{};
    for (final transaction in _transactions) {
      final categoryId = transaction.categoryId;
      if (categoryId == null || !allowedIds.contains(categoryId)) {
        continue;
      }
      if (!monthKeys.contains(serviceMonthKey(transaction.transactionDate))) {
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
          (totals[categoryId] ?? 0) + _transactionAmountInBase(transaction);
    }
    return totals;
  }

  // ---------------------------------------------------------------------------
  // 预测
  // ---------------------------------------------------------------------------

  /// 基于历史月度数据的财务预测。
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
    final currentSavingsBase =
        accountService.totalAssetsByGroup(ReportGroup.cash) +
            accountService.totalAssetsByGroup(ReportGroup.investment) +
            accountService.totalAssetsByGroup(ReportGroup.retirement) +
            accountService.totalAssetsByGroup(ReportGroup.credit);

    return ForecastSummary(
      averageMonthlyIncome: averageIncome,
      averageMonthlyExpense: averageExpense,
      averageMonthlySavings: averageSavings,
      projectedSavingsInThreeMonths: currentSavingsBase + (averageSavings * 3),
      projectedSavingsInSixMonths: currentSavingsBase + (averageSavings * 6),
    );
  }

  // ---------------------------------------------------------------------------
  // 现金流投影
  // ---------------------------------------------------------------------------

  /// 未来 [months] 个月的现金流投影。
  List<CashFlowProjectionPoint> futureCashFlowProjection({int months = 6}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startMonth = DateTime(now.year, now.month);
    final cutoffDate = accountService.currentMonthCutoffDate();
    var runningCash = accountService.displayTotalAssetsByGroup(
      ReportGroup.cash,
      cutoffDate: cutoffDate,
    );

    return List.generate(months, (index) {
      final monthDate = DateTime(startMonth.year, startMonth.month + index);
      final monthKey = serviceMonthKey(monthDate);
      var income = 0.0;
      var expense = 0.0;
      var transfers = 0.0;

      for (final transaction in _transactions.where(
        (item) => serviceMonthKey(item.transactionDate) == monthKey,
      )) {
        if (transaction.transactionDate.isBefore(today) &&
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

  // ---------------------------------------------------------------------------
  // 信用卡还款提醒
  // ---------------------------------------------------------------------------

  /// 信用卡还款提醒列表（按欠款金额倒序）。
  List<CreditCardPaymentReminder> creditCardPaymentReminders({
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final dueDate = DateTime(now.year, now.month + 1, 25);
    final cutoffDate = accountService.currentMonthCutoffDate();
    return _accounts
        .where((account) => account.reportGroup == ReportGroup.credit)
        .map((account) {
          final balance =
              accountService.accountBalanceAt(account.id, cutoffDate);
          return CreditCardPaymentReminder(
            account: account,
            amountDue: balance < 0 ? balance.abs() : 0,
            dueDate: dueDate,
          );
        })
        .where((item) => item.amountDue > 0)
        .toList()
      ..sort((a, b) => b.amountDue.compareTo(a.amountDue));
  }

  // ---------------------------------------------------------------------------
  // 月度收支明细
  // ---------------------------------------------------------------------------

  /// 指定月份的实际收入合计（基准货币）。
  double totalIncomeForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.income &&
            item.status != TransactionStatus.planned &&
            serviceMonthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + _transactionAmountInBase(item));
  }

  /// 指定月份的实际支出合计（基准货币）。
  double totalExpenseForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.expense &&
            item.status != TransactionStatus.planned &&
            serviceMonthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + _transactionAmountInBase(item));
  }

  /// 指定月份现金账户的实际流入与流出，不包含计划交易。
  CashFlowSummary actualCashFlowSummaryForMonth(String monthKey) {
    var inflow = 0.0;
    var outflow = 0.0;
    for (final transaction in _transactions.where(
      (item) =>
          item.status != TransactionStatus.planned &&
          serviceMonthKey(item.transactionDate) == monthKey,
    )) {
      final delta = _actualCashFlowDelta(transaction);
      if (delta >= 0) {
        inflow += delta;
      } else {
        outflow += -delta;
      }
    }
    return CashFlowSummary(inflow: inflow, outflow: outflow);
  }

  /// 指定月份的计划收入合计（基准货币）。
  double plannedIncomeForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.income &&
            item.status == TransactionStatus.planned &&
            serviceMonthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + _transactionAmountInBase(item));
  }

  /// 指定月份的计划支出合计（基准货币）。
  double plannedExpenseForMonth(String monthKey) {
    return _transactions
        .where((item) =>
            item.type == TransactionType.expense &&
            item.status == TransactionStatus.planned &&
            serviceMonthKey(item.transactionDate) == monthKey)
        .fold(0, (sum, item) => sum + _transactionAmountInBase(item));
  }

  // ---------------------------------------------------------------------------
  // 私有辅助
  // ---------------------------------------------------------------------------

  double _transactionAmountInBase(FinanceTransaction transaction) {
    return currencyService.convertToBase(
        transaction.amount, transaction.currency);
  }

  /// 最近 [count] 个月的月份键（含当前月）。
  List<String> _recentMonthKeys(int count) {
    final now = DateTime.now();
    return List.generate(count, (index) {
      final date = DateTime(now.year, now.month - (count - index - 1));
      return serviceMonthKey(date);
    });
  }

  double _actualCashFlowDelta(FinanceTransaction transaction) {
    Account? accountFor(String id) {
      for (final account in _accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    final source = accountFor(transaction.accountId);
    final target = transaction.toAccountId == null
        ? null
        : accountFor(transaction.toAccountId!);
    final amount = _transactionAmountInBase(transaction);
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
          delta += currencyService.convertToBase(
            transaction.transferInAmount,
            transaction.transferInCurrency,
          );
        }
        return delta;
    }
  }
}
