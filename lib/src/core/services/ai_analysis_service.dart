import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/finance_repository.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/month_key.dart';
import '../utils/month_range.dart';

class AiAnalysisService {
  static const defaultFutureMonthCount = 6;

  static const financeAnalysisSystemPrompt = '''
你是一位专业、谨慎、重视时间边界与会计口径的个人财务分析师。你只能依据用户提供的 Finance Compass JSON 分析，不得把缺失资料当作零，也不得编造交易、收益率、利率或建议金额。

一、先确认资料与截止时间
- 兼容两类文件：含 analysis_contract 的分析摘要 JSON，以及含 format_version、accounts、transactions、budgets 的完整备份 JSON。若没有 analysis_contract，使用本提示词的规则自行计算。
- 以 generated_at 或 exported_at 作为分析时点；若两者都缺失，明确说明无法精确判断“截至今天”。
- transaction_date 是经济事项发生日期；record_date 只是录入/原始记录日期，不能用于月度归属。
- actual/settled 表示已确认记录，planned 表示预计。交易日期晚于分析时点的 actual/settled 是“未来已确定”，不是截至分析时点已经发生的现金流或消费。
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
- 金额为零时保留记录但不影响合计；负数按代数方向处理，不可取绝对值后直接相加。
- 多币种优先使用 *_base 或已经折算的汇总；否则按 exchange_rates_to_base 换算到 base_currency，并注明换算口径。

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
  }) {
    final now = DateTime.now();
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
    final cutoffDate = repository.currentMonthCutoffDate();

    final accounts = <Map<String, dynamic>>[];
    for (final group in ReportGroup.values) {
      for (final account in repository.accountsByGroup(group)) {
        final balance = repository.accountBalanceAtBase(account.id, cutoffDate);
        accounts.add({
          'name': account.name,
          'type': account.accountType.name,
          'report_group': account.reportGroup.name,
          'currency': account.currency,
          'balance': balance,
          'balance_base': balance,
          'native_balance': repository.accountBalanceAt(account.id, cutoffDate),
          'is_active': account.isActive,
        });
      }
    }

    final income = repository.totalIncomeForMonth(currentMonth);
    final expense = repository.totalExpenseForMonth(currentMonth);
    final plannedIncome = repository.plannedIncomeForMonth(currentMonth);
    final plannedExpense = repository.plannedExpenseForMonth(currentMonth);
    final displayIncome = includePlanned ? income + plannedIncome : income;
    final displayExpense = includePlanned ? expense + plannedExpense : expense;

    final lastActualIncome = repository.totalIncomeForMonth(lastMonth);
    final lastActualExpense = repository.totalExpenseForMonth(lastMonth);
    final lastPlannedIncome = repository.plannedIncomeForMonth(lastMonth);
    final lastPlannedExpense = repository.plannedExpenseForMonth(lastMonth);
    final lastIncome =
        lastActualIncome + (includePlanned ? lastPlannedIncome : 0);
    final lastExpense =
        lastActualExpense + (includePlanned ? lastPlannedExpense : 0);

    final monthRows = analysisMonthKeys
        .map(
          (monthKey) => _monthlyRow(
            repository,
            monthKey: monthKey,
            currentMonth: currentMonth,
            includePlanned: includePlanned,
          ),
        )
        .toList();
    final futureMonthRows = futureMonthKeys
        .map(
          (monthKey) => _monthlyRow(
            repository,
            monthKey: monthKey,
            currentMonth: currentMonth,
            includePlanned: true,
          ),
        )
        .toList();
    final recentMonthsForGateway = (includePlanned
            ? monthRows
            : monthRows.where((item) => item['period'] != 'future').toList())
        .map(
          (item) => {
            'month': item['month'],
            'income': item['analysis_income'],
            'expense': item['analysis_expense'],
            'net': item['analysis_net'],
            'period': item['period'],
            'actual_income': item['actual_income'],
            'actual_expense': item['actual_expense'],
            'planned_income': item['planned_income'],
            'planned_expense': item['planned_expense'],
          },
        )
        .where(
          (item) =>
              (item['income'] as double) != 0 ||
              (item['expense'] as double) != 0 ||
              item['period'] == 'future',
        )
        .toList();

    final categoryDivisor =
        monthCount + (includePlanned ? futureMonthCount : 0);
    final expenseCategories = _categorySummary(
      repository,
      type: CategoryType.expense,
      monthKeys: analysisMonthKeys,
      includePlanned: includePlanned,
      divisor: categoryDivisor,
    );
    final incomeCategories = _categorySummary(
      repository,
      type: CategoryType.income,
      monthKeys: analysisMonthKeys,
      includePlanned: includePlanned,
      divisor: categoryDivisor,
    );

    final budgetsByMonth = {
      for (final monthKey in [currentMonth, ...futureMonthKeys])
        monthKey: _budgetRowsForMonth(repository, monthKey),
    };
    final budgets = budgetsByMonth[currentMonth] ?? const [];

    final goals = <Map<String, dynamic>>[];
    for (final goal in repository.assetGoalSummaries()) {
      goals.add({
        'name': goal.goal.name,
        'target': goal.goal.targetAmount,
        'current': goal.currentAssets,
        'progress': (goal.progressRatio * 100).toStringAsFixed(1),
        'is_reached': goal.isReached,
      });
    }

    final futureTransactions = _transactionsInWindow(
      repository,
      startDateExclusive: today,
      endDateInclusive: DateTime(now.year, now.month + futureMonthCount + 1, 0),
      limit: 120,
    );
    final recentActualTransactions = _transactionsInWindow(
      repository,
      endDateInclusive: today,
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
        .futureCashFlowProjection(months: futureMonthCount + 1)
        .map(
          (item) => {
            'month': item.monthKey,
            'income': item.income,
            'expense': item.expense,
            'transfers': item.transfers,
            'net': item.net,
            'ending_cash_after_credit': item.endingCash,
          },
        )
        .toList();
    final futureMonthsWithKnownData = futureMonthRows
        .where((item) => _monthHasKnownFutureData(item))
        .map((item) => item['month'])
        .toList();
    final budgetRiskRows = _budgetRiskRows(budgetsByMonth);

    return {
      'schema_version': 3,
      'prompt_version': 'finance_compass_three_lenses_v3',
      'generated_at': DateTime.now().toIso8601String(),
      'base_currency': repository.baseCurrency,
      'analysis_contract': {
        'actual': 'completed or settled records that affect real balances',
        'planned':
            'user-entered estimates that should not be treated as completed cash flow',
        'analysis_income': includePlanned
            ? 'actual_income plus planned_income'
            : 'actual_income only',
        'analysis_expense': includePlanned
            ? 'actual_expense plus planned_expense'
            : 'actual_expense only',
        'cash_flow_projection':
            'cash and credit pressure projection; this is not total net worth',
        'consumption_occurrence':
            'income and expense by transaction_date; transfers and card repayments are excluded',
        'cash_settlement':
            'net movement of report_group=cash accounts; card purchase is recognized only when cash repayment occurs',
        'credit_commitment':
            'confirmed credit liabilities; all-date actual/settled may represent locked commitments, planned is scenario only',
        'future_actual':
            'confirmed future event, not cash flow or consumption already completed as of generated_at',
        'recommended_source_order': [
          'current_month and last_month summaries',
          'cash_flow_projection',
          'future_monthly_actual_planned',
          'future_transactions',
          'budgets_by_month',
          'recurring_transaction_rules',
          'recent_actual_transactions',
        ],
      },
      'data_mode': includePlanned ? 'all' : 'actual',
      'data_mode_note': includePlanned
          ? 'analysis fields include actual plus planned records; actual/planned remain separated'
          : 'analysis fields use actual records only; future planned data is still included in dedicated future fields',
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
        'cash': repository.totalAssetsByGroup(ReportGroup.cash),
        'credit': repository.totalAssetsByGroup(ReportGroup.credit),
        'investment': repository.totalAssetsByGroup(ReportGroup.investment),
        'retirement': repository.totalAssetsByGroup(ReportGroup.retirement),
      },
      'total_assets': repository.totalAssets(),
      'current_month': {
        'income': displayIncome,
        'expense': displayExpense,
        'net': displayIncome - displayExpense,
        'actual_income': income,
        'actual_expense': expense,
        'actual_net': income - expense,
        'planned_income': plannedIncome,
        'planned_expense': plannedExpense,
        'planned_net': plannedIncome - plannedExpense,
      },
      'last_month': {
        'income': lastIncome,
        'expense': lastExpense,
        'net': lastIncome - lastExpense,
        'actual_income': lastActualIncome,
        'actual_expense': lastActualExpense,
        'planned_income': lastPlannedIncome,
        'planned_expense': lastPlannedExpense,
      },
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
      'recent_months': recentMonthsForGateway,
      'analysis_notes': [
        'planned transactions are user-entered estimates, not completed cash flow',
        'future_transactions may already include generated recurring records',
        'recurring_transaction_rules explain fixed patterns and should not be double-counted when matching future planned transactions exist',
        'cash_flow_projection focuses on cash and credit groups, while total_assets includes investment and retirement groups',
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
4. 日期晚于 generated_at/exported_at 的 actual/settled 必须标为“未来已确定”，不得混入截至该时点的实绩；planned 始终单列为预计。
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

  static Map<String, dynamic> _monthlyRow(
    FinanceRepository repository, {
    required String monthKey,
    required String currentMonth,
    required bool includePlanned,
  }) {
    final actualIncome = repository.totalIncomeForMonth(monthKey);
    final actualExpense = repository.totalExpenseForMonth(monthKey);
    final plannedIncome = repository.plannedIncomeForMonth(monthKey);
    final plannedExpense = repository.plannedExpenseForMonth(monthKey);
    final analysisIncome = actualIncome + (includePlanned ? plannedIncome : 0);
    final analysisExpense =
        actualExpense + (includePlanned ? plannedExpense : 0);
    return {
      'month': monthKey,
      'period': monthKey.compareTo(currentMonth) < 0
          ? 'past'
          : monthKey == currentMonth
              ? 'current'
              : 'future',
      'actual_income': actualIncome,
      'actual_expense': actualExpense,
      'actual_net': actualIncome - actualExpense,
      'planned_income': plannedIncome,
      'planned_expense': plannedExpense,
      'planned_net': plannedIncome - plannedExpense,
      'total_known_income': actualIncome + plannedIncome,
      'total_known_expense': actualExpense + plannedExpense,
      'total_known_net':
          actualIncome + plannedIncome - actualExpense - plannedExpense,
      'analysis_income': analysisIncome,
      'analysis_expense': analysisExpense,
      'analysis_net': analysisIncome - analysisExpense,
    };
  }

  static bool _monthHasKnownFutureData(Map<String, dynamic> row) {
    return (row['planned_income'] as double) != 0 ||
        (row['planned_expense'] as double) != 0 ||
        (row['actual_income'] as double) != 0 ||
        (row['actual_expense'] as double) != 0;
  }

  static List<Map<String, dynamic>> _budgetRiskRows(
    Map<String, List<Map<String, dynamic>>> budgetsByMonth,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final entry in budgetsByMonth.entries) {
      for (final budget in entry.value) {
        final remaining =
            (budget['remaining_after_committed'] as num).toDouble();
        if (remaining >= 0) {
          continue;
        }
        rows.add({
          'month': entry.key,
          'category': budget['category'],
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
    FinanceRepository repository, {
    required CategoryType type,
    required List<String> monthKeys,
    required bool includePlanned,
    required int divisor,
  }) {
    final actual = _categoryTotals(
      repository,
      type: type,
      monthKeys: monthKeys,
      includePlanned: false,
    );
    final planned = _categoryTotals(
      repository,
      type: type,
      monthKeys: monthKeys,
      plannedOnly: true,
    );
    final categoryIds = <String>{...actual.keys, ...planned.keys};
    final rows = <Map<String, dynamic>>[];
    for (final categoryId in categoryIds) {
      final actualTotal = actual[categoryId] ?? 0;
      final plannedTotal = planned[categoryId] ?? 0;
      final total = actualTotal + (includePlanned ? plannedTotal : 0);
      if (total == 0 && plannedTotal == 0 && actualTotal == 0) {
        continue;
      }
      rows.add({
        'name': _categoryName(repository, categoryId),
        'total': total,
        'actual_total': actualTotal,
        'planned_total': plannedTotal,
        'monthly_avg': divisor <= 0 ? total : total / divisor,
      });
    }
    rows.sort(
      (a, b) => (b['total'] as double).compareTo(a['total'] as double),
    );
    return rows;
  }

  static Map<String, double> _categoryTotals(
    FinanceRepository repository, {
    required CategoryType type,
    required List<String> monthKeys,
    bool includePlanned = true,
    bool plannedOnly = false,
  }) {
    final allowedIds = repository.categories
        .where((category) => category.type == type)
        .map((category) => category.id)
        .toSet();
    final totals = <String, double>{};
    for (final transaction in repository.transactions) {
      final categoryId = transaction.categoryId;
      if (categoryId == null || !allowedIds.contains(categoryId)) {
        continue;
      }
      if (!monthKeys.contains(monthKeyFromDate(transaction.transactionDate))) {
        continue;
      }
      if (plannedOnly && transaction.status != TransactionStatus.planned) {
        continue;
      }
      if (!includePlanned && transaction.status == TransactionStatus.planned) {
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
      totals[categoryId] = (totals[categoryId] ?? 0) +
          repository.transactionAmountInBase(transaction);
    }
    return totals;
  }

  static List<Map<String, dynamic>> _budgetRowsForMonth(
    FinanceRepository repository,
    String monthKey,
  ) {
    return repository.activeBudgetsForMonth(monthKey).map((budget) {
      final effective = repository.effectiveBudgetForMonth(budget, monthKey);
      final actualSpent =
          repository.expenseTotalForCategory(budget.categoryId, monthKey);
      final plannedSpent = repository.plannedExpenseTotalForCategory(
        budget.categoryId,
        monthKey,
      );
      final committed = actualSpent + plannedSpent;
      return {
        'category': _categoryName(repository, budget.categoryId),
        'budget': effective,
        'spent': actualSpent,
        'actual_spent': actualSpent,
        'planned_spent': plannedSpent,
        'committed_spend': committed,
        'remaining_after_actual': effective - actualSpent,
        'remaining_after_committed': effective - committed,
        'rollover_enabled': budget.rolloverEnabled,
        'alert_threshold': budget.alertThreshold,
      };
    }).toList();
  }

  static List<Map<String, dynamic>> _transactionsInWindow(
    FinanceRepository repository, {
    DateTime? startDateExclusive,
    required DateTime endDateInclusive,
    int limit = 80,
    bool descending = false,
    bool actualOnly = false,
  }) {
    final items = repository.transactions.where((transaction) {
      if (actualOnly && transaction.status == TransactionStatus.planned) {
        return false;
      }
      if (startDateExclusive != null &&
          !transaction.transactionDate.isAfter(startDateExclusive)) {
        return false;
      }
      if (transaction.transactionDate.isAfter(endDateInclusive)) {
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
      'amount': transaction.amount,
      'currency': transaction.currency,
      'amount_base': repository.transactionAmountInBase(transaction),
      'to_amount': transaction.toAmount,
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
      'status_when_generated': rule.status.name,
      'is_active': rule.isActive,
      'account': _accountName(repository, rule.accountId),
      'to_account': rule.toAccountId == null
          ? null
          : _accountName(repository, rule.toAccountId!),
      'category': _categoryName(repository, rule.categoryId),
      'amount': rule.amount,
      'currency': rule.currency,
      'amount_base': repository.convertToBase(rule.amount, rule.currency),
      'to_amount': rule.toAmount,
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
    var cursor = DateTime(
      rule.startDate.year,
      rule.startDate.month,
      rule.startDate.day,
    );
    var guard = 0;
    while (!cursor.isAfter(endDate) && guard++ < 240) {
      if (cursor.isAfter(today) &&
          (rule.endDate == null || !cursor.isAfter(rule.endDate!))) {
        final occurrenceMonthKey = monthKeyFromDate(cursor);
        rows.add({
          'date': _dateText(cursor),
          'month': occurrenceMonthKey,
          'already_generated_as_transaction':
              rule.generatedMonthKeys.contains(occurrenceMonthKey),
        });
      }
      cursor = DateTime(
        cursor.year,
        cursor.month + rule.intervalMonths,
        cursor.day,
      );
    }
    return rows;
  }

  static String _categoryName(
      FinanceRepository repository, String? categoryId) {
    if (categoryId == null) {
      return '未分类';
    }
    for (final category in repository.categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }
    return '未命名类别';
  }

  static String _accountName(FinanceRepository repository, String accountId) {
    for (final account in repository.accounts) {
      if (account.id == accountId) {
        return account.name;
      }
    }
    return '未知账户';
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
