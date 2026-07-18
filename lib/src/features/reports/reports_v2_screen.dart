import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';
import 'reports_screen.dart';

class ReportsV2Screen extends StatelessWidget {
  const ReportsV2Screen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final netWorth = repository.totalAssets();
    final startOfYear = repository.totalAssetsAt(DateTime(now.year, 1, 1));
    final growth = netWorth - startOfYear;
    final growthRate = startOfYear == 0 ? 0.0 : growth / startOfYear;
    final cash = repository.totalAssetsByGroup(ReportGroup.cash);
    final investment = repository.totalAssetsByGroup(ReportGroup.investment);
    final retirement = repository.totalAssetsByGroup(ReportGroup.retirement);
    final creditBalance = repository.totalAssetsByGroup(ReportGroup.credit);
    final debt = creditBalance < 0 ? -creditBalance : 0.0;
    final history = repository.totalAssetHistory();
    final chartValues = history.isEmpty
        ? <double>[netWorth]
        : history.map((point) => point.totalAssets).toList();
    final positiveTotal = cash + investment + retirement;
    String percent(double value) =>
        positiveTotal <= 0 ? '0%' : '${(value / positiveTotal * 100).round()}%';
    final monthKey = monthKeyFromDate(now);
    final income = repository.totalIncomeForMonth(monthKey);
    final expense = repository.totalExpenseForMonth(monthKey);
    final savingsRate = income <= 0 ? 0.0 : (income - expense) / income;
    final budget = repository.totalEffectiveBudgetForMonth(monthKey);
    final budgetUsed = repository.totalBudgetExpenseForMonth(monthKey) +
        repository.totalPlannedBudgetExpenseForMonth(monthKey);
    final budgetRate = budget <= 0 ? 0.0 : budgetUsed / budget;
    final forecast = repository.forecastSummary(months: 3);
    return ListView(
      padding: compassPagePadding.copyWith(bottom: 28),
      children: [
        CompassPageHeader(
          title: '报表',
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: FinanceColors.compassBorder),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text('${now.year}年至今'),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text: 'Finance Compass ${now.year} 年报表\n'
                      '净资产 ${compassMoney(netWorth)}\n'
                      '年内变化 ${compassMoney(growth)}',
                  subject: 'Finance Compass 报表',
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('净资产', style: Theme.of(context).textTheme.bodySmall),
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
        Text.rich(
          TextSpan(
            text: '今年增长 ',
            children: [
              TextSpan(
                text:
                    '${growthRate >= 0 ? '+' : ''}${(growthRate * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: growth >= 0
                      ? FinanceColors.compassTeal
                      : FinanceColors.compassOrange,
                ),
              ),
              const TextSpan(text: ' · '),
              TextSpan(
                text:
                    '${growth >= 0 ? '+' : ''} ${compassMoney(growth, decimals: 0)}',
                style: TextStyle(
                  color: growth >= 0
                      ? FinanceColors.compassTeal
                      : FinanceColors.compassOrange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(26, 16, 4, 12),
              child: CompassAreaChart(
                values: chartValues,
                height: 176,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Text(
                '${now.month}月${now.day}日  ${compassMoney(netWorth, decimals: 0)}',
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
              history.isEmpty
                  ? '${now.month}月'
                  : '${history.first.date.year}年${history.first.date.month}月',
              style: const TextStyle(fontSize: 10),
            ),
            Text(
              '${now.month}月${now.day}日',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('资产构成', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
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
        Text('负债为负值，将从资产中扣除。', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 18),
        compassHairline,
        const SizedBox(height: 18),
        Text('健康信号', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        _HealthSignal(
          icon: Icons.trending_up_rounded,
          title: '储蓄率',
          subtitle: '${now.month}月实际收入与支出计算',
          value: '${(savingsRate * 100).toStringAsFixed(0)}%',
          color: savingsRate >= 0
              ? FinanceColors.compassTeal
              : FinanceColors.compassOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportsScreen(repository: repository),
            ),
          ),
        ),
        _HealthSignal(
          icon: Icons.shopping_bag_outlined,
          title: '预算总体使用',
          subtitle: budget <= 0 ? '本月尚未设置预算' : '实际与预计交易合计',
          value:
              budget <= 0 ? '—' : '${(budgetRate * 100).toStringAsFixed(0)}%',
          color: budgetRate >= .8
              ? FinanceColors.compassOrange
              : FinanceColors.compassTeal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportsScreen(repository: repository),
            ),
          ),
        ),
        _HealthSignal(
          icon: Icons.account_balance_wallet_outlined,
          title: '近 3 个月平均月度现金流',
          subtitle: '根据已记录的收入与支出计算',
          value: compassMoney(forecast.averageMonthlySavings, decimals: 0),
          color: forecast.averageMonthlySavings >= 0
              ? FinanceColors.compassTeal
              : FinanceColors.compassOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportsScreen(repository: repository),
            ),
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportsScreen(repository: repository),
            ),
          ),
          child: CompassCard(
            child: Row(
              children: [
                const CompassIconBadge(
                  icon: Icons.lightbulb_outline_rounded,
                  outlined: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '按近 3 个月平均，每月可增加净资产约 ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  compassMoney(forecast.averageMonthlySavings, decimals: 0),
                  style: TextStyle(
                    color: forecast.averageMonthlySavings >= 0
                        ? FinanceColors.compassTeal
                        : FinanceColors.compassOrange,
                  ),
                ),
              ],
            ),
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

class _HealthSignal extends StatelessWidget {
  const _HealthSignal({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: FinanceColors.compassBorder),
            ),
          ),
          child: Row(
            children: [
              CompassIconBadge(icon: icon, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                value,
                style: TextStyle(color: color, fontSize: 20),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}
