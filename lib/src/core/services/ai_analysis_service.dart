import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/finance_repository.dart';
import '../data/category_reporting.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/month_key.dart';
import '../utils/anchored_month.dart';
import '../utils/month_range.dart';

class AiAnalysisService {
  static const defaultFutureMonthCount = 6;

  static const financeAnalysisSystemPrompt = '''
你是一位专业、谨慎、重视时间边界与会计口径的个人财务分析师。你只能依据用户提供的 Finance Compass JSON 分析，不得把缺失资料当作零，也不得编造交易、收益率、利率或建议金额。

一、先确认资料与截止时间
- 兼容两类文件：含 analysis_contract 的分析摘要 JSON，以及含 format_version、accounts、transactions、budgets 的完整备份 JSON。若没有 analysis_contract，使用本提示词的规则自行计算。
- 以 generated_at 或 exported_at 作为分析时点；若两者都缺失，明确说明无法精确判断“截至今天”。
- transaction_date 是经济事项发生日期；record_date 只是录入/原始记录日期，不能用于月度归属。
- actual/settled 表示已确认记录，planned 表示预计。交易日期在分析日次日及以后的 actual/settled 是“未来已确定”，不是截至分析时点已经发生的现金流或消费。
- 默认没有另选时间范围时，历史汇总截至当前自然月及分析时点；不得把之后月份的 EPF、投资调整、收入或支出提前计入当前资产和本月实绩。

二、必须分开三个观察口径
1. 消费发生：按 transaction_date 统计 income 与 expense；排除 transfer。信用卡消费计入刷卡消费发生的月份，不因为之后还款而再次计为支出。
2. 现金收付：只统计 report_group=cash 的账户真实流入流出。信用卡消费当月不产生现金流；现金账户转入信用账户的还款在付款月份计为现金流出。现金账户之间转账净额为零。
3. 信用负债：显示信用卡、PayLater、贷款等 report_group=credit 已确定的当前负债。全部日期的 actual/settled 可用于已锁定额度/已承诺负债；planned 只能作为情景预测，不得写成当前欠款。优先使用账户余额或已计算的信用负债字段，避免把同一交易再加一次。

三、分类规则
- 信用卡还款是 transfer，不是消费支出；不得同时计入“消费发生”和“现金收付”两次支出。
- 转入投资或退休账户是资产重新配置，不是消费；投资市值调整不是工资或经营收入。
- future actual/settled 与 future planned 必须分列：前者叫“未来已确定”，后者叫“预计”。两者都不能混入截至分析时点的本月实绩。
- 周期规则若已经生成对应 future_transactions，不得重复累计；只有尚未生成的月份才可用规则补足，并标记为推算。
- 现金预测以分析日日终现金为基线；income 与 expense 为非转账现金收付，transfers 为转账对现金账户的净变动，还卡不再重复计入 expense。
- 金额为零时保留记录但不影响合计；负数按代数方向处理，不可取绝对值后直接相加。
- 多币种优先使用 *_base 或已经折算的汇总；缺少报价时保留原币并标为未估值。unpriced_currencies 非空时，汇总只包含可估值部分。

四、分析方法
- 先核对关键合计能否由明细解释；若账户余额、月度汇总和交易明细不一致，列出差额与可能原因，不要擅自选择最有利的数字。
- 本月与上月比较时，同时考虑 current_month_elapsed_ratio；本月尚未结束时，不用不完整月份直接下结论。
- 预算监督按消费发生口径；偿还信用卡不会再次占用消费预算。
- 现金安全评估按现金收付口径与 cash_flow_projection；净资产评估才加入投资、退休和信用负债。
- 历史均值只能补足没有明确未来记录的月份，必须标为“估算”，并给出低/中/高置信度。

五、输出格式
使用简体中文、纯文字，不要 HTML 或代码块。金额以 base_currency 为前缀并保留 2 位小数。按以下顺序输出：

分析口径与数据质量
- 写明分析时点、货币、资料覆盖范围、关键缺口和总体置信度。

三口径摘要
- 消费发生：本月截至分析时点的收入、支出、结余；另列本月剩余日期的未来已确定与预计。
- 现金收付：本月真实流入、真实流出、净现金流，解释信用卡还款影响。
- 信用负债：当前已确定负债、未来已确定承诺、planned 情景影响；三者分列。

本月与上月
- 比较收入、消费、现金流和预算执行，说明当前月份完成比例。

资产与负债
- 说明现金、投资、退休、信用负债构成及集中度；投资转账不得当作消费。

未来推演
- 按未来月份分列“未来已确定”和“预计”，给出收入、消费、现金流、信用还款压力及月末现金。
- 指出最需要关注的 1-2 个月，并说明依据。

行动建议
- 给出 3-5 条具体、可执行且不重复的建议，每条引用月份、账户类别或金额区间。
''';

