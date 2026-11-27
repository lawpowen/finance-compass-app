import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart' show moneyDisplayParts;
import '../../core/utils/month_key.dart';
import '../ai/ai_chat_screen.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_donut.dart';

enum _ReportOverviewRange { yearToDate, last12Months, allTime }

const _periodHelp = '日期范围影响净资产趋势与变化、实际现金流和支出排行。'
    '资产构成、本月预算与投资使用各自的本月末数据。';
const _snapshotHelp = '这里显示本月末的资产构成、本月预算和投资数据。'
    '更改上方日期范围不会改变本月末快照。';
const _netWorthHelp = '净资产按基础币汇总各账户的余额，包含负债。'
    '变化是月末净资产与期初净资产之差。期初为零或负数时，变化率不适用。';
const _cashFlowHelp = '统计现金账户的实际收付。信用卡和贷款还款按全额计入，'
    '刷卡消费在还款前不算现金流出，预计交易不计入。';
const _spendingHelp = '按交易发生日统计已分类支出，包含刷卡消费，'
    '按一级分类汇总后代，净退款单列为负数。占比按正净支出分类计算，不含预计交易。';
const _assetHelp = '环形图按基础币汇总现金、投资和退休账户的正余额。'
    '溢付余额计入总资产，信用卡溢缴款单独列示。负债包含透支及信用卡、贷款欠款。';
const _budgetHelp = '已用比例包含本月实际支出与预计支出。'
    '进度条的实色段代表实际支出，斜纹段代表预计支出。';
const _investmentHelp = '资金净收益等于月末市值减净投入。净投入大于零时按净投入计算收益率。';

/// Self-contained report overview.
///
/// The selected range drives the net-worth change and trend, the actual cash
/// flow totals and trend, and the transaction-occurrence expense category
/// ranking. Asset composition, this month's budget and investment valuation
/// are point-in-time figures and are labelled with their own date instead.
class ReportsV2Screen extends StatefulWidget {
  const ReportsV2Screen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  State<ReportsV2Screen> createState() => _ReportsV2ScreenState();
}

class _ReportsV2ScreenState extends State<ReportsV2Screen> {
  _ReportOverviewRange range = _ReportOverviewRange.yearToDate;
  bool _showAllExpenseCategories = false;
  _ReportsViewData? _cachedData;

  FinanceRepository get repository => widget.repository;
  String _money(double value, {int decimals = 2}) => compassMoney(value,
      currency: repository.baseCurrency, decimals: decimals);

  String _changeAmount(double value, {int decimals = 2}) => _signedMoney(value,
      currency: repository.baseCurrency, decimals: decimals);

