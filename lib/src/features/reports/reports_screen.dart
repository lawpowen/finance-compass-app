import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/database/database_provider.dart';
import '../../core/models/account.dart';
import '../../core/models/monthly_summary.dart';
import '../../core/models/period_comparison.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/month_key.dart';
import '../../core/utils/month_range.dart';
import '../shared/finance_metric_card.dart';
import '../shared/period_comparison_card.dart';
import '../shared/section_card.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/simple_charts.dart';

enum ReportRangeType {
  thisMonth,
  thisQuarter,
  last3Months,
  last6Months,
  last12Months,
  thisYear,
  lastYear,
  allTime
}

enum ReportMeasureMode { monthly, cumulative }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRangeType rangeType = ReportRangeType.thisYear;
  ReportMeasureMode measureMode = ReportMeasureMode.monthly;
  List<String> _sectionOrder = [];
  bool _isLoadingOrder = true;

  static const _defaultSectionOrder = [
    'overview',
    'trends',
    'budget',
    'expense',
    'asset',
    'forecast',
  ];

  @override
  void initState() {
    super.initState();
    _loadSectionOrder();
  }

  Future<void> _loadSectionOrder() async {
    final raw =
        await DatabaseProvider.instance.getMetaValue('report_section_order_v2');
    if (raw != null && mounted) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        setState(() {
          _sectionOrder = decoded.cast<String>();
          _isLoadingOrder = false;
        });
      } catch (_) {
        setState(() {
          _sectionOrder = List.from(_defaultSectionOrder);
          _isLoadingOrder = false;
        });
      }
    } else if (mounted) {
      setState(() {
        _sectionOrder = List.from(_defaultSectionOrder);
        _isLoadingOrder = false;
      });
    }
  }

  Future<void> _saveSectionOrder(List<String> order) async {
    setState(() {
      _sectionOrder = order;
    });
    await DatabaseProvider.instance.setMetaValue(
      'report_section_order_v2',
      jsonEncode(order),
    );
  }

  void _reorderSections(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final newOrder = List<String>.from(_sectionOrder);
    final item = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, item);
    _saveSectionOrder(newOrder);
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final now = DateTime.now();
    final currentMonthKey = monthKeyFromDate(now);
    final monthKeys = _monthKeysForRange(rangeType, now);

    final rawSummaries = monthKeys.map(
      (monthKey) {
        final cashFlow = repository.actualCashFlowSummaryForMonth(monthKey);
        return MonthlySummary(
          monthKey: monthKey,
          income: cashFlow.inflow,
          expense: cashFlow.outflow,
        );
      },
    ).toList();
    final displaySummaries = measureMode == ReportMeasureMode.monthly
        ? rawSummaries
        : _toCumulativeSummaries(rawSummaries);

    final currentCashFlow =
        repository.actualCashFlowSummaryForMonth(currentMonthKey);
    final currentIncome = currentCashFlow.inflow;
    final currentExpense = currentCashFlow.outflow;
    final lastMonth = DateTime(now.year, now.month - 1);
    final lastMonthKey = monthKeyFromDate(lastMonth);
    final lastCashFlow = repository.actualCashFlowSummaryForMonth(lastMonthKey);
    final lastIncome = lastCashFlow.inflow;
    final lastExpense = lastCashFlow.outflow;

    if (_isLoadingOrder) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = <MapEntry<String, Widget>>[
      // 1. 快速概览
      MapEntry(
          'overview',
          _QuickOverviewSection(
            repository: repository,
            currentMonthKey: currentMonthKey,
            currentIncome: currentIncome,
            currentExpense: currentExpense,
            previousMonthKey: lastMonthKey,
            previousIncome: lastIncome,
            previousExpense: lastExpense,
          )),
      // 2. 趋势分析
      MapEntry(
          'trends',
          _TrendAnalysisSection(
            repository: repository,
            summaries: displaySummaries,
            rawSummaries: rawSummaries,
            measureMode: measureMode,
            rangeType: rangeType,
            onMeasureChanged: (value) => setState(() => measureMode = value),
            onRangeChanged: (value) => setState(() => rangeType = value),
          )),
      // 3. 预算洞察
      MapEntry(
          'budget',
          _BudgetInsightsSection(
            repository: repository,
            monthKey: currentMonthKey,
          )),
      // 4. 支出分析
      MapEntry(
          'expense',
          _ExpenseAnalysisSection(
            repository: repository,
            currentMonthKey: currentMonthKey,
            monthKeys: monthKeys,
          )),
      // 5. 资产健康
      MapEntry(
          'asset',
          _AssetHealthSection(
            repository: repository,
          )),
      // 6. 未来预测
      MapEntry(
          'forecast',
          _FutureForecastSection(
            repository: repository,
          )),
    ];

    // Sort sections by saved order
    final sortedSections = <MapEntry<String, Widget>>[];
    for (final sectionId in _sectionOrder) {
      final section = sections.where((s) => s.key == sectionId).firstOrNull;
      if (section != null) {
        sortedSections.add(section);
      }
    }
    // Add any new sections not in saved order
    for (final section in sections) {
      if (!_sectionOrder.contains(section.key)) {
        sortedSections.add(section);
      }
    }

    return ReorderableListView(
      padding: const EdgeInsets.all(16),
      buildDefaultDragHandles: false,
      onReorder: _reorderSections,
      children: sortedSections.asMap().entries.map((entry) {
        final index = entry.key;
        final section = entry.value;
        return Container(
          key: ValueKey('report-section-${section.key}'),
          margin: const EdgeInsets.only(bottom: 16),
          child: Stack(
            children: [
              section.value,
              Positioned(
                top: 12,
                right: 12,
                child: ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<String> _monthKeysForRange(ReportRangeType rangeType, DateTime now) {
    switch (rangeType) {
      case ReportRangeType.thisMonth:
        return [monthKeyFromDate(now)];
      case ReportRangeType.thisQuarter:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return List.generate(now.month - quarterStartMonth + 1,
            (i) => monthKeyFromDate(DateTime(now.year, quarterStartMonth + i)));
      case ReportRangeType.last3Months:
        return recentMonthKeys(count: 3, anchor: now);
      case ReportRangeType.last6Months:
        return recentMonthKeys(count: 6, anchor: now);
      case ReportRangeType.last12Months:
        return recentMonthKeys(count: 12, anchor: now);
      case ReportRangeType.thisYear:
        return List.generate(
            now.month, (i) => monthKeyFromDate(DateTime(now.year, i + 1)));
      case ReportRangeType.lastYear:
        return List.generate(
            12, (i) => monthKeyFromDate(DateTime(now.year - 1, i + 1)));
      case ReportRangeType.allTime:
        final allMonths = <String>{};
        for (final transaction in widget.repository.transactions) {
          allMonths.add(monthKeyFromDate(transaction.transactionDate));
        }
        return allMonths.toList()..sort();
    }
  }

  List<MonthlySummary> _toCumulativeSummaries(List<MonthlySummary> input) {
    var runningIncome = 0.0;
    var runningExpense = 0.0;
    return input.map((summary) {
      runningIncome += summary.income;
      runningExpense += summary.expense;
      return MonthlySummary(
        monthKey: summary.monthKey,
        income: runningIncome,
        expense: runningExpense,
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════
// Section 1: Quick Overview
// ═══════════════════════════════════════════════════════════════

class _QuickOverviewSection extends StatelessWidget {
  const _QuickOverviewSection({
    required this.repository,
    required this.currentMonthKey,
    required this.currentIncome,
    required this.currentExpense,
    required this.previousMonthKey,
    required this.previousIncome,
    required this.previousExpense,
  });

  final FinanceRepository repository;
  final String currentMonthKey;
  final double currentIncome;
  final double currentExpense;
  final String previousMonthKey;
  final double previousIncome;
  final double previousExpense;

  @override
  Widget build(BuildContext context) {
    final netBalance = currentIncome - currentExpense;
    final totalAssets = repository.totalAssets();
    final incomeComparison = PeriodComparison(
      currentValue: currentIncome,
      previousValue: previousIncome,
      lowerIsBetter: false,
    );
    final expenseComparison = PeriodComparison(
      currentValue: currentExpense,
      previousValue: previousExpense,
      lowerIsBetter: true,
    );

    return SectionCard(
      title: '快速概览',
      subtitle: '$currentMonthKey 本月表现',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceMetricGrid(
            minItemWidth: 120,
            maxColumns: 4,
            children: [
              FinanceMetricCard(
                label: '现金流入',
                value: formatMoney(currentIncome),
                color: FinanceColors.income,
              ),
              FinanceMetricCard(
                label: '现金流出',
                value: formatMoney(currentExpense),
                color: FinanceColors.expense,
              ),
              FinanceMetricCard(
                label: '结余',
                value: formatMoney(netBalance),
                color: netBalance >= 0
                    ? FinanceColors.income
                    : FinanceColors.expense,
              ),
              FinanceMetricCard(
                label: '总资产',
                value: formatMoney(totalAssets),
                color: FinanceColors.info,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '较上月',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            '同时查看实际金额、金额差与变化率',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final useTwoColumns = constraints.maxWidth >= 620;
              final cardWidth = useTwoColumns
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: PeriodComparisonCard(
                      label: '现金流入对比',
                      currentPeriodLabel: '本月 $currentMonthKey',
                      previousPeriodLabel: '上月 $previousMonthKey',
                      comparison: incomeComparison,
                      accentColor: FinanceColors.income,
                      icon: Icons.south_west_rounded,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: PeriodComparisonCard(
                      label: '现金流出对比',
                      currentPeriodLabel: '本月 $currentMonthKey',
                      previousPeriodLabel: '上月 $previousMonthKey',
                      comparison: expenseComparison,
                      accentColor: FinanceColors.expense,
                      icon: Icons.north_east_rounded,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section 2: Trend Analysis
// ═══════════════════════════════════════════════════════════════

class _TrendAnalysisSection extends StatelessWidget {
  const _TrendAnalysisSection({
    required this.repository,
    required this.summaries,
    required this.rawSummaries,
    required this.measureMode,
    required this.rangeType,
    required this.onMeasureChanged,
    required this.onRangeChanged,
  });

  final FinanceRepository repository;
  final List<MonthlySummary> summaries;
  final List<MonthlySummary> rawSummaries;
  final ReportMeasureMode measureMode;
  final ReportRangeType rangeType;
  final ValueChanged<ReportMeasureMode> onMeasureChanged;
  final ValueChanged<ReportRangeType> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final totalIncome = rawSummaries.fold<double>(
      0,
      (total, summary) => total + summary.income,
    );
    final totalExpense = rawSummaries.fold<double>(
      0,
      (total, summary) => total + summary.expense,
    );
    final totalNet = totalIncome - totalExpense;
    final savingsRate = totalIncome > 0 ? totalNet / totalIncome * 100 : null;

    return SectionCard(
      title: '趋势分析',
      subtitle:
          measureMode == ReportMeasureMode.monthly ? '月度实际现金流趋势' : '累计实际现金流趋势',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('月度'),
                selected: measureMode == ReportMeasureMode.monthly,
                onSelected: (_) => onMeasureChanged(ReportMeasureMode.monthly),
              ),
              ChoiceChip(
                label: const Text('累计'),
                selected: measureMode == ReportMeasureMode.cumulative,
                onSelected: (_) =>
                    onMeasureChanged(ReportMeasureMode.cumulative),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('本月'),
                selected: rangeType == ReportRangeType.thisMonth,
                onSelected: (_) => onRangeChanged(ReportRangeType.thisMonth),
              ),
              ChoiceChip(
                label: const Text('本季'),
                selected: rangeType == ReportRangeType.thisQuarter,
                onSelected: (_) => onRangeChanged(ReportRangeType.thisQuarter),
              ),
              ChoiceChip(
                label: const Text('本年'),
                selected: rangeType == ReportRangeType.thisYear,
                onSelected: (_) => onRangeChanged(ReportRangeType.thisYear),
              ),
              ChoiceChip(
                label: const Text('去年'),
                selected: rangeType == ReportRangeType.lastYear,
                onSelected: (_) => onRangeChanged(ReportRangeType.lastYear),
              ),
              ChoiceChip(
                label: const Text('3月'),
                selected: rangeType == ReportRangeType.last3Months,
                onSelected: (_) => onRangeChanged(ReportRangeType.last3Months),
              ),
              ChoiceChip(
                label: const Text('6月'),
                selected: rangeType == ReportRangeType.last6Months,
                onSelected: (_) => onRangeChanged(ReportRangeType.last6Months),
              ),
              ChoiceChip(
                label: const Text('12月'),
                selected: rangeType == ReportRangeType.last12Months,
                onSelected: (_) => onRangeChanged(ReportRangeType.last12Months),
              ),
              ChoiceChip(
                label: const Text('全部'),
                selected: rangeType == ReportRangeType.allTime,
                onSelected: (_) => onRangeChanged(ReportRangeType.allTime),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('所选范围汇总', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          FinanceMetricGrid(
            minItemWidth: 120,
            maxColumns: 4,
            children: [
              FinanceMetricCard(
                label: '现金流入合计',
                value: formatMoney(totalIncome),
                color: FinanceColors.income,
              ),
              FinanceMetricCard(
                label: '现金流出合计',
                value: formatMoney(totalExpense),
                color: FinanceColors.expense,
              ),
              FinanceMetricCard(
                label: '结余合计',
                value: formatMoney(totalNet),
                color: totalNet >= 0
                    ? FinanceColors.income
                    : FinanceColors.expense,
              ),
              FinanceMetricCard(
                label: '现金结余率',
                value: savingsRate == null
                    ? '不可用'
                    : '${savingsRate.toStringAsFixed(1)}%',
                color: FinanceColors.info,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (summaries.length < 2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前范围只有 1 个数据点，准确值已在上方展示；选择更长范围可查看趋势。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            SizedBox(
              height: 200,
              child: _TrendChart(summaries: summaries),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(color: FinanceColors.income, label: '现金流入'),
                SizedBox(width: 16),
                _LegendItem(color: FinanceColors.expense, label: '现金流出'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.summaries});

  final List<MonthlySummary> summaries;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    final maxValue = summaries.fold<double>(
        0, (max, s) => math.max(max, math.max(s.income, s.expense)));

    return CustomPaint(
      painter: _TrendChartPainter(
        summaries: summaries,
        maxValue: maxValue,
        incomeColor: FinanceColors.income,
        expenseColor: FinanceColors.expense,
      ),
      child: Container(),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.summaries,
    required this.maxValue,
    required this.incomeColor,
    required this.expenseColor,
  });

  final List<MonthlySummary> summaries;
  final double maxValue;
  final Color incomeColor;
  final Color expenseColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (summaries.isEmpty || maxValue == 0) return;

    final incomePaint = Paint()
      ..color = incomeColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final expensePaint = Paint()
      ..color = expenseColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final width = size.width;
    final height = size.height;
    final stepX = width / (summaries.length - 1);

    final incomePath = Path();
    final expensePath = Path();

    for (var i = 0; i < summaries.length; i++) {
      final x = i * stepX;
      final incomeY = height - (summaries[i].income / maxValue * height);
      final expenseY = height - (summaries[i].expense / maxValue * height);

      if (i == 0) {
        incomePath.moveTo(x, incomeY);
        expensePath.moveTo(x, expenseY);
      } else {
        incomePath.lineTo(x, incomeY);
        expensePath.lineTo(x, expenseY);
      }
    }

    canvas.drawPath(incomePath, incomePaint);
    canvas.drawPath(expensePath, expensePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section 3: Budget Insights
// ═══════════════════════════════════════════════════════════════

class _BudgetInsightsSection extends StatelessWidget {
  const _BudgetInsightsSection({
    required this.repository,
    required this.monthKey,
  });

  final FinanceRepository repository;
  final String monthKey;

  @override
  Widget build(BuildContext context) {
    final activeBudgets = repository.activeBudgetsForMonth(monthKey);

    if (activeBudgets.isEmpty) {
      return SectionCard(
        title: '预算洞察',
        subtitle: monthKey,
        child: const Text('暂无预算数据', style: TextStyle(color: Colors.grey)),
      );
    }

    // Sort by usage ratio
    final budgetData = activeBudgets.map((budget) {
      final effective = repository.effectiveBudgetForMonth(budget, monthKey);
      final spent =
          repository.expenseTotalForCategory(budget.categoryId, monthKey);
      final ratio = effective > 0 ? spent / effective : 0.0;
      final variance = effective - spent;
      return _BudgetItem(
        name: repository.categoryName(budget.categoryId),
        spent: spent,
        budget: effective,
        ratio: ratio,
        variance: variance,
      );
    }).toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

    final totalBudget = activeBudgets.fold<double>(
        0, (sum, b) => sum + repository.effectiveBudgetForMonth(b, monthKey));
    final totalSpent = activeBudgets.fold<double>(
        0,
        (sum, b) =>
            sum + repository.expenseTotalForCategory(b.categoryId, monthKey));
    final overallRatio = totalBudget > 0 ? totalSpent / totalBudget : 0.0;

    return SectionCard(
      title: '预算洞察',
      subtitle: '$monthKey · 总体使用 ${(overallRatio * 100).toStringAsFixed(0)}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall progress
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: overallRatio.clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(
                overallRatio > 1.0
                    ? FinanceColors.expense
                    : FinanceColors.income,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // Top over-budget categories
          if (budgetData.any((b) => b.ratio > 1.0)) ...[
            Text('超支类别',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.expense)),
            const SizedBox(height: 8),
            ...budgetData
                .where((b) => b.ratio > 1.0)
                .take(3)
                .map((b) => _BudgetInsightItem(
                      name: b.name,
                      ratio: b.ratio,
                      variance: b.variance,
                      isOver: true,
                    )),
            const SizedBox(height: 12),
          ],
          // Top under-budget categories
          if (budgetData.any((b) => b.ratio <= 0.8)) ...[
            Text('节省类别',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.income)),
            const SizedBox(height: 8),
            ...budgetData
                .where((b) => b.ratio <= 0.8)
                .take(3)
                .map((b) => _BudgetInsightItem(
                      name: b.name,
                      ratio: b.ratio,
                      variance: b.variance,
                      isOver: false,
                    )),
          ],
        ],
      ),
    );
  }
}

class _BudgetItem {
  final String name;
  final double spent;
  final double budget;
  final double ratio;
  final double variance;

  _BudgetItem({
    required this.name,
    required this.spent,
    required this.budget,
    required this.ratio,
    required this.variance,
  });
}

class _BudgetInsightItem extends StatelessWidget {
  const _BudgetInsightItem({
    required this.name,
    required this.ratio,
    required this.variance,
    required this.isOver,
  });

  final String name;
  final double ratio;
  final double variance;
  final bool isOver;

  @override
  Widget build(BuildContext context) {
    final color = isOver ? FinanceColors.expense : FinanceColors.income;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            '${(ratio * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${variance >= 0 ? '剩余' : '超支'} ${formatMoney(variance.abs())}',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section 4: Expense Analysis
// ═══════════════════════════════════════════════════════════════

class _ExpenseAnalysisSection extends StatelessWidget {
  const _ExpenseAnalysisSection({
    required this.repository,
    required this.currentMonthKey,
    required this.monthKeys,
  });

  final FinanceRepository repository;
  final String currentMonthKey;
  final List<String> monthKeys;

  @override
  Widget build(BuildContext context) {
    final categoryTotals =
        repository.actualCashOutflowByCategoryForMonths(monthKeys);

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalExpense =
        repository.actualCashFlowSummaryForMonths(monthKeys).outflow;

    // Account ranking
    final accountExpenses =
        repository.actualCashOutflowByAccountForMonth(currentMonthKey);
    final sortedAccounts = accountExpenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final colors = FinanceColors.categoryPalette;

    // Prepare pie chart data
    final categoryPieData = sortedCategories.take(8).map((e) {
      final name = e.key == FinanceRepository.uncategorizedCashOutflowKey
          ? '转账还款等未分类现金流出'
          : repository.categoryName(e.key);
      final percentage =
          totalExpense > 0 ? (e.value / totalExpense * 100) : 0.0;
      return _PieData(label: name, value: e.value, percentage: percentage);
    }).toList();

    final accountPieData = sortedAccounts.take(6).map((e) {
      final name = repository.accountName(e.key);
      final percentage =
          totalExpense > 0 ? (e.value / totalExpense * 100) : 0.0;
      return _PieData(label: name, value: e.value, percentage: percentage);
    }).toList();

    return SectionCard(
      title: '现金流出分析',
      subtitle: monthKeys.length == 1
          ? '$currentMonthKey 本月实际现金流出 ${formatMoney(totalExpense)}'
          : '${monthKeys.first} 至 ${monthKeys.last} 实际现金流出 ${formatMoney(totalExpense)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category pie chart
          Text('现金流出分类',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (categoryPieData.isNotEmpty)
            Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: _SimplePieChart(
                    values: categoryPieData.map((d) => d.value).toList(),
                    colors: colors,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PieLegend(
                    items: categoryPieData,
                    colors: colors,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Account pie chart
          if (sortedAccounts.isNotEmpty) ...[
            Text('现金账户流出',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: _SimplePieChart(
                    values: accountPieData.map((d) => d.value).toList(),
                    colors: List.generate(accountPieData.length,
                        (i) => colors[(i + 5) % colors.length]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PieLegend(
                    items: accountPieData,
                    colors: List.generate(accountPieData.length,
                        (i) => colors[(i + 5) % colors.length]),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseBar extends StatelessWidget {
  const _ExpenseBar({
    required this.label,
    required this.amount,
    required this.percentage,
    required this.color,
  });

  final String label;
  final double amount;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                '${formatMoney(amount)} (${percentage.toStringAsFixed(1)}%)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (percentage / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section 5: Asset Health
// ═══════════════════════════════════════════════════════════════

class _AssetHealthSection extends StatelessWidget {
  const _AssetHealthSection({required this.repository});

  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) {
    final totalAssets = repository.totalAssets();
    final cashBalance = repository.totalAssetsByGroup(ReportGroup.cash);
    final creditDebt = repository.totalAssetsByGroup(ReportGroup.credit);
    final investmentBalance =
        repository.totalAssetsByGroup(ReportGroup.investment);
    final retirementBalance =
        repository.totalAssetsByGroup(ReportGroup.retirement);

    // Investment P&L
    final investmentAccounts = repository.investmentAccounts();
    final cutoffDate = repository.currentMonthCutoffDate();
    double totalMarketValue = 0;
    double totalRemainingCostBasis = 0;
    for (final account in investmentAccounts) {
      totalMarketValue += repository.convertToBase(
        repository.accountBalanceAt(account.id, cutoffDate),
        account.currency,
      );
      totalRemainingCostBasis += repository.convertToBase(
        repository.remainingCostBasisForAccount(
          account.id,
          upToDate: cutoffDate,
        ),
        account.currency,
      );
    }
    final unrealizedPnL = totalMarketValue - totalRemainingCostBasis;
    final pnlRatio = totalRemainingCostBasis > 0
        ? (unrealizedPnL / totalRemainingCostBasis * 100)
        : 0.0;

    // Asset trend
    final history = repository.totalAssetHistory();

    // Asset distribution pie data
    final assetPieData = [
      _PieData(
          label: '现金',
          value: cashBalance,
          percentage: totalAssets > 0 ? (cashBalance / totalAssets * 100) : 0),
      _PieData(
          label: '信用负债',
          value: creditDebt.abs(),
          percentage:
              totalAssets > 0 ? (creditDebt.abs() / totalAssets * 100) : 0),
      _PieData(
          label: '投资',
          value: investmentBalance,
          percentage:
              totalAssets > 0 ? (investmentBalance / totalAssets * 100) : 0),
      _PieData(
          label: '退休',
          value: retirementBalance,
          percentage:
              totalAssets > 0 ? (retirementBalance / totalAssets * 100) : 0),
    ];

    return SectionCard(
      title: '资产健康',
      subtitle: '净资产 ${formatMoney(totalAssets)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Asset distribution with pie chart
          Text('资产分布',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: _SimplePieChart(
                  values: assetPieData.map((d) => d.value).toList(),
                  colors: [
                    FinanceColors.cash,
                    FinanceColors.credit,
                    FinanceColors.investment,
                    FinanceColors.retirement
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PieLegend(
                  items: assetPieData,
                  colors: [
                    FinanceColors.cash,
                    FinanceColors.credit,
                    FinanceColors.investment,
                    FinanceColors.retirement
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Investment performance
          if (investmentAccounts.isNotEmpty) ...[
            Text('投资表现',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricItem(
                    label: '总市值',
                    value: formatMoney(totalMarketValue),
                    color: FinanceColors.info,
                  ),
                ),
                Expanded(
                  child: _MetricItem(
                    label: '未实现盈亏',
                    value:
                        '${formatMoney(unrealizedPnL)} (${pnlRatio.toStringAsFixed(1)}%)',
                    color: unrealizedPnL >= 0
                        ? FinanceColors.income
                        : FinanceColors.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Investment sub-categories
            Text('投资子类',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...investmentAccounts.map((account) {
              final balance =
                  repository.accountBalanceAt(account.id, cutoffDate);
              final percentage = totalMarketValue > 0
                  ? (balance / totalMarketValue * 100)
                  : 0.0;
              return _AssetBar(
                label: account.name,
                amount: balance,
                percentage: percentage,
                color: FinanceColors.investment,
              );
            }),
            const SizedBox(height: 16),
          ],
          // Asset trend
          if (history.isNotEmpty) ...[
            Text('资产趋势',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: SimpleLineChart(
                points: history
                    .map(
                        (p) => ChartPoint(label: p.label, value: p.totalAssets))
                    .toList(),
                amountBuilder: formatMoneyValue,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetBar extends StatelessWidget {
  const _AssetBar({
    required this.label,
    required this.amount,
    required this.color,
    this.percentage,
  });

  final String label;
  final double amount;
  final Color color;
  final double? percentage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                percentage != null
                    ? '${formatMoney(amount)} (${percentage!.toStringAsFixed(1)}%)'
                    : formatMoney(amount),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700]),
              ),
            ],
          ),
          if (percentage != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (percentage! / 100).clamp(0.0, 1.0),
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section 6: Future Forecast
// ═══════════════════════════════════════════════════════════════

class _FutureForecastSection extends StatelessWidget {
  const _FutureForecastSection({required this.repository});

  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) {
    final forecast = repository.forecastSummary(months: 3);
    final projection =
        repository.futureCashFlowProjection(months: 4).skip(1).toList();
    final goalSummaries = repository.assetGoalSummaries();
    final now = DateTime.now();

    // Calculate historical average (last 3 months)
    final historyMonths = List.generate(3, (i) {
      final date = DateTime(now.year, now.month - 2 + i);
      return monthKeyFromDate(date);
    });
    double avgIncome = 0;
    double avgExpense = 0;
    for (final month in historyMonths) {
      final cashFlow = repository.actualCashFlowSummaryForMonth(month);
      avgIncome += cashFlow.inflow;
      avgExpense += cashFlow.outflow;
    }
    avgIncome /= 3;
    avgExpense /= 3;

    // Recent 3 months actual
    final recentMonths = List.generate(3, (i) {
      final date = DateTime(now.year, now.month - 2 + i);
      return monthKeyFromDate(date);
    });
    final recentData = recentMonths.map((month) {
      final cashFlow = repository.actualCashFlowSummaryForMonth(month);
      return _MonthlyData(
        monthKey: month,
        income: cashFlow.inflow,
        expense: cashFlow.outflow,
      );
    }).toList();

    return SectionCard(
      title: '财务预测',
      subtitle: '基于历史数据的分析与预测',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Savings rate
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FinanceColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: FinanceColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.savings_outlined,
                    size: 24, color: FinanceColors.info),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('月均现金结余',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text(
                        formatMoney(forecast.averageMonthlySavings),
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('现金结余率',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600])),
                    Text(
                      forecast.averageMonthlyIncome > 0
                          ? '${(forecast.averageMonthlySavings / forecast.averageMonthlyIncome * 100).toStringAsFixed(1)}%'
                          : '0%',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Historical average
          Text('历史平均（近3月）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _ForecastItem(
                      label: '月均现金流入',
                      value: formatMoney(avgIncome),
                      color: FinanceColors.income)),
              const SizedBox(width: 12),
              Expanded(
                  child: _ForecastItem(
                      label: '月均现金流出',
                      value: formatMoney(avgExpense),
                      color: FinanceColors.expense)),
              const SizedBox(width: 12),
              Expanded(
                  child: _ForecastItem(
                      label: '月均现金结余',
                      value: formatMoney(avgIncome - avgExpense),
                      color: FinanceColors.info)),
            ],
          ),
          const SizedBox(height: 16),
          // Recent 3 months
          Text('近3个月实际现金流',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...recentData.map((data) => _MonthlyDataCard(data: data)),
          const SizedBox(height: 16),
          // Future 3 months prediction
          Text('未来3个月预测',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...projection.map((point) => _ForecastDataCard(point: point)),
          const SizedBox(height: 16),
          // Goal progress with line chart
          if (goalSummaries.isNotEmpty) ...[
            Text('储蓄目标',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...goalSummaries.map((g) {
              final pct = g.progressRatio * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(g.goal.name,
                                style: const TextStyle(fontSize: 13))),
                        Text('${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: pct >= 100
                                    ? FinanceColors.income
                                    : FinanceColors.info)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: math.min(g.progressRatio, 1.0),
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(pct >= 100
                            ? FinanceColors.income
                            : FinanceColors.info),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: _GoalProgressChart(goal: g, forecast: forecast),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Pie Chart Components
// ═══════════════════════════════════════════════════════════════

class _PieData {
  final String label;
  final double value;
  final double percentage;

  _PieData(
      {required this.label, required this.value, required this.percentage});
}

class _SimplePieChart extends StatelessWidget {
  const _SimplePieChart({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (sum, v) => sum + v);
    if (total == 0) return const SizedBox();

    return CustomPaint(
      painter: _PieChartPainter(values: values, colors: colors, total: total),
      child: Container(),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({
    required this.values,
    required this.colors,
    required this.total,
  });

  final List<double> values;
  final List<Color> colors;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    var startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _PieLegend extends StatelessWidget {
  const _PieLegend({required this.items, required this.colors});

  final List<_PieData> items;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors[index % colors.length],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.label,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${item.percentage.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Forecast Components
// ═══════════════════════════════════════════════════════════════

class _MonthlyData {
  final String monthKey;
  final double income;
  final double expense;

  _MonthlyData(
      {required this.monthKey, required this.income, required this.expense});
}

class _ForecastItem extends StatelessWidget {
  const _ForecastItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _GoalProgressChart extends StatelessWidget {
  const _GoalProgressChart({required this.goal, required this.forecast});

  final dynamic goal;
  final dynamic forecast;

  @override
  Widget build(BuildContext context) {
    final targetAmount = goal.goal.targetAmount;
    final currentAmount = goal.currentAssets;
    final monthlySavings = forecast.averageMonthlySavings;

    if (monthlySavings <= 0) {
      return Center(
        child: Text('需要正储蓄才能达成目标',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      );
    }

    final remaining = targetAmount - currentAmount;
    final monthsNeeded = (remaining / monthlySavings).ceil();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('剩余 ${formatMoney(remaining)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              Text('月均 ${formatMoney(monthlySavings)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
          Text(
            '预计 $monthsNeeded 个月',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: FinanceColors.info),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Responsive Data Cards
// ═══════════════════════════════════════════════════════════════

class _MonthlyDataCard extends StatelessWidget {
  const _MonthlyDataCard({required this.data});

  final _MonthlyData data;

  @override
  Widget build(BuildContext context) {
    final netAmount = data.income - data.expense;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.monthKey,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniMetric(
                  label: '现金流入',
                  value: formatMoney(data.income),
                  color: FinanceColors.income),
              _MiniMetric(
                  label: '现金流出',
                  value: formatMoney(data.expense),
                  color: FinanceColors.expense),
              _MiniMetric(
                label: '净额',
                value: formatMoney(netAmount),
                color: netAmount >= 0
                    ? FinanceColors.income
                    : FinanceColors.expense,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForecastDataCard extends StatelessWidget {
  const _ForecastDataCard({required this.point});

  final dynamic point;

  @override
  Widget build(BuildContext context) {
    final netAmount = point.income - point.expense;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(point.monthKey,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniMetric(
                  label: '现金流入',
                  value: formatMoney(point.income),
                  color: FinanceColors.income),
              _MiniMetric(
                  label: '现金流出',
                  value: formatMoney(point.expense),
                  color: FinanceColors.expense),
              _MiniMetric(
                label: '净额',
                value: formatMoney(netAmount),
                color: netAmount >= 0
                    ? FinanceColors.income
                    : FinanceColors.expense,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