  AiAnalysisService({
    required this.gatewayUrl,
  });

  final String gatewayUrl;

  Future<String> generateAnalysis(
    FinanceRepository repository, {
    bool includePlanned = false,
    int monthCount = 6,
    int futureMonthCount = defaultFutureMonthCount,
  }) async {
    final data = buildRequestData(
      repository,
      includePlanned: includePlanned,
      monthCount: monthCount,
      futureMonthCount: futureMonthCount,
    );
    final prompt = buildAnalysisPrompt(data);
    final uri = Uri.parse('$gatewayUrl/api/analyze');

    const maxRetries = 2;
    Exception? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'data': data,
                'prompt': prompt,
              }),
            )
            .timeout(const Duration(seconds: 300));

        if (response.statusCode != 200) {
          throw Exception(
              'Gateway 返回 ${response.statusCode}: ${response.body}');
        }

        final result = jsonDecode(response.body);
        return result['summary'] as String;
      } on TimeoutException {
        lastError = Exception('请求超时（300秒）');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }

    throw AiNetworkException(
      '无法连接到 AI 网关\n\n'
      '请检查：\n'
      '1. 网关服务器是否运行中\n'
      '2. 手机网络是否正常\n'
      '3. 网关地址是否正确',
      originalError: lastError,
    );
  }

  static Map<String, dynamic> buildRequestData(
    FinanceRepository repository, {
    required bool includePlanned,
    required int monthCount,
    int futureMonthCount = defaultFutureMonthCount,
    DateTime? asOf,
  }) {
    if (monthCount < 1) throw ArgumentError.value(monthCount, 'monthCount');
    if (futureMonthCount < 0) {
      throw ArgumentError.value(futureMonthCount, 'futureMonthCount');
    }
    final now = (asOf ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final currentMonth = monthKeyFromDate(now);
    final lastMonth = monthKeyFromDate(DateTime(now.year, now.month - 1));
    final daysInCurrentMonth = DateTime(now.year, now.month + 1, 0).day;
    final historyMonthKeys = recentMonthKeys(count: monthCount, anchor: now);
    final futureMonthKeys = List.generate(
      futureMonthCount,
      (index) => monthKeyFromDate(DateTime(now.year, now.month + index + 1)),
    );
    final analysisMonthKeys = [
      ...historyMonthKeys,
      ...futureMonthKeys,
    ];
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final cutoffDate = tomorrow.subtract(const Duration(microseconds: 1));
    final historyStart = DateTime(now.year, now.month - monthCount + 1);
    final futureEndExclusive =
        DateTime(now.year, now.month + futureMonthCount + 1);
    CategoryReportIndex report(DateTime start, DateTime end) =>
        CategoryReportIndex(
          repository.categoryHierarchy,
          repository.transactions.where((t) =>
              !t.transactionDate.isBefore(start) &&
              t.transactionDate.isBefore(end)),
          hasRate: repository.hasExchangeRate,
          convertToBase: repository.convertToBase,
        );
    final occurred = report(historyStart, tomorrow);
    final upcoming = report(tomorrow, futureEndExclusive);

    final accounts = <Map<String, dynamic>>[];
    for (final group in ReportGroup.values) {
      for (final account in repository.accountsByGroup(group)) {
        final nativeBalance =
            repository.accountBalanceAt(account.id, cutoffDate);
        final balance = repository.tryConvertAmount(
            amount: nativeBalance,
            fromCurrency: account.currency,
            toCurrency: repository.baseCurrency);
        accounts.add({
          'name': account.name,
          'type': account.accountType.name,
          'report_group': account.effectiveReportGroup.name,
          'currency': account.currency,
          'balance': balance,
          'balance_base': balance,
          'native_balance': nativeBalance,
          'is_active': account.isActive,
          if (account.accountType == AccountType.creditCard)
            'all_date_committed_outstanding_native':
                repository.creditCardCommittedOutstandingBalance(account.id),
        });
      }
    }

    final cash = repository.actualCashFlowSummaryForMonth(currentMonth,
        cutoffDate: cutoffDate);
    final current =
        _monthlyRow(occurred, currentMonth, currentMonth, includePlanned);
    final previousReport = historyStart
            .isAfter(DateTime(now.year, now.month - 1))
        ? report(
            DateTime(now.year, now.month - 1), DateTime(now.year, now.month))
        : occurred;
    final previous =
        _monthlyRow(previousReport, lastMonth, currentMonth, includePlanned);
    final remainder =
        _monthlyRow(upcoming, currentMonth, currentMonth, true, future: true);
    final historyRows = [
      for (final key in historyMonthKeys)
        _monthlyRow(occurred, key, currentMonth, includePlanned),
    ];
    final futureMonthRows = [
      for (final key in futureMonthKeys)
        _monthlyRow(upcoming, key, currentMonth, true, future: true),
    ];
    final monthRows = [...historyRows, ...futureMonthRows];
    final expenseCategories = _categorySummary(
      occurred,
      type: CategoryType.expense,
      monthKeys: historyMonthKeys,
      includePlanned: includePlanned,
    );
    final incomeCategories = _categorySummary(
      occurred,
      type: CategoryType.income,
      monthKeys: historyMonthKeys,
      includePlanned: includePlanned,
    );
    final budgetsByMonth = {
      for (final monthKey in [currentMonth, ...futureMonthKeys])
        monthKey: _budgetRowsForMonth(repository, monthKey, tomorrow),
    };
    final budgets = budgetsByMonth[currentMonth] ?? const [];

    final goals = <Map<String, dynamic>>[];
    for (final goal in repository.assetGoalSummaries(cutoffDate: cutoffDate)) {
      goals.add({
        'name': goal.goal.name,
        'valuation_available': goal.valuationAvailable,
        'target': repository.tryConvertAmount(
            amount: goal.goal.targetAmount,
            fromCurrency: goal.goal.currency,
            toCurrency: repository.baseCurrency),
        'original_target': goal.goal.targetAmount,
        'original_currency': goal.goal.currency,
        'current': goal.valuationAvailable ? goal.currentAssets : null,
        'progress': goal.valuationAvailable
            ? (goal.progressRatio * 100).toStringAsFixed(1)
            : null,
        'is_reached': goal.valuationAvailable ? goal.isReached : null,
      });
    }

    final futureTransactions = _transactionsInWindow(
      repository,
      startInclusive: tomorrow,
      endExclusive: futureEndExclusive,
      limit: 120,
    );
    final recentActualTransactions = _transactionsInWindow(
      repository,
      startInclusive: historyStart,
      endExclusive: tomorrow,
      limit: 50,
      descending: true,
      actualOnly: true,
    );
    final recurringRules = repository.recurringTransactionRules
        .map(
          (rule) => _recurringRuleRow(
            repository,
            rule,
            now: now,
            futureMonthCount: futureMonthCount,
          ),
        )
        .toList();
    final cashFlowProjection = repository
        .futureCashFlowProjection(months: futureMonthCount + 1, asOf: now)
        .map(
          (item) => {
            'month': item.monthKey,
            'income': item.income,
            'expense': item.expense,
            'transfers': item.transfers,
            'net': item.net,
            'ending_cash': item.endingCash,
          },
        )
        .toList();
    final monthsWithRecords = {
      for (final item in repository.transactions)
        if (!item.transactionDate.isBefore(tomorrow) &&
            item.transactionDate.isBefore(futureEndExclusive))
          monthKeyFromDate(item.transactionDate),
    };
    final futureMonthsWithKnownData =
        futureMonthKeys.where(monthsWithRecords.contains).toList();
    final budgetRiskRows = _budgetRiskRows(budgetsByMonth);

    return {
      'schema_version': 3,
      'prompt_version': 'finance_compass_three_lenses_v3',
      'generated_at': now.toIso8601String(),
      'actual_through_date': _dateText(today),
      'base_currency': repository.baseCurrency,
      'unpriced_currencies': repository.unpricedCurrencies.toList()..sort(),
      'analysis_contract': {
        'actual': 'completed or settled records that affect real balances',
        'planned':
            'user-entered estimates that should not be treated as completed cash flow',
        'history_mode': includePlanned
            ? 'historical analysis_income/expense adds planned records dated through actual_through_date'
            : 'historical analysis_income/expense uses occurred actual/settled records',
        'future_mode':
            'future rows total confirmed_future and planned as two separate components',
        'cash_flow_projection':
            'known dated cash movements only; net = income minus expense plus signed cash transfers. No additional deduction for unrecorded bills',
        'consumption_occurrence':
            'income and expense by transaction_date; transfers and card repayments are excluded',
        'cash_settlement':
            'net movement of report_group=cash accounts; card purchase is recognized only when cash repayment occurs',
        'credit_commitment':
            'confirmed credit liabilities; all-date actual/settled may represent locked commitments, planned is scenario only',
        'future_actual':
            'confirmed event dated after actual_through_date; listed separately from occurred actuals',
        'recommended_source_order': [
          'current_month and last_month summaries',
          'current_month_remaining',
          'cash_flow_projection',
          'future_monthly_actual_planned',
          'future_transactions',
          'budgets_by_month',
          'recurring_transaction_rules',
          'recent_actual_transactions',
        ],
      },
      'data_mode': includePlanned ? 'all' : 'actual',
      'data_mode_note':
          'history and current_month run through actual_through_date; future planning rows distinguish confirmed events and estimates',
      'month_count': monthCount,
      'future_month_count': futureMonthCount,
      'current_month_key': currentMonth,
      'current_day_of_month': today.day,
      'days_in_current_month': daysInCurrentMonth,
      'current_month_elapsed_ratio':
          double.parse((today.day / daysInCurrentMonth).toStringAsFixed(2)),
      'history_months': historyMonthKeys,
      'future_months': futureMonthKeys,
      'analysis_months': analysisMonthKeys,
      'currency_priority': repository.currencyPriority,
      'exchange_rates_to_base': repository.exchangeRatesToBase,
      'accounts': accounts,
      'assets_by_group': {
        for (final group in ReportGroup.values)
          group.name: repository.displayTotalAssetsByGroup(group,
              cutoffDate: cutoffDate),
      },
      'total_assets': repository.totalAssetsAt(cutoffDate),
      'current_month': {
        ...current,
        'actual_cash_inflow': cash.inflow,
        'actual_cash_outflow': cash.outflow,
        'actual_cash_net': cash.net,
      },
      'current_month_remaining': remainder,
      'last_month': previous,
      'monthly_actual_planned': monthRows,
      'future_monthly_actual_planned': futureMonthRows,
      'expense_categories': expenseCategories,
      'income_categories': incomeCategories,
      'budgets': budgets,
      'budgets_by_month': budgetsByMonth,
      'goals': goals,
      'cash_flow_projection': cashFlowProjection,
      'future_transactions': futureTransactions,
      'recent_actual_transactions': recentActualTransactions,
      'recurring_transaction_rules': recurringRules,
      'budget_risks': budgetRiskRows,
      'data_quality': {
        'future_months_requested': futureMonthCount,
        'future_months_with_known_planned_data':
            futureMonthsWithKnownData.length,
        'future_months_missing_known_planned_data':
            futureMonthCount - futureMonthsWithKnownData.length,
        'future_months_with_known_planned_data_keys': futureMonthsWithKnownData,
        'future_transactions_count': futureTransactions.length,
        'recurring_rules_count': recurringRules.length,
        'recent_actual_transactions_count': recentActualTransactions.length,
        'budget_risk_count': budgetRiskRows.length,
      },
      'recent_months': historyRows,
      'analysis_notes': [
        'planned transactions are user-entered estimates, not completed cash flow',
        'future_transactions may already include generated recurring records',
        'recurring_transaction_rules explain fixed patterns and should not be double-counted when matching future planned transactions exist',
        'cash_flow_projection starts with end-of-day cash; transfers records signed net cash movement from transfers, including repayments. A same-currency cash-to-cash transfer nets to zero.',
      ],
    };
  }

  static String buildAnalysisPrompt(Map<String, dynamic> data) {
    final baseCurrency = data['base_currency'] ?? 'MYR';
    final futureMonthCount =
        data['future_month_count'] ?? defaultFutureMonthCount;
    return '''
$financeAnalysisSystemPrompt

请分析用户随后提供的 Finance Compass JSON，解释截至资料时间点的财务状态，并推演未来 $futureMonthCount 个月。若上传的是完整备份 JSON 而不是分析摘要，请直接按照上面的三口径规则从 accounts、transactions、budgets、asset_snapshots 和 recurring_transaction_rules 计算。

请特别注意：
1. base_currency 是 $baseCurrency，所有 *_base 或汇总金额都已折算到该货币。
2. 如果存在 analysis_contract，必须与上面的三口径规则一起遵守；如有冲突，以更严格地区分时间与状态的规则为准。
3. 不要把信用卡还款再次算成消费，也不要把刷卡月份的消费推迟到还款月份；分别放入消费发生与现金收付口径。
4. 以 generated_at/exported_at 的本地自然日为截止日，次日起的 actual/settled 必须标为“未来已确定”，不得混入截至该时点的实绩；planned 始终单列为预计。
5. recurring_transaction_rules 若已生成对应交易，不得重复计算。budgets_by_month 用于消费预算，cash_flow_projection 用于现金安全，两者不能互相替代。
6. 如果资料只有原始明细，先建立账户 ID 到 report_group 的映射，再处理转账两端；不得仅看交易 type 猜测现金流。
7. data_quality 或原始资料覆盖不足时，降低置信度并列出缺失项。

最后检查：同一信用卡消费是否只进入一次消费、同一还款是否只进入一次现金流、未来 EPF/投资调整是否没有提前进入当前资产。
''';
  }

  static String buildExternalAnalysisText(
    FinanceRepository repository, {
    int monthCount = 6,
    int futureMonthCount = defaultFutureMonthCount,
  }) {
    final prompt = buildAnalysisPrompt({
      'base_currency': repository.baseCurrency,
      'future_month_count': futureMonthCount,
    });
    return '''
$prompt

请在对话中上传 Finance Compass 导出的 JSON 文件，再根据上面的要求进行分析。
''';
  }

  static Map<String, dynamic> _monthlyRow(CategoryReportIndex index,
      String monthKey, String currentMonth, bool includePlanned,
      {bool future = false}) {
    final inflows = index.read(CategoryType.income, [monthKey]).all;
    final outflows = index.read(CategoryType.expense, [monthKey]).all;
    final actualIncome = future ? 0.0 : inflows.actual;
    final actualExpense = future ? 0.0 : outflows.actual;
    final income = inflows.actual + (includePlanned ? inflows.planned : 0);
    final expense = outflows.actual + (includePlanned ? outflows.planned : 0);
    return {
      'month': monthKey,
      'period': future
          ? 'future'
          : monthKey == currentMonth
              ? 'current'
              : 'past',
      'income': income,
      'expense': expense,
      'net': income - expense,
      'actual_income': actualIncome,
      'actual_expense': actualExpense,
      'actual_net': actualIncome - actualExpense,
      'confirmed_future_income': future ? inflows.actual : 0.0,
      'confirmed_future_expense': future ? outflows.actual : 0.0,
      'planned_income': inflows.planned,
      'planned_expense': outflows.planned,
      'planned_net': inflows.planned - outflows.planned,
      'total_known_income': inflows.actual + inflows.planned,
      'total_known_expense': outflows.actual + outflows.planned,
      'total_known_net':
          inflows.actual + inflows.planned - outflows.actual - outflows.planned,
      'analysis_income': income,
      'analysis_expense': expense,
      'analysis_net': income - expense,
      'transaction_count': inflows.actualCount +
          inflows.plannedCount +
          outflows.actualCount +
          outflows.plannedCount,
    };
  }

  static List<Map<String, dynamic>> _budgetRiskRows(
    Map<String, List<Map<String, dynamic>>> budgetsByMonth,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final entry in budgetsByMonth.entries) {
      for (final budget in entry.value) {
        final remaining = budget['remaining_after_committed'] as double?;
        if (remaining == null || remaining >= 0) {
          continue;
        }
        rows.add({
          'month': entry.key,
          'category': budget['category'],
          'category_id': budget['category_id'],
          'path': budget['path'],
          'budget': (budget['budget'] as num).toDouble(),
          'committed_spend': (budget['committed_spend'] as num).toDouble(),
          'over_budget_by': -remaining,
        });
      }
    }
    rows.sort(
      (a, b) => (b['over_budget_by'] as double)
          .compareTo(a['over_budget_by'] as double),
    );
    return rows.take(12).toList();
  }

  static List<Map<String, dynamic>> _categorySummary(
    CategoryReportIndex index, {
    required CategoryType type,
    required List<String> monthKeys,
    required bool includePlanned,
  }) {
    final divisor = monthKeys.length;
    final report = index.read(type, monthKeys);
    return report.rows().map((row) {
      final actual = row['actual'] as double;
      final planned = row['planned'] as double;
      final total = actual + (includePlanned ? planned : 0);
      return {
        ...row,
        'total': total,
        'actual_total': actual,
        'planned_total': planned,
        'monthly_avg': divisor <= 0 ? total : total / divisor,
      };
    }).toList()
      ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
  }

  static List<Map<String, dynamic>> _budgetRowsForMonth(
    FinanceRepository repository,
    String monthKey,
    DateTime tomorrow,
  ) {
    return repository.activeBudgetsForMonth(monthKey).map((budget) {
      final effective = repository.effectiveBudgetForMonth(budget, monthKey);
      final usage = repository.budgetUsageFor(budget.categoryId, monthKey);
      var actualSpent = 0.0;
      var futureConfirmed = 0.0;
      var actualValued = true;
      var futureValued = true;
      for (final entry in usage.transactions.where((t) => t.affectsBalance)) {
        final value = repository.tryConvertAmount(
            amount: entry.amount,
            fromCurrency: entry.currency,
            toCurrency: repository.baseCurrency);
        if (entry.transactionDate.isBefore(tomorrow)) {
          actualSpent += value ?? 0;
          actualValued = actualValued && value != null;
        } else {
          futureConfirmed += value ?? 0;
          futureValued = futureValued && value != null;
        }
      }
      final plannedSpent = usage.planned;
      final committed = actualSpent + futureConfirmed + plannedSpent;
      final limitValued =
          repository.budgetLimitIsValued(budget.categoryId, monthKey);
      final committedValued =
          actualValued && futureValued && usage.plannedValued;
      final complete = limitValued && committedValued;
      return {
        'category': _categoryName(repository, budget.categoryId),
        'category_id': budget.categoryId,
        'path': repository.categoryHierarchy
            .pathOf(budget.categoryId)
            .map((c) => c.name)
            .toList(),
        'original_amount': budget.amount,
        'original_currency': budget.currency,
        'valuation_complete': complete,
        'budget': limitValued ? effective : null,
        'spent': actualValued ? actualSpent : null,
        'actual_spent': actualValued ? actualSpent : null,
        'confirmed_future_spent': futureValued ? futureConfirmed : null,
        'planned_spent': usage.plannedValued ? plannedSpent : null,
        'committed_spend': committedValued ? committed : null,
        'remaining_after_actual':
            limitValued && actualValued ? effective - actualSpent : null,
        'remaining_after_committed': complete ? effective - committed : null,
        if (!complete)
          'priced_subtotals': {
            'effective_budget': effective,
            'actual_spent': actualSpent,
            'confirmed_future_spent': futureConfirmed,
            'planned_spent': plannedSpent,
          },
        'rollover_enabled': budget.rolloverEnabled,
        'alert_threshold': budget.alertThreshold,
      };
    }).toList();
  }

  static List<Map<String, dynamic>> _transactionsInWindow(
    FinanceRepository repository, {
    required DateTime startInclusive,
    required DateTime endExclusive,
    int limit = 80,
    bool descending = false,
    bool actualOnly = false,
  }) {
    final items = repository.transactions.where((transaction) {
      if (actualOnly && transaction.status == TransactionStatus.planned) {
        return false;
      }
      if (transaction.transactionDate.isBefore(startInclusive)) {
        return false;
      }
      if (!transaction.transactionDate.isBefore(endExclusive)) {
        return false;
      }
      return true;
    }).toList()
      ..sort(
        (a, b) => descending
            ? b.transactionDate.compareTo(a.transactionDate)
            : a.transactionDate.compareTo(b.transactionDate),
      );
    return items
        .take(limit)
        .map((item) => _transactionRow(repository, item))
        .toList();
  }

  static Map<String, dynamic> _transactionRow(
    FinanceRepository repository,
    FinanceTransaction transaction,
  ) {
    return {
      'date': _dateText(transaction.transactionDate),
      'month': monthKeyFromDate(transaction.transactionDate),
      'type': transaction.type.name,
      'status': transaction.status.name,
      'is_planned': transaction.status == TransactionStatus.planned,
      'is_recurring_instance': transaction.recurringRuleId != null,
      'recurring_rule_id': transaction.recurringRuleId,
      'account': _accountName(repository, transaction.accountId),
      'to_account': transaction.toAccountId == null
          ? null
          : _accountName(repository, transaction.toAccountId!),
      'category': _categoryName(repository, transaction.categoryId),
      'category_id': transaction.categoryId,
      'amount': transaction.amount,
      'currency': transaction.currency,
      'amount_base': repository.tryConvertAmount(
          amount: transaction.amount,
          fromCurrency: transaction.currency,
          toCurrency: repository.baseCurrency),
      'to_amount': transaction.toAmount,
      if (transaction.loanInstallmentNumber != null) ...{
        'loan_installment_number': transaction.loanInstallmentNumber,
        'loan_payment_amount':
            transaction.loanPaymentAmount ?? transaction.amount,
      },
      'to_currency': transaction.toCurrency,
      'description': transaction.description,
      'merchant': transaction.merchant,
    };
  }

  static Map<String, dynamic> _recurringRuleRow(
    FinanceRepository repository,
    RecurringTransactionRule rule, {
    required DateTime now,
    required int futureMonthCount,
  }) {
    return {
      'id': rule.id,
      'name': rule.name,
      'type': rule.type.name,
      'template_status': rule.status.name,
      'status_when_generated': TransactionStatus.planned.name,
      'is_active': rule.isActive,
      'account': _accountName(repository, rule.accountId),
      'to_account': rule.toAccountId == null
          ? null
          : _accountName(repository, rule.toAccountId!),
      'category': _categoryName(repository, rule.categoryId),
      'amount': rule.amount,
      'currency': rule.currency,
      'amount_base': repository.tryConvertAmount(
          amount: rule.amount,
          fromCurrency: rule.currency,
          toCurrency: repository.baseCurrency),
      'to_amount': rule.toAmount,
      if (rule.loanInstallmentNumber != null) ...{
        'loan_installment_number': rule.loanInstallmentNumber,
        'loan_payment_amount': rule.loanPaymentAmount ?? rule.amount,
      },
      'to_currency': rule.toCurrency,
      'interval_months': rule.intervalMonths,
      'start_date': _dateText(rule.startDate),
      'end_date': rule.endDate == null ? null : _dateText(rule.endDate!),
      'generated_month_keys': rule.generatedMonthKeys,
      'next_occurrences': _nextRecurringOccurrences(
        rule,
        now: now,
        futureMonthCount: futureMonthCount,
      ),
    };
  }

  static List<Map<String, dynamic>> _nextRecurringOccurrences(
    RecurringTransactionRule rule, {
    required DateTime now,
    required int futureMonthCount,
  }) {
    if (!rule.isActive) {
      return const [];
    }
    final today = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(now.year, now.month + futureMonthCount + 1, 0);
    final rows = <Map<String, dynamic>>[];
    for (final date in recurringDates(
        start: rule.startDate,
        intervalMonths: rule.intervalMonths,
        after: today,
        through: endDate,
        end: rule.endDate)) {
      final key = monthKeyFromDate(date);
      rows.add({
        'date': _dateText(date),
        'month': key,
        'already_generated_as_transaction':
            rule.generatedMonthKeys.contains(key)
      });
    }
    return rows;
  }

  static String _categoryName(
      FinanceRepository repository, String? categoryId) {
    return categoryId == null ? '未分类' : repository.categoryName(categoryId);
  }

  static String _accountName(FinanceRepository repository, String accountId) {
    return repository.accountName(accountId);
  }

  static String _dateText(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class AiNetworkException implements Exception {
  final String message;
  final Exception? originalError;
  AiNetworkException(this.message, {this.originalError});
  @override
  String toString() => message;
}