  _ReportsViewData _viewDataFor(DateTime now) {
    final todayKey = now.year * 10000 + now.month * 100 + now.day;
    final cached = _cachedData;
    if (cached != null &&
        identical(cached.repository, repository) &&
        cached.range == range &&
        cached.todayKey == todayKey) {
      return cached;
    }

    final currentMonthKey = monthKeyFromDate(now);
    final cutoff = repository.currentMonthCutoffDate();
    final asOfLabel = '截至 ${cutoff.month}月${cutoff.day}日（本月末）';

    final hasAccounts = repository.accounts.isNotEmpty;
    final sheet = repository.balanceSheetAt(cutoff);
    final netWorth = sheet.netWorth;
    final allHistory = repository.totalAssetHistory(cutoffDate: cutoff);
    final firstHistoryDate = allHistory.isEmpty ? now : allHistory.first.date;
    final rangeStart = switch (range) {
      _ReportOverviewRange.yearToDate => DateTime(now.year, 1, 1),
      _ReportOverviewRange.last12Months =>
        DateTime(now.year, now.month - 11, 1),
      _ReportOverviewRange.allTime =>
        DateTime(firstHistoryDate.year, firstHistoryDate.month, 1),
    };
    final monthKeys = _monthKeysBetween(rangeStart, now);
    final baselineDate =
        DateTime(rangeStart.year, rangeStart.month, 0, 23, 59, 59, 999);
    final startingNetWorth = repository.totalAssetsAt(baselineDate);
    final growth = netWorth - startingNetWorth;
    final growthRate = startingNetWorth > 0 ? growth / startingNetWorth : null;
    final rangePoints = allHistory
        .where((point) =>
            !point.date.isBefore(rangeStart) && point.label != currentMonthKey)
        .toList();
    final chartValues = <double>[
      startingNetWorth,
      ...rangePoints.map((point) => point.totalAssets),
      netWorth,
    ];
    final chartLabels = <String>[
      '期初',
      ...rangePoints.map((point) => point.label),
      '本月末',
    ];
    final cashFlow = repository.actualCashFlowSummaryForMonths(monthKeys);
    final monthlyCashFlows = [
      for (final key in monthKeys)
        repository.actualCashFlowSummaryForMonth(key),
    ];
    final monthlyNet = [
      for (final summary in monthlyCashFlows) summary.net,
    ];
    final monthLabels = [
      for (final key in monthKeys) _monthLabel(key),
    ];
    final hasCashFlow = cashFlow.inflow != 0 || cashFlow.outflow != 0;
    final savingsRateLabel = cashFlow.inflow > 0
        ? '${(cashFlow.net / cashFlow.inflow * 100).toStringAsFixed(0)}%'
        : '—';
    final averageMonthlyNet = cashFlow.net / monthKeys.length;
    final breakdown =
        repository.categoryReports.read(CategoryType.expense, monthKeys);
    final rankedExpenses = [
      for (final id in breakdown.roots)
        if (breakdown.subtree[id]!.pricedActualCount > 0)
          MapEntry(id, breakdown.subtree[id]!.actual),
    ]..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        if (byAmount != 0) return byAmount;
        final byName = repository
            .categoryName(a.key)
            .compareTo(repository.categoryName(b.key));
        return byName != 0 ? byName : a.key.compareTo(b.key);
      });
    final expenseTotal =
        rankedExpenses.fold(0.0, (double sum, e) => sum + e.value);
    final positiveExpenseTotal = rankedExpenses.fold(
        0.0, (double sum, e) => sum + math.max(0.0, e.value));
    final maxExpenseAmount = rankedExpenses.fold(
        0.0, (double maxAmount, e) => math.max(maxAmount, e.value.abs()));
    final unclassified = breakdown.direct[null];
    final unclassifiedActual =
        unclassified != null && unclassified.pricedActualCount > 0
            ? unclassified.actual
            : null;

    final cash = sheet.assetsIn(ReportGroup.cash);
    final investment = sheet.assetsIn(ReportGroup.investment);
    final retirement = sheet.assetsIn(ReportGroup.retirement);
    final debt = sheet.liabilities;
    final cardCredit = sheet.cardCredit;
    final positiveTotal = sheet.assets;
    final hasComposition = positiveTotal > 0 || debt > 0 || cardCredit > 0;
    final budget = repository.totalEffectiveBudgetForMonth(currentMonthKey);
    final budgetActual = repository.totalBudgetExpenseForMonth(currentMonthKey);
    final budgetPlanned =
        repository.totalPlannedBudgetExpenseForMonth(currentMonthKey);
    final budgetUsed = budgetActual + budgetPlanned;
    final budgetRate = budget <= 0 ? 0.0 : budgetUsed / budget;
    final budgetRemaining = budget - budgetUsed;
    final investmentAccounts = repository.investmentAccounts();
    var marketValue = 0.0;
    var remainingCost = 0.0;
    for (final account in investmentAccounts) {
      marketValue += repository.accountBalanceAtBase(account.id, cutoff);
      remainingCost += repository.convertToBase(
        repository.remainingCostBasisForAccount(account.id, upToDate: cutoff),
        account.currency,
      );
    }
    final unrealizedPnl = marketValue - remainingCost;
    final hasCost = remainingCost > 0;

    final rangeLabel = switch (range) {
      _ReportOverviewRange.yearToDate => '${now.year}年至今',
      _ReportOverviewRange.last12Months => '最近12个月',
      _ReportOverviewRange.allTime => '全部时间',
    };
    final periodLabel = monthKeys.length == 1
        ? _monthLabel(monthKeys.first)
        : '${_monthLabel(monthKeys.first)} – ${_monthLabel(monthKeys.last)}'
            ' · ${monthKeys.length} 个月';
    final shareText = [
      'Finance Compass 报表 · $rangeLabel（$periodLabel）',
      if (repository.unpricedCurrencies.isNotEmpty)
        '未计入缺少汇率的金额：${repository.unpricedCurrencies.join('、')}',
      '月末净资产 ${_money(netWorth)}（${cutoff.month}月${cutoff.day}日）',
      '$rangeLabel净资产变化 ${_changeAmount(growth)}',
      hasCashFlow
          ? '$rangeLabel实际现金净流入 ${_changeAmount(cashFlow.net)}'
              '（流入 ${_money(cashFlow.inflow)}'
              ' / 流出 ${_money(cashFlow.outflow)}）'
          : '$rangeLabel没有实际现金流记录',
    ].join('\n');

    return _cachedData = _ReportsViewData(
      repository: repository,
      range: range,
      todayKey: todayKey,
      currentMonthKey: currentMonthKey,
      cutoff: cutoff,
      asOfLabel: asOfLabel,
      hasAccounts: hasAccounts,
      netWorth: netWorth,
      monthKeys: monthKeys,
      startingNetWorth: startingNetWorth,
      growth: growth,
      growthRate: growthRate,
      chartValues: chartValues,
      chartLabels: chartLabels,
      cashFlow: cashFlow,
      monthlyNet: monthlyNet,
      monthLabels: monthLabels,
      hasCashFlow: hasCashFlow,
      savingsRateLabel: savingsRateLabel,
      averageMonthlyNet: averageMonthlyNet,
      rankedExpenses: rankedExpenses,
      expenseTotal: expenseTotal,
      positiveExpenseTotal: positiveExpenseTotal,
      unclassifiedActual: unclassifiedActual,
      unpricedExpenses: breakdown.all.unpricedActual,
      maxExpenseAmount: maxExpenseAmount,
      cash: cash,
      investment: investment,
      retirement: retirement,
      debt: debt,
      cardCredit: cardCredit,
      loanCredit: sheet.loanCredit,
      positiveTotal: positiveTotal,
      hasComposition: hasComposition,
      budget: budget,
      budgetActual: budgetActual,
      budgetPlanned: budgetPlanned,
      budgetUsed: budgetUsed,
      budgetRate: budgetRate,
      budgetRemaining: budgetRemaining,
      investmentAccounts: investmentAccounts,
      marketValue: marketValue,
      remainingCost: remainingCost,
      unrealizedPnl: unrealizedPnl,
      hasCost: hasCost,
      rangeLabel: rangeLabel,
      periodLabel: periodLabel,
      shareText: shareText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final data = _viewDataFor(now);
    final currentMonthKey = data.currentMonthKey;
    final cutoff = data.cutoff;
    final asOfLabel = data.asOfLabel;
    final hasAccounts = data.hasAccounts;
    final netWorth = data.netWorth;
    final monthKeys = data.monthKeys;
    final startingNetWorth = data.startingNetWorth;
    final growth = data.growth;
    final growthRate = data.growthRate;
    final chartValues = data.chartValues;
    final chartLabels = data.chartLabels;
    final cashFlow = data.cashFlow;
    final monthlyNet = data.monthlyNet;
    final monthLabels = data.monthLabels;
    final hasCashFlow = data.hasCashFlow;
    final savingsRateLabel = data.savingsRateLabel;
    final averageMonthlyNet = data.averageMonthlyNet;
    final rankedExpenses = data.rankedExpenses;
    final expenseTotal = data.expenseTotal;
    final displayedExpenses = _showAllExpenseCategories
        ? rankedExpenses
        : rankedExpenses.take(5).toList();
    final maxExpenseAmount = data.maxExpenseAmount;
    final cash = data.cash;
    final investment = data.investment;
    final retirement = data.retirement;
    final debt = data.debt;
    final cardCredit = data.cardCredit;
    final positiveTotal = data.positiveTotal;
    final hasComposition = data.hasComposition;
    final assetColors = financeDonutSeries(context);
    final budget = data.budget;
    final budgetActual = data.budgetActual;
    final budgetPlanned = data.budgetPlanned;
    final budgetUsed = data.budgetUsed;
    final budgetRate = data.budgetRate;
    final budgetRemaining = data.budgetRemaining;
    final investmentAccounts = data.investmentAccounts;
    final marketValue = data.marketValue;
    final remainingCost = data.remainingCost;
    final unrealizedPnl = data.unrealizedPnl;
    final hasCost = data.hasCost;
    final rangeLabel = data.rangeLabel;
    final periodLabel = data.periodLabel;
    final shareText = data.shareText;
    final header = CompassPageHeader(
      title: '报表',
      actions: [
        const AiChatEntryButton(),
        PopupMenuButton<_ReportOverviewRange>(
          initialValue: range,
          tooltip: '选择报表范围',
          onSelected: (value) => setState(() => range = value),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _ReportOverviewRange.yearToDate,
              child: Text('今年至今'),
            ),
            PopupMenuItem(
              value: _ReportOverviewRange.last12Months,
              child: Text('最近 12 个月'),
            ),
            PopupMenuItem(
              value: _ReportOverviewRange.allTime,
              child: Text('全部时间'),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: financePaletteOf(context).border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text(rangeLabel),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '分享所选期间报表',
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              text: shareText,
              subject: 'Finance Compass $rangeLabel 报表',
            ),
          ),
          icon: const Icon(Icons.ios_share_rounded),
        ),
      ],
    );
    final period = Text(
      periodLabel,
      key: const Key('reports-period-label'),
      style: textTheme.bodySmall,
    );
    List<Widget> netWorthSection({required bool wide}) => [
          if (wide)
            _SectionHeader(
              title: '净资产趋势',
              scope: '月末净资产 · ${cutoff.month}月${cutoff.day}日',
              helpMessage: _netWorthHelp,
            )
          else
            CompassHelpHeading(
              title: Text(
                '月末净资产 · ${cutoff.month}月${cutoff.day}日',
                style: textTheme.bodySmall,
              ),
              label: '净资产趋势',
              message: _netWorthHelp,
            ),
          const SizedBox(height: 4),
          Text(
            compassMoney(
              netWorth,
              currency: repository.baseCurrency,
              decimals: 0,
            ),
            key: const Key('reports-net-worth'),
            style: TextStyle(
              color: moneyDisplayParts(netWorth, decimals: 0).sign < 0
                  ? financePaletteOf(context).expense
                  : financePaletteOf(context).textPrimary,
              fontSize: 31,
              fontWeight: FontWeight.w700,
              fontFeatures: compassTabularFigures,
            ),
          ),
          const SizedBox(height: 4),
          if (!hasAccounts)
            Text(
              '尚未添加账户',
              style: textTheme.bodySmall,
            )
          else ...[
            Text.rich(
              TextSpan(
                text: '$rangeLabel 变化 ',
                children: [
                  TextSpan(
                    text: _changeAmount(growth, decimals: 0),
                    style: TextStyle(
                      color: _signColor(context, growth, decimals: 0),
                      fontWeight: FontWeight.w600,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: growthRate == null ? '—' : _signedPercent(growthRate),
                    style: TextStyle(
                      color: _signColor(context, growth, decimals: 0),
                      fontWeight: FontWeight.w600,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                ],
              ),
              key: const Key('reports-net-worth-change'),
            ),
            const SizedBox(height: 12),
            Stack(
              children: [
                Padding(
                  padding: wide
                      ? const EdgeInsets.fromLTRB(2, 4, 2, 8)
                      : const EdgeInsets.fromLTRB(26, 16, 4, 12),
                  child: CompassAreaChart(
                    key: const Key('reports-net-worth-trend'),
                    values: chartValues,
                    height: wide ? 160 : 176,
                    labels: chartLabels,
                    formatValue: (value) => compassMoney(
                      value,
                      currency: repository.baseCurrency,
                      decimals: 0,
                    ),
                    showMinMaxLabels: true,
                  ),
                ),
                if (!wide)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Text(
                      '本月末  ${_money(netWorth, decimals: 0)}',
                      style: TextStyle(
                        color: financePaletteOf(context).seed,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  wide
                      ? '期初 ${_money(startingNetWorth, decimals: 0)}'
                      : '${_monthLabel(monthKeys.first)}期初',
                  style: const TextStyle(fontSize: 10),
                ),
                const Text('本月末', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ];
    const cashFlowHeading = _SectionHeader(
      title: '实际现金流',
      helpMessage: _cashFlowHelp,
    );
    Widget cashFlowContent({required bool wide}) => !hasCashFlow
        ? Text(
            '所选期间没有实际现金流记录',
            style: textTheme.bodySmall,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: '流入',
                      value: compassMoney(
                        cashFlow.inflow,
                        currency: repository.baseCurrency,
                      ),
                      valueKey: const Key('reports-cash-inflow'),
                      color: financePaletteOf(context).income,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '流出',
                      value: compassMoney(
                        cashFlow.outflow,
                        currency: repository.baseCurrency,
                      ),
                      valueKey: const Key('reports-cash-outflow'),
                      color: financePaletteOf(context).expense,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '净流入',
                      value: _changeAmount(cashFlow.net),
                      valueKey: const Key('reports-cash-net'),
                      color: _signColor(context, cashFlow.net),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _NetFlowLine(
                key: const Key('reports-cash-flow-trend'),
                values: monthlyNet,
                monthLabels: monthLabels,
                baseCurrency: repository.baseCurrency,
                height: wide ? 160 : 64,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _monthLabel(monthKeys.first),
                    style: const TextStyle(fontSize: 10),
                  ),
                  Text(
                    _monthLabel(monthKeys.last),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '现金结余率 $savingsRateLabel · 月均净流入 '
                '${_changeAmount(averageMonthlyNet, decimals: 0)}',
                style: textTheme.bodySmall?.copyWith(
                  fontFeatures: compassTabularFigures,
                ),
              ),
            ],
          );
    final spendingHeading = _SectionHeader(
      title: _showAllExpenseCategories && rankedExpenses.length > 5
          ? '支出分类排行 · 全部 ${rankedExpenses.length}'
          : '支出分类排行 · 前 5',
      helpLabel: '支出分类排行',
      helpMessage: _spendingHelp,
    );
    Widget spendContent({required bool wide}) => displayedExpenses.isEmpty &&
            data.unclassifiedActual == null &&
            data.unpricedExpenses.isEmpty
        ? Text(
            '所选期间没有已分类支出',
            style: textTheme.bodySmall,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) const _ExpenseTableHeader(),
              for (var index = 0; index < displayedExpenses.length; index++)
                _CategoryRankRow(
                  index: index,
                  name: repository.categoryName(displayedExpenses[index].key),
                  amount: displayedExpenses[index].value,
                  currency: repository.baseCurrency,
                  maxAmount: maxExpenseAmount,
                  share: displayedExpenses[index].value <= 0 ||
                          data.positiveExpenseTotal <= 0
                      ? null
                      : displayedExpenses[index].value /
                          data.positiveExpenseTotal,
                  wide: wide,
                ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    data.unpricedExpenses.isNotEmpty && rankedExpenses.isEmpty
                        ? '已分类支出暂无可折算金额'
                        : '已分类支出合计 ${_money(expenseTotal)}'
                            '${data.unpricedExpenses.isEmpty ? '' : '（部分折算）'}'
                            '${rankedExpenses.length > 5 ? ' · 共 ${rankedExpenses.length} 个分类' : ''}',
                    key: const Key('reports-category-total'),
                    style: textTheme.bodySmall?.copyWith(
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                  for (final entry in data.unpricedExpenses.entries)
                    Text(
                        '未折算 ${compassMoney(entry.value, currency: entry.key)}'),
                  if (data.unclassifiedActual case final unclassified?) ...[
                    Text('未分类支出 ${_money(unclassified)}',
                        key: const Key('reports-unclassified-total')),
                    Text('支出净额 ${_money(expenseTotal + unclassified)}',
                        key: const Key('reports-all-expense-total')),
                  ],
                  if (rankedExpenses.length > 5)
                    TextButton(
                      key: const Key('reports-toggle-all-categories'),
                      onPressed: () => setState(
                        () => _showAllExpenseCategories =
                            !_showAllExpenseCategories,
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _showAllExpenseCategories
                            ? '收起至前 5'
                            : '展开全部 ${rankedExpenses.length} 个分类',
                      ),
                    ),
                ],
              ),
            ],
          );
    Widget assetsSection({required bool wide}) => hasComposition
        ? FinanceDonutPanel(
            key: const Key('reports-asset-composition'),
            title: '资产构成',
            titleHelp: _assetHelp,
            totalLabel: '总资产',
            totalValue: compassMoney(positiveTotal,
                currency: repository.baseCurrency, decimals: 0),
            formatLegendAmount: (amount) => compassMoney(amount,
                currency: repository.baseCurrency, decimals: 0),
            slices: [
              FinanceDonutSlice(
                  label: '现金', value: cash, color: assetColors[0]),
              FinanceDonutSlice(
                  label: '投资', value: investment, color: assetColors[2]),
              FinanceDonutSlice(
                  label: '退休', value: retirement, color: assetColors[1]),
              if (cardCredit + data.loanCredit > 0)
                FinanceDonutSlice(
                    label: '溢付余额',
                    value: cardCredit + data.loanCredit,
                    color: financePaletteOf(context).income),
            ],
            footer: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  '负债 ${compassMoney(debt, currency: repository.baseCurrency, decimals: 0)}',
                  style: TextStyle(
                    color: debt > 0
                        ? financePaletteOf(context).expense
                        : financePaletteOf(context).textMuted,
                    fontFeatures: compassTabularFigures,
                  ),
                ),
                if (cardCredit > 0)
                  Text(
                    '信用卡溢缴款 ${compassMoney(cardCredit, currency: repository.baseCurrency, decimals: 0)}',
                    style: TextStyle(
                      color: financePaletteOf(context).income,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                if (!wide) Text(asOfLabel, style: textTheme.bodySmall),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: '资产构成',
                scope: wide ? null : asOfLabel,
                helpMessage: _assetHelp,
              ),
              const SizedBox(height: 10),
              Text('暂无资产余额', style: textTheme.bodySmall),
            ],
          );
    final budgetHeading = _SectionHeader(
      title: '本月预算',
      scope: _monthLabel(currentMonthKey),
      helpMessage: _budgetHelp,
    );
    final budgetActualRatio = budget <= 0 ? 0.0 : budgetActual / budget;
    final budgetPlannedRatio = budget <= 0 ? 0.0 : budgetPlanned / budget;
    final budgetPriced = repository.budgetMonthIsValued(currentMonthKey);
    final hasBudget =
        repository.activeBudgetsForMonth(currentMonthKey).isNotEmpty;
    final budgetContent = !hasBudget
        ? Text('本月尚未设置预算', style: textTheme.bodySmall)
        : !budgetPriced
            ? Text(
                '缺少汇率，预算进度未估值（已折算预算 ${_money(budget)}，已折算占用 ${_money(budgetUsed)}）',
                style: textTheme.bodySmall)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已用（含预计交易）',
                          style: textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        budget <= 0
                            ? '—'
                            : '${(budgetRate * 100).toStringAsFixed(0)}%',
                        key: const Key('reports-budget-rate'),
                        style: TextStyle(
                          color: budgetRate > 1.0
                              ? financePaletteOf(context).expense
                              : budgetRate >= .8
                                  ? financePaletteOf(context).warning
                                  : financePaletteOf(context).income,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFeatures: compassTabularFigures,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CompassDualProgressBar(
                    actualRatio: budgetActualRatio,
                    plannedRatio: budgetPlannedRatio,
                    alertThreshold: 0.8,
                    height: 8,
                    semanticsLabel: '本月总体预算进度',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '已用 ${_money(budgetUsed)} / 预算 ${_money(budget)}',
                    style: textTheme.bodySmall?.copyWith(
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                  Text(
                    '其中预计 ${_money(budgetPlanned)} · '
                    '${budgetRemaining >= 0 ? '剩余 ${_money(budgetRemaining)}' : '超支 ${_money(-budgetRemaining)}'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: budgetRemaining < 0
                          ? financePaletteOf(context).expense
                          : null,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                ],
              );
    final investmentHeading = _SectionHeader(
      title: '投资与退休账户',
      scope: asOfLabel,
      helpMessage: _investmentHelp,
    );
    final investmentContent = investmentAccounts.isEmpty
        ? Text('尚未添加投资或退休账户', style: textTheme.bodySmall)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: '当前市值',
                      value: _money(marketValue),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '净投入',
                      value: _money(remainingCost),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '资金净收益',
                      value: _changeAmount(unrealizedPnl),
                      valueKey: const Key('reports-investment-pnl'),
                      color: _signColor(context, unrealizedPnl),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                hasCost
                    ? '资金收益率 ${_signedPercent(unrealizedPnl / remainingCost)}'
                    : '净投入不大于零，收益率不适用',
                style: textTheme.bodySmall?.copyWith(
                  fontFeatures: compassTabularFigures,
                ),
              ),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= compassDesktopMinWidth;
        return ListView(
          cacheExtent: 500,
          padding: compassScrollPadding(
            context,
            wide ? compassDesktopPagePadding : compassPagePadding,
          ),
          children: [
            header,
            if (wide) ...[
              const SizedBox(height: 24),
              _ReportScopeHeading(
                title: '所选期间',
                date: period,
                helpMessage: _periodHelp,
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CompassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: netWorthSection(wide: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _ReportPanel(
                        heading: cashFlowHeading,
                        content: cashFlowContent(wide: true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ReportPanel(
                heading: spendingHeading,
                content: spendContent(wide: true),
              ),
              const SizedBox(height: 24),
              _ReportScopeHeading(
                title: '本月末快照',
                helpMessage: _snapshotHelp,
                date: Text(
                  '${cutoff.year}年${cutoff.month}月${cutoff.day}日',
                  style: textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: assetsSection(wide: true)),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ReportPanel(
                          heading: const _SectionHeader(
                            title: '本月预算',
                            helpMessage: _budgetHelp,
                          ),
                          content: budgetContent,
                        ),
                        const SizedBox(height: 16),
                        _ReportPanel(
                          heading: const _SectionHeader(
                            title: '投资与退休账户',
                            helpMessage: _investmentHelp,
                          ),
                          content: investmentContent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              CompassHelpHeading(
                title: period,
                label: '所选期间',
                message: _periodHelp,
              ),
              const SizedBox(height: 14),
              ...netWorthSection(wide: false),
              const SizedBox(height: 24),
              cashFlowHeading,
              const SizedBox(height: 10),
              CompassCard(child: cashFlowContent(wide: false)),
              const SizedBox(height: 24),
              spendingHeading,
              const SizedBox(height: 10),
              CompassCard(child: spendContent(wide: false)),
              const SizedBox(height: 24),
              assetsSection(wide: false),
              const SizedBox(height: 24),
              budgetHeading,
              const SizedBox(height: 10),
              CompassCard(child: budgetContent),
              const SizedBox(height: 24),
              investmentHeading,
              const SizedBox(height: 10),
              CompassCard(child: investmentContent),
            ],
          ],
        );
      },
    );
  }
}

class _ReportScopeHeading extends StatelessWidget {
  const _ReportScopeHeading({
    required this.title,
    required this.date,
    required this.helpMessage,
  });

  final String title;
  final Widget date;
  final String helpMessage;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          CompassHelpHeading(
            title: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            label: title,
            message: helpMessage,
          ),
          date,
        ],
      );
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.heading, required this.content});

  final Widget heading;
  final Widget content;

  @override
  Widget build(BuildContext context) => CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [heading, const SizedBox(height: 12), content],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.scope,
    this.helpLabel,
    this.helpMessage,
  });

  final String title;
  final String? scope;
  final String? helpLabel;
  final String? helpMessage;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helpMessage case final message?)
            CompassHelpHeading(
              title:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
              label: helpLabel ?? title,
              message: message,
            )
          else
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (scope case final scope?) ...[
            const SizedBox(height: 2),
            Text(scope, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.valueKey,
    this.color,
  });

  final String label;
  final String value;
  final Key? valueKey;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: financePaletteOf(context).textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                key: valueKey,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: compassTabularFigures,
                ),
              ),
            ),
          ],
        ),
      );
}

