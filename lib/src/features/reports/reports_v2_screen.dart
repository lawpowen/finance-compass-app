import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_donut.dart';

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
    double positiveBalance(ReportGroup group) =>
        repository.displayTotalAssetsByGroup(group, positiveOnly: true);
    final cash = positiveBalance(ReportGroup.cash);
    final investment = positiveBalance(ReportGroup.investment);
    final retirement = positiveBalance(ReportGroup.retirement);
    final liabilities = repository.accountLiabilities();
    final debt = liabilities.credit + liabilities.loans;
    final cardCredit = repository.totalCreditCardCredit();
    final positiveTotal = cash + investment + retirement;
    final hasComposition = positiveTotal > 0 || debt > 0 || cardCredit > 0;
    final assetColors = financeDonutSeries(context);
    final budget = repository.totalEffectiveBudgetForMonth(currentMonthKey);
    final budgetActual = repository.totalBudgetExpenseForMonth(currentMonthKey);
    final budgetPlanned =
        repository.totalPlannedBudgetExpenseForMonth(currentMonthKey);
    final budgetUsed = budgetActual + budgetPlanned;
    final budgetRate = budget <= 0 ? 0.0 : budgetUsed / budget;
    final budgetRemaining = budget - budgetUsed;
    final budgetColor = budgetRate >= .8
        ? financePaletteOf(context).expense
        : financePaletteOf(context).seed;
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
      '月末净资产 ${compassMoney(netWorth)}（${cutoff.month}月${cutoff.day}日）',
      '$rangeLabel净资产变化 ${_signedMoney(growth)}',
      hasCashFlow
          ? '$rangeLabel实际现金净流入 ${_signedMoney(cashFlow.net)}'
              '（流入 ${compassMoney(cashFlow.inflow)}'
              ' / 流出 ${compassMoney(cashFlow.outflow)}）'
          : '$rangeLabel没有实际现金流记录',
    ].join('\n');
    final header = CompassPageHeader(
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
            )
          else
            Text(
              '月末净资产 · ${cutoff.month}月${cutoff.day}日',
              style: textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(
            compassMoney(netWorth, decimals: 0),
            style: TextStyle(
              color: financePaletteOf(context).seed,
              fontSize: 31,
              fontWeight: FontWeight.w600,
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
                    text: _signedMoney(growth, decimals: 0),
                    style: TextStyle(
                        color: _signColor(context, growth, decimals: 0)),
                  ),
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: growthRate == null ? '—' : _signedPercent(growthRate),
                    style: TextStyle(
                        color: _signColor(context, growth, decimals: 0)),
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
                  padding: wide
                      ? const EdgeInsets.fromLTRB(2, 4, 2, 8)
                      : const EdgeInsets.fromLTRB(26, 16, 4, 12),
                  child: CompassAreaChart(
                    key: const Key('reports-net-worth-trend'),
                    values: chartValues,
                    height: wide ? 160 : 176,
                  ),
                ),
                if (!wide)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Text(
                      '本月末  ${compassMoney(netWorth, decimals: 0)}',
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
                      ? '期初 ${compassMoney(startingNetWorth, decimals: 0)}'
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
      scope: '现金账户实际收付 · 信用卡和贷款还款计入全额',
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
                      value: compassMoney(cashFlow.inflow),
                      valueKey: const Key('reports-cash-inflow'),
                      color: financePaletteOf(context).seed,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '流出',
                      value: compassMoney(cashFlow.outflow),
                      valueKey: const Key('reports-cash-outflow'),
                      color: financePaletteOf(context).expense,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '净流入',
                      value: _signedMoney(cashFlow.net),
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
                '${_signedMoney(averageMonthlyNet, decimals: 0)}',
                style: textTheme.bodySmall,
              ),
            ],
          );
    const spendingHeading = _SectionHeader(
      title: '支出分类排行 · 前 5',
      scope: '按交易发生日 · 含刷卡消费 · 不含预计交易',
    );
    Widget spendContent({required bool wide}) => topExpenses.isEmpty
        ? Text(
            '所选期间没有已分类支出',
            style: textTheme.bodySmall,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) const _ExpenseTableHeader(),
              for (var index = 0; index < topExpenses.length; index++)
                _CategoryRankRow(
                  index: index,
                  name: repository.categoryName(topExpenses[index].key),
                  amount: topExpenses[index].value,
                  share: expenseTotal <= 0
                      ? 0.0
                      : topExpenses[index].value / expenseTotal,
                  wide: wide,
                ),
              const SizedBox(height: 6),
              Text(
                '已分类支出合计 ${compassMoney(expenseTotal)}'
                '${rankedExpenses.length > 5 ? ' · 共 ${rankedExpenses.length} 个分类' : ''}',
                key: const Key('reports-category-total'),
                style: textTheme.bodySmall,
              ),
            ],
          );
    Widget assetsSection({required bool wide}) => hasComposition
        ? FinanceDonutPanel(
            key: const Key('reports-asset-composition'),
            title: '资产构成',
            totalLabel: '总资产',
            totalValue: compassMoney(positiveTotal,
                currency: repository.baseCurrency, decimals: 0),
            formatLegendAmount: wide
                ? (amount) => compassMoney(amount,
                    currency: repository.baseCurrency, decimals: 0)
                : null,
            slices: [
              FinanceDonutSlice(
                  label: '现金', value: cash, color: assetColors[0]),
              FinanceDonutSlice(
                  label: '投资', value: investment, color: assetColors[2]),
              FinanceDonutSlice(
                  label: '退休', value: retirement, color: assetColors[1]),
            ],
            footer: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  '负债 ${compassMoney(debt, currency: repository.baseCurrency, decimals: 0)}',
                ),
                if (cardCredit > 0)
                  Text(
                    '信用卡溢缴款 ${compassMoney(cardCredit, currency: repository.baseCurrency, decimals: 0)}',
                  ),
                if (!wide) Text(asOfLabel, style: textTheme.bodySmall),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: '资产构成', scope: wide ? null : asOfLabel),
              const SizedBox(height: 10),
              Text('暂无资产余额', style: textTheme.bodySmall),
            ],
          );
    final budgetHeading = _SectionHeader(
      title: '本月预算',
      scope: _monthLabel(currentMonthKey),
    );
    final budgetContent = budget <= 0
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
          );
    final investmentHeading = _SectionHeader(
      title: '投资与退休账户',
      scope: asOfLabel,
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
                          ? _signColor(context, unrealizedPnl)
                          : financePaletteOf(context).textMuted,
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
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= compassDesktopMinWidth;
        return ListView(
          padding: compassScrollPadding(
            context,
            wide ? compassDesktopPagePadding : compassPagePadding,
          ),
          children: [
            header,
            if (wide) ...[
              const SizedBox(height: 24),
              _ReportScopeHeading(title: '所选期间', date: period),
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
              const SizedBox(height: 32),
              _ReportScopeHeading(
                title: '本月末快照',
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
                          heading: const _SectionHeader(title: '本月预算'),
                          content: budgetContent,
                        ),
                        const SizedBox(height: 16),
                        _ReportPanel(
                          heading: const _SectionHeader(title: '投资与退休账户'),
                          content: investmentContent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              period,
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
  const _ReportScopeHeading({required this.title, required this.date});

  final String title;
  final Widget date;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
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
  const _SectionHeader({required this.title, this.scope});

  final String title;
  final String? scope;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    required this.share,
    required this.wide,
  });

  final int index;
  final String name;
  final double amount;
  final double share;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final amountLabel = Text(
      compassMoney(amount),
      key: Key('reports-category-$index-amount'),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: financePaletteOf(context).textMuted,
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
            amountLabel,
          SizedBox(
            width: wide ? _expenseShareColumnWidth : 52,
            child: Text(
              '${(share * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: financePaletteOf(context).textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetFlowLine extends StatelessWidget {
  const _NetFlowLine({
    super.key,
    required this.values,
    required this.height,
  });

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Semantics(
      label: '所选期间每月实际现金净流入',
      value: '最新月份 ${_signedMoney(values.last)}',
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: height,
              child: CustomPaint(
                painter: _NetFlowPainter(values, palette),
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
  const _NetFlowPainter(this.values, this.palette);

  final List<double> values;
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
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    final pointPaint = Paint();
    for (var index = 0; index < points.length; index++) {
      if (points.length > 1 &&
          (values[index] == 0 ||
              (points.length > 24 && index != points.length - 1))) {
        continue;
      }
      pointPaint.color = values[index] >= 0 ? palette.seed : palette.expense;
      canvas.drawCircle(points[index], 2.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(_NetFlowPainter oldDelegate) =>
      oldDelegate.palette != palette || !listEquals(oldDelegate.values, values);
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

Color _signColor(BuildContext context, double value, {int decimals = 2}) {
  final palette = financePaletteOf(context);
  if (_isZero(value, decimals)) {
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
