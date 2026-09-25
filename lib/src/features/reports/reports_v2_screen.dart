import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';

enum _ReportOverviewRange { yearToDate, last12Months, allTime }

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

  FinanceRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final currentMonthKey = monthKeyFromDate(now);
    final cutoff = repository.currentMonthCutoffDate();
    final asOfLabel = '截至 ${cutoff.month}月${cutoff.day}日（本月末）';

    // Range-driven figures: net-worth change, actual cash flow, categories.
    final hasAccounts = repository.accounts.isNotEmpty;
    final netWorth = repository.totalAssets();
    final allHistory = repository.totalAssetHistory();
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
    final chartValues = <double>[
      startingNetWorth,
      ...allHistory
          .where((point) =>
              !point.date.isBefore(rangeStart) &&
              point.label != currentMonthKey)
          .map((point) => point.totalAssets),
      netWorth,
    ];
    final cashFlow = repository.actualCashFlowSummaryForMonths(monthKeys);
    final monthlyNet = [
      for (final key in monthKeys)
        repository.actualCashFlowSummaryForMonth(key).net,
    ];
    final hasCashFlow = cashFlow.inflow != 0 || cashFlow.outflow != 0;
    final savingsRateLabel = cashFlow.inflow > 0
        ? '${(cashFlow.net / cashFlow.inflow * 100).toStringAsFixed(0)}%'
        : '—';
    final averageMonthlyNet = cashFlow.net / monthKeys.length;
    final rankedExpenses = repository
        .categoryTotalsForMonths(
          type: CategoryType.expense,
          monthKeys: monthKeys,
        )
        .entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        return byAmount != 0
            ? byAmount
            : repository
                .categoryName(a.key)
                .compareTo(repository.categoryName(b.key));
      });
    final expenseTotal =
        rankedExpenses.fold<double>(0, (sum, entry) => sum + entry.value);
    final topExpenses = rankedExpenses.take(5).toList();

    // Point-in-time figures: they do not follow the selected range.
    final cash = repository.totalAssetsByGroup(ReportGroup.cash);
    final investment = repository.totalAssetsByGroup(ReportGroup.investment);
    final retirement = repository.totalAssetsByGroup(ReportGroup.retirement);
    final creditBalance = repository.totalAssetsByGroup(ReportGroup.credit);
    final debt = creditBalance < 0 ? -creditBalance : 0.0;
    final positiveTotal = cash + investment + retirement;
    final hasComposition = positiveTotal > 0 || debt > 0;
    String percent(double value) =>
        positiveTotal <= 0 ? '0%' : '${(value / positiveTotal * 100).round()}%';
    final budget = repository.totalEffectiveBudgetForMonth(currentMonthKey);
    final budgetActual = repository.totalBudgetExpenseForMonth(currentMonthKey);
    final budgetPlanned =
        repository.totalPlannedBudgetExpenseForMonth(currentMonthKey);
    final budgetUsed = budgetActual + budgetPlanned;
    final budgetRate = budget <= 0 ? 0.0 : budgetUsed / budget;
    final budgetRemaining = budget - budgetUsed;
    final budgetColor = budgetRate >= .8
        ? FinanceColors.compassOrange
        : FinanceColors.compassTeal;
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
      '当前净资产 ${compassMoney(netWorth)}',
      '$rangeLabel净资产变化 ${_signedMoney(growth)}',
      hasCashFlow
          ? '$rangeLabel实际现金净流入 ${_signedMoney(cashFlow.net)}'
              '（流入 ${compassMoney(cashFlow.inflow)}'
              ' / 流出 ${compassMoney(cashFlow.outflow)}）'
          : '$rangeLabel没有实际现金流记录',
    ].join('\n');
    return ListView(
      padding: compassPagePadding.copyWith(bottom: 28),
      children: [
        CompassPageHeader(
          title: '报表',
          actions: [
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: FinanceColors.compassBorder),
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
        ),
        const SizedBox(height: 6),
        Text(
          '所选期间：$periodLabel',
          key: const Key('reports-period-label'),
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Text('净资产 · 当前（$asOfLabel）', style: textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          compassMoney(netWorth, decimals: 0),
          style: const TextStyle(
            color: FinanceColors.compassTeal,
            fontSize: 31,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        if (!hasAccounts)
          Text(
            '尚未添加账户，添加账户后可查看净资产变化。',
            style: textTheme.bodySmall,
          )
        else ...[
          Text.rich(
            TextSpan(
              text: '$rangeLabel 变化 ',
              children: [
                TextSpan(
                  text: _signedMoney(growth, decimals: 0),
                  style: TextStyle(color: _signColor(growth, decimals: 0)),
                ),
                const TextSpan(text: ' · '),
                TextSpan(
                  text: growthRate == null ? '—' : _signedPercent(growthRate),
                  style: TextStyle(color: _signColor(growth, decimals: 0)),
                ),
              ],
            ),
            key: const Key('reports-net-worth-change'),
          ),
          if (growthRate == null)
            Text(
              '期初净资产不为正，变化率不适用。',
              style: textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 16, 4, 12),
                child: CompassAreaChart(
                  key: const Key('reports-net-worth-trend'),
                  values: chartValues,
                  height: 176,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Text(
                  '当前  ${compassMoney(netWorth, decimals: 0)}',
                  style: const TextStyle(
                    color: FinanceColors.compassTeal,
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
                '${_monthLabel(monthKeys.first)}期初',
                style: const TextStyle(fontSize: 10),
              ),
              const Text('当前', style: TextStyle(fontSize: 10)),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _SectionHeader(
          title: '实际现金流',
          scope: '$periodLabel · 仅统计已发生交易，不含预计交易',
        ),
        const SizedBox(height: 10),
        CompassCard(
          child: !hasCashFlow
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
                            value: compassMoney(cashFlow.inflow),
                            valueKey: const Key('reports-cash-inflow'),
                            color: FinanceColors.compassTeal,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '流出',
                            value: compassMoney(cashFlow.outflow),
                            valueKey: const Key('reports-cash-outflow'),
                            color: FinanceColors.compassOrange,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '净流入',
                            value: _signedMoney(cashFlow.net),
                            valueKey: const Key('reports-cash-net'),
                            color: _signColor(cashFlow.net),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _NetFlowBars(
                      key: const Key('reports-cash-flow-trend'),
                      values: monthlyNet,
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
                      '${_signedMoney(averageMonthlyNet, decimals: 0)}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Text(
          '口径：只统计现金类账户的实际进出。信用卡消费在还款时才计入；'
          '信用卡和贷款还款按实际支付的全额计为现金流出；现金账户之间的转账相互抵消。',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        _SectionHeader(
          title: '支出分类排行 · 前 5',
          scope: '$periodLabel · 按交易发生口径（非现金流）：'
              '信用卡消费按消费日计入，不含预计交易',
        ),
        const SizedBox(height: 10),
        CompassCard(
          child: topExpenses.isEmpty
              ? Text(
                  '所选期间没有已分类支出',
                  style: textTheme.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < topExpenses.length; index++)
                      _CategoryRankRow(
                        index: index,
                        name: repository.categoryName(topExpenses[index].key),
                        amount: topExpenses[index].value,
                        share: expenseTotal <= 0
                            ? 0.0
                            : topExpenses[index].value / expenseTotal,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '已分类支出合计 ${compassMoney(expenseTotal)}'
                      '${rankedExpenses.length > 5 ? ' · 共 ${rankedExpenses.length} 个分类' : ''}',
                      key: const Key('reports-category-total'),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(
          title: '资产构成',
          scope: '当前时点 · $asOfLabel，不随所选期间变化',
        ),
        const SizedBox(height: 10),
        if (!hasComposition)
          Text('暂无资产余额', style: textTheme.bodySmall)
        else ...[
          CompassDistributionBar(
            values: [cash, investment, retirement, -debt],
            colors: [
              FinanceColors.compassTeal,
              Color(0xFF3F8795),
              Color(0xFF376B50),
              FinanceColors.compassOrange,
            ],
            labels: [
              percent(cash),
              percent(investment),
              percent(retirement),
              debt == 0 || positiveTotal <= 0
                  ? '0%'
                  : '-${(debt / positiveTotal * 100).round()}%',
            ],
            height: 24,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AssetLegend(
                  label: '现金',
                  amount: compassMoney(cash, decimals: 0),
                  color: FinanceColors.compassTeal,
                ),
              ),
              Expanded(
                child: _AssetLegend(
                  label: '投资',
                  amount: compassMoney(investment, decimals: 0),
                  color: Color(0xFF3F8795),
                ),
              ),
              Expanded(
                child: _AssetLegend(
                  label: '退休',
                  amount: compassMoney(retirement, decimals: 0),
                  color: Color(0xFF376B50),
                ),
              ),
              Expanded(
                child: _AssetLegend(
                  label: '信用负债',
                  amount: '-${compassMoney(debt, decimals: 0)}',
                  color: FinanceColors.compassOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('负债为负值，将从资产中扣除。', style: textTheme.bodySmall),
        ],
        const SizedBox(height: 24),
        _SectionHeader(
          title: '本月预算',
          scope: '${now.year}年${now.month}月 · 不随所选期间变化',
        ),
        const SizedBox(height: 10),
        CompassCard(
          child: budget <= 0
              ? Text('本月尚未设置预算', style: textTheme.bodySmall)
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
                          '${(budgetRate * 100).toStringAsFixed(0)}%',
                          key: const Key('reports-budget-rate'),
                          style: TextStyle(color: budgetColor, fontSize: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: budgetRate.clamp(0.0, 1.0).toDouble(),
                        minHeight: 6,
                        color: budgetColor,
                        backgroundColor: FinanceColors.compassBorder,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已用 ${compassMoney(budgetUsed)} / 预算 ${compassMoney(budget)}',
                      style: textTheme.bodySmall,
                    ),
                    Text(
                      '其中预计 ${compassMoney(budgetPlanned)} · '
                      '${budgetRemaining >= 0 ? '剩余 ${compassMoney(budgetRemaining)}' : '超支 ${compassMoney(-budgetRemaining)}'}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(
          title: '投资与退休账户',
          scope: '当前时点 · $asOfLabel 的市值与成本，不随所选期间变化',
        ),
        const SizedBox(height: 10),
        CompassCard(
          child: investmentAccounts.isEmpty
              ? Text('尚未添加投资或退休账户', style: textTheme.bodySmall)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: '当前市值',
                            value: compassMoney(marketValue),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '剩余成本',
                            value: hasCost ? compassMoney(remainingCost) : '—',
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '未实现盈亏',
                            value: hasCost ? _signedMoney(unrealizedPnl) : '—',
                            valueKey: const Key('reports-investment-pnl'),
                            color: hasCost
                                ? _signColor(unrealizedPnl)
                                : FinanceColors.compassMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hasCost
                          ? '未实现收益率 ${_signedPercent(unrealizedPnl / remainingCost)}'
                          : '尚无成本数据，无法计算未实现盈亏。',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AssetLegend extends StatelessWidget {
  const _AssetLegend({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              amount,
              style: const TextStyle(
                color: FinanceColors.compassMuted,
                fontSize: 9,
              ),
            ),
          ),
        ],
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.scope});

  final String title;
  final String scope;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(scope, style: Theme.of(context).textTheme.bodySmall),
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
              style: const TextStyle(
                color: FinanceColors.compassMuted,
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
                ),
              ),
            ),
          ],
        ),
      );
}

class _CategoryRankRow extends StatelessWidget {
  const _CategoryRankRow({
    required this.index,
    required this.name,
    required this.amount,
    required this.share,
  });

  final int index;
  final String name;
  final double amount;
  final double share;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: FinanceColors.compassMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    name,
                    key: Key('reports-category-$index-name'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  compassMoney(amount),
                  key: Key('reports-category-$index-amount'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(share * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: FinanceColors.compassMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0).toDouble(),
                  minHeight: 5,
                  color: FinanceColors.compassOrange,
                  backgroundColor: FinanceColors.compassBorder,
                ),
              ),
            ),
          ],
        ),
      );
}

class _NetFlowBars extends StatelessWidget {
  const _NetFlowBars({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final peak =
        values.fold<double>(0, (max, value) => math.max(max, value.abs()));
    final gap = values.length > 24 ? 0.5 : 2.0;
    Widget bar(double value) => FractionallySizedBox(
          heightFactor: peak <= 0 ? 0.0 : value.abs() / peak,
          widthFactor: 1,
          child: ColoredBox(
            color: value >= 0
                ? FinanceColors.compassTeal
                : FinanceColors.compassOrange,
          ),
        );
    return Semantics(
      label: '所选期间每月实际现金净流入',
      child: SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final value in values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gap),
                  child: Column(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: value > 0 ? bar(value) : null,
                        ),
                      ),
                      Container(
                        height: 1,
                        color: FinanceColors.compassBorder,
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: value < 0 ? bar(value) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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

bool _isZero(double value, int decimals) =>
    value.abs() < 0.5 / math.pow(10, decimals);

/// Signed amount for changes; a zero change never carries a gain sign.
String _signedMoney(double value, {int decimals = 2}) {
  if (_isZero(value, decimals)) {
    return compassMoney(0, decimals: decimals);
  }
  final formatted = compassMoney(value, decimals: decimals);
  return value > 0 ? '+ $formatted' : formatted;
}

Color _signColor(double value, {int decimals = 2}) {
  if (_isZero(value, decimals)) {
    return FinanceColors.compassMuted;
  }
  return value > 0 ? FinanceColors.compassTeal : FinanceColors.compassOrange;
}

String _signedPercent(double ratio) {
  final percent = ratio * 100;
  if (percent.abs() < 0.05) {
    return '0.0%';
  }
  return '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';
}