const _expenseAmountColumnWidth = 148.0;
const _expenseShareColumnWidth = 64.0;

class _ExpenseTableHeader extends StatelessWidget {
  const _ExpenseTableHeader();

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall,
        child: const Column(
          children: [
            Row(
              children: [
                SizedBox(width: 20),
                Expanded(child: Text('分类')),
                SizedBox(width: 8),
                SizedBox(
                  width: _expenseAmountColumnWidth,
                  child: Text('金额', textAlign: TextAlign.end),
                ),
                SizedBox(
                  width: _expenseShareColumnWidth,
                  child: Text('占比', textAlign: TextAlign.end),
                ),
              ],
            ),
            SizedBox(height: 6),
            Divider(height: 1),
          ],
        ),
      );
}

class _CategoryRankRow extends StatelessWidget {
  const _CategoryRankRow({
    required this.index,
    required this.name,
    required this.amount,
    required this.currency,
    required this.maxAmount,
    required this.share,
    required this.wide,
  });

  final int index;
  final String name;
  final double amount;
  final String currency;
  final double maxAmount;
  final double? share;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final barRatio =
        maxAmount <= 0 ? 0.0 : (amount.abs() / maxAmount).clamp(0.0, 1.0);
    final amountLabel = Text(
      compassMoney(amount, currency: currency),
      key: Key('reports-category-$index-amount'),
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontFeatures: compassTabularFigures,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: wide ? 5 : 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontFeatures: compassTabularFigures,
                  ),
                ),
              ),
              if (wide)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          name,
                          key: Key('reports-category-$index-name'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: CompassDualProgressBar(
                            actualRatio: barRatio,
                            alertThreshold: 1.0,
                            height: 6,
                            actualColor:
                                amount < 0 ? palette.income : palette.seed,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  flex: 3,
                  child: Text(
                    name,
                    key: Key('reports-category-$index-name'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              if (wide)
                SizedBox(
                  width: _expenseAmountColumnWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: amountLabel,
                  ),
                )
              else
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: amountLabel,
                  ),
                ),
              SizedBox(
                width: wide ? _expenseShareColumnWidth : 52,
                child: Text(
                  share == null ? '—' : '${(share! * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontFeatures: compassTabularFigures,
                  ),
                ),
              ),
            ],
          ),
          if (!wide)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 5),
              child: CompassDualProgressBar(
                actualRatio: barRatio,
                alertThreshold: 1.0,
                height: 4,
                actualColor: amount < 0 ? palette.income : palette.seed,
              ),
            ),
        ],
      ),
    );
  }
}

class _NetFlowLine extends StatefulWidget {
  const _NetFlowLine({
    super.key,
    required this.values,
    required this.monthLabels,
    required this.baseCurrency,
    required this.height,
  });

  final List<double> values;
  final List<String> monthLabels;
  final String baseCurrency;
  final double height;

  @override
  State<_NetFlowLine> createState() => _NetFlowLineState();
}

class _NetFlowLineState extends State<_NetFlowLine> {
  int? _activeIndex;

  void _updateFromDx(double dx, double width) {
    if (width <= 0 || widget.values.isEmpty) return;
    final index = widget.values.length == 1
        ? 0
        : ((dx / width).clamp(0.0, 1.0) * (widget.values.length - 1))
            .round()
            .clamp(0, widget.values.length - 1);
    if (_activeIndex != index) {
      setState(() => _activeIndex = index);
    }
  }

  void _clearActive() {
    if (_activeIndex != null) {
      setState(() => _activeIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Semantics(
      label: '所选期间每月实际现金净流入',
      value:
          '最新月份 ${_signedMoney(widget.values.last, currency: widget.baseCurrency)}',
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: widget.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return MouseRegion(
                    onHover: (event) =>
                        _updateFromDx(event.localPosition.dx, width),
                    onExit: (_) => _clearActive(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          _updateFromDx(details.localPosition.dx, width),
                      onHorizontalDragStart: (details) =>
                          _updateFromDx(details.localPosition.dx, width),
                      onHorizontalDragUpdate: (details) =>
                          _updateFromDx(details.localPosition.dx, width),
                      onHorizontalDragEnd: (_) => _clearActive(),
                      onTapUp: (_) => _clearActive(),
                      onTapCancel: _clearActive,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _NetFlowPainter(
                            widget.values,
                            widget.monthLabels,
                            widget.baseCurrency,
                            _activeIndex,
                            palette,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          ExcludeSemantics(
            child: Text(
              '0',
              style: TextStyle(color: palette.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetFlowPainter extends CustomPainter {
  const _NetFlowPainter(
    this.values,
    this.monthLabels,
    this.baseCurrency,
    this.activeIndex,
    this.palette,
  );

  final List<double> values;
  final List<String> monthLabels;
  final String baseCurrency;
  final int? activeIndex;
  final FinanceThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 3.0;
    final width = size.width - inset * 2;
    final zero = size.height / 2;
    if (width <= 0 || zero <= inset) return;

    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()..color = palette.border,
    );

    final peak =
        values.fold<double>(0, (peak, value) => math.max(peak, value.abs()));
    if (peak > 0 && size.height >= 96) {
      final peakText = compassMoney(peak, currency: baseCurrency, decimals: 0);
      _paintScaleLabel(canvas, size, '+ $peakText', 2);
      _paintScaleLabel(canvas, size, '- $peakText', size.height - 14);
    }

    final points = [
      for (var index = 0; index < values.length; index++)
        Offset(
          values.length == 1
              ? size.width / 2
              : inset + width * index / (values.length - 1),
          peak == 0 ? zero : zero - values[index] / peak * (zero - inset),
        ),
    ];
    final line = Path()..addPolygon(points, false);
    canvas.drawPath(
      line,
      Paint()
        ..color = palette.seed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    final pointPaint = Paint();
    for (var index = 0; index < points.length; index++) {
      if (points.length > 1 &&
          (values[index] == 0 ||
              (points.length > 24 && index != points.length - 1))) {
        continue;
      }
      pointPaint.color = values[index] >= 0 ? palette.income : palette.expense;
      canvas.drawCircle(points[index], 2.8, pointPaint);
    }

    if (activeIndex case final hoverIndex?
        when hoverIndex >= 0 && hoverIndex < points.length) {
      final point = points[hoverIndex];
      final dotColor =
          values[hoverIndex] >= 0 ? palette.income : palette.expense;
      canvas.drawLine(
        Offset(point.dx, 0),
        Offset(point.dx, size.height),
        Paint()
          ..color = palette.textMuted.withValues(alpha: .45)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(point, 5.5, Paint()..color = palette.surface);
      canvas.drawCircle(point, 3.6, Paint()..color = dotColor);

      final label = hoverIndex < monthLabels.length
          ? '${monthLabels[hoverIndex]} · 净 ${_signedMoney(values[hoverIndex], currency: baseCurrency, decimals: 0)}'
          : _signedMoney(values[hoverIndex],
              currency: baseCurrency, decimals: 0);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: financeForegroundOn(palette.textPrimary),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            fontFeatures: compassTabularFigures,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: math.max(80, size.width - 12));
      final pillWidth = painter.width + 12;
      final pillHeight = painter.height + 6;
      final dx = (point.dx - pillWidth / 2)
          .clamp(2.0, math.max(2.0, size.width - pillWidth - 2))
          .toDouble();
      final preferredY = point.dy - pillHeight - 7;
      final dy = preferredY >= 2
          ? preferredY
          : (point.dy + 8)
              .clamp(2.0, math.max(2.0, size.height - pillHeight - 2))
              .toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dx, dy, pillWidth, pillHeight),
          const Radius.circular(7),
        ),
        Paint()..color = palette.textPrimary,
      );
      painter.paint(canvas, Offset(dx + 6, dy + 3));
    }
  }

  void _paintScaleLabel(Canvas canvas, Size size, String text, double y) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: palette.textMuted.withValues(alpha: .68),
          fontSize: 9.5,
          fontFeatures: compassTabularFigures,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width * .6);
    painter.paint(
      canvas,
      Offset(math.max(0, size.width - painter.width - 2), y),
    );
  }

  @override
  bool shouldRepaint(_NetFlowPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.activeIndex != activeIndex ||
      !listEquals(oldDelegate.values, values);
}

List<String> _monthKeysBetween(DateTime start, DateTime end) {
  final keys = <String>[];
  var cursor = DateTime(start.year, start.month);
  final last = DateTime(end.year, end.month);
  while (!cursor.isAfter(last)) {
    keys.add(monthKeyFromDate(cursor));
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return keys.isEmpty ? [monthKeyFromDate(end)] : keys;
}

String _monthLabel(String monthKey) {
  final parts = monthKey.split('-');
  return '${parts[0]}年${int.parse(parts[1])}月';
}

/// Signed amount for changes; a zero change never carries a gain sign.
String _signedMoney(double value,
    {required String currency, int decimals = 2}) =>
    compassMoney(value, currency: currency, decimals: decimals, showPositiveSign: true);

Color _signColor(BuildContext context, double value, {int decimals = 2}) {
  final palette = financePaletteOf(context);
  if (moneyDisplayParts(value, decimals: decimals).sign == 0) {
    return palette.textMuted;
  }
  return value > 0 ? palette.income : palette.expense;
}

String _signedPercent(double ratio) {
  final percent = ratio * 100;
  if (percent.abs() < 0.05) {
    return '0.0%';
  }
  return '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';
}

class _ReportsViewData {
  const _ReportsViewData({
    required this.repository,
    required this.range,
    required this.todayKey,
    required this.currentMonthKey,
    required this.cutoff,
    required this.asOfLabel,
    required this.hasAccounts,
    required this.netWorth,
    required this.monthKeys,
    required this.startingNetWorth,
    required this.growth,
    required this.growthRate,
    required this.chartValues,
    required this.chartLabels,
    required this.cashFlow,
    required this.monthlyNet,
    required this.monthLabels,
    required this.hasCashFlow,
    required this.savingsRateLabel,
    required this.averageMonthlyNet,
    required this.rankedExpenses,
    required this.expenseTotal,
    required this.positiveExpenseTotal,
    required this.unclassifiedActual,
    required this.unpricedExpenses,
    required this.maxExpenseAmount,
    required this.cash,
    required this.investment,
    required this.retirement,
    required this.debt,
    required this.cardCredit,
    required this.loanCredit,
    required this.positiveTotal,
    required this.hasComposition,
    required this.budget,
    required this.budgetActual,
    required this.budgetPlanned,
    required this.budgetUsed,
    required this.budgetRate,
    required this.budgetRemaining,
    required this.investmentAccounts,
    required this.marketValue,
    required this.remainingCost,
    required this.unrealizedPnl,
    required this.hasCost,
    required this.rangeLabel,
    required this.periodLabel,
    required this.shareText,
  });

  final FinanceRepository repository;
  final _ReportOverviewRange range;
  final int todayKey;
  final String currentMonthKey;
  final DateTime cutoff;
  final String asOfLabel;
  final bool hasAccounts;
  final double netWorth;
  final List<String> monthKeys;
  final double startingNetWorth;
  final double growth;
  final double? growthRate;
  final List<double> chartValues;
  final List<String> chartLabels;
  final CashFlowSummary cashFlow;
  final List<double> monthlyNet;
  final List<String> monthLabels;
  final bool hasCashFlow;
  final String savingsRateLabel;
  final double averageMonthlyNet;
  final List<MapEntry<String, double>> rankedExpenses;
  final double expenseTotal;
  final double positiveExpenseTotal;
  final double? unclassifiedActual;
  final Map<String, double> unpricedExpenses;
  final double maxExpenseAmount;
  final double cash;
  final double investment;
  final double retirement;
  final double debt;
  final double cardCredit;
  final double loanCredit;
  final double positiveTotal;
  final bool hasComposition;
  final double budget;
  final double budgetActual;
  final double budgetPlanned;
  final double budgetUsed;
  final double budgetRate;
  final double budgetRemaining;
  final List<Account> investmentAccounts;
  final double marketValue;
  final double remainingCost;
  final double unrealizedPnl;
  final bool hasCost;
  final String rangeLabel;
  final String periodLabel;
  final String shareText;
}
