import 'package:flutter/material.dart';

import '../../core/data/finance_repository.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';

class NetWorthDetailPage extends StatelessWidget {
  const NetWorthDetailPage({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) => _ReportDetailShell(
        title: '净资产详情',
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: FinanceColors.compassBorder),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('2026年至今⌄'),
            ),
          ),
          const SizedBox(height: 28),
          const Row(
            children: [
              Expanded(
                child: _EquationValue(
                  label: '资产',
                  value: 'MYR 140,340',
                  color: FinanceColors.compassTeal,
                ),
              ),
              Text('−'),
              Expanded(
                child: _EquationValue(
                  label: '负债',
                  value: 'MYR 11,880',
                  color: FinanceColors.compassOrange,
                ),
              ),
              Text('='),
              Expanded(
                child: _EquationValue(
                  label: '净资产',
                  value: 'MYR 128,460',
                  color: FinanceColors.compassTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const CompassDistributionBar(
            values: [48750, 39850, 28230, 23510, -11880],
            colors: [
              FinanceColors.compassTeal,
              Color(0xFF3E7E8D),
              Color(0xFF315E48),
              Color(0xFF4D949B),
              FinanceColors.compassOrange,
            ],
            height: 18,
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: _MiniPercent(percent: '34.7%', label: '现金')),
              Expanded(child: _MiniPercent(percent: '28.4%', label: '投资')),
              Expanded(child: _MiniPercent(percent: '20.1%', label: '退休')),
              Expanded(child: _MiniPercent(percent: '16.8%', label: '其他资产')),
              Expanded(
                child: _MiniPercent(
                  percent: '-8.5%',
                  label: '负债',
                  color: FinanceColors.compassOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('资产', style: Theme.of(context).textTheme.titleLarge),
          const _NetWorthRow(
            icon: Icons.account_balance_wallet_outlined,
            title: '现金',
            amount: 'MYR 48,750',
            percent: '34.7%',
          ),
          const _NetWorthRow(
            icon: Icons.trending_up_rounded,
            title: '投资',
            amount: 'MYR 39,850',
            percent: '28.4%',
          ),
          const _NetWorthRow(
            icon: Icons.beach_access_outlined,
            title: '退休',
            amount: 'MYR 28,230',
            percent: '20.1%',
          ),
          const _NetWorthRow(
            icon: Icons.grid_view_rounded,
            title: '其他资产',
            amount: 'MYR 23,510',
            percent: '16.8%',
          ),
          const SizedBox(height: 18),
          Text('负债', style: Theme.of(context).textTheme.titleLarge),
          const _NetWorthRow(
            icon: Icons.credit_card_rounded,
            title: '信用卡',
            amount: 'MYR 11,880  未结清余额',
            percent: '8.5%',
            color: FinanceColors.compassOrange,
          ),
          Text('贷款账户启用后会显示在这里', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 26),
          compassHairline,
          const SizedBox(height: 20),
          Text('今年变化', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          const Text(
            '+MYR 9,320 · +7.8%',
            style: TextStyle(color: FinanceColors.compassTeal, fontSize: 20),
          ),
          const CompassAreaChart(
            values: [119, 117, 113, 115, 119, 124, 129, 126, 130, 134, 138],
            height: 150,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('1月1日\nMYR 119,140'), Text('7月16日\nMYR 128,460')],
          ),
        ],
      );
}

class SpendingAnalysisPage extends StatefulWidget {
  const SpendingAnalysisPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  State<SpendingAnalysisPage> createState() => _SpendingAnalysisPageState();
}

class _SpendingAnalysisPageState extends State<SpendingAnalysisPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => _ReportDetailShell(
        title: '支出分析',
        children: [
          Row(
            children: [
              const _OutlineChip(label: '最近 6 个月⌄'),
              const SizedBox(width: 10),
              Expanded(
                child: CompassSegmentedControl(
                  labels: const ['实际', '含预计'],
                  selectedIndex: selected,
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
              const SizedBox(width: 10),
              const _OutlineChip(label: '全部分类⌄'),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Expanded(
                child: _Metric(label: '总支出', value: 'MYR 22,680'),
              ),
              Expanded(
                child: _Metric(label: '月均', value: 'MYR 3,780', white: true),
              ),
              Expanded(
                child: _Metric(
                  label: '较前 6 个月',
                  value: '+7.4%',
                  orange: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          compassHairline,
          const SizedBox(height: 18),
          const _SixMonthBarChart(),
          const SizedBox(height: 26),
          Text('增长来源', style: Theme.of(context).textTheme.titleLarge),
          const _GrowthRow(
            icon: Icons.shopping_bag_outlined,
            title: '购物',
            amount: '+MYR 680',
            percent: '+21%',
            progress: .9,
          ),
          const _GrowthRow(
            icon: Icons.restaurant_outlined,
            title: '餐饮',
            amount: '+MYR 320',
            percent: '+9%',
            progress: .64,
          ),
          const _GrowthRow(
            icon: Icons.directions_bus_outlined,
            title: '交通',
            amount: '+MYR 140',
            percent: '+6%',
            progress: .46,
          ),
          const _GrowthRow(
            icon: Icons.shield_outlined,
            title: '保险',
            amount: '-MYR 210',
            percent: '-8%',
            progress: .4,
            positive: true,
          ),
          const CompassSettingsRow(
            icon: Icons.pie_chart_outline_rounded,
            title: '查看分类构成',
            onTap: _noop,
          ),
        ],
      );
}

class BudgetInsightPage extends StatelessWidget {
  const BudgetInsightPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) => _ReportDetailShell(
        title: '预算洞察',
        children: [
          const Center(child: _OutlineChip(label: '2026年7月⌄')),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '▣  今天 7月16日',
              style: TextStyle(color: FinanceColors.compassTeal),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  text: '时间已过 ',
                  style: TextStyle(fontSize: 21),
                  children: [
                    TextSpan(
                      text: '52%',
                      style: TextStyle(color: FinanceColors.compassTeal),
                    ),
                    TextSpan(text: ' · 预算已用 '),
                    TextSpan(
                      text: '70%',
                      style: TextStyle(color: FinanceColors.compassOrange),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text.rich(
              TextSpan(
                text: '支出速度',
                children: [
                  TextSpan(
                    text: '偏快',
                    style: TextStyle(color: FinanceColors.compassOrange),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const CompassAreaChart(
            values: [0, 8, 16, 21, 27, 34, 41, 48, 52, 58, 67, 72, 78],
            markerIndex: 8,
            markerColor: FinanceColors.compassOrange,
            lineColor: FinanceColors.compassOrange,
            height: 210,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1日'),
              Text('8日'),
              Text('16日'),
              Text('23日'),
              Text('31日')
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(
                child: _BigBudgetMetric(label: '剩余预算', value: 'MYR 2,240'),
              ),
              SizedBox(
                height: 60,
                child: VerticalDivider(color: FinanceColors.compassBorder),
              ),
              Expanded(
                child: _BigBudgetMetric(label: '建议可用', value: 'MYR 149/天'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          compassHairline,
          const SizedBox(height: 16),
          Text('节奏异常', style: Theme.of(context).textTheme.titleLarge),
          const _PaceRow(
            icon: Icons.shopping_bag_outlined,
            title: '购物',
            subtitle: '提前 6 天用完',
            value: '107%',
            orange: true,
          ),
          const _PaceRow(
            icon: Icons.restaurant_outlined,
            title: '餐饮',
            subtitle: '当前 MYR 8/天',
            value: '92%',
            orange: true,
          ),
          const _PaceRow(
            icon: Icons.directions_bus_outlined,
            title: '交通',
            subtitle: '节奏正常',
            value: '70%',
          ),
          const SizedBox(height: 18),
          Text('未来 15 天', style: Theme.of(context).textTheme.titleLarge),
          const CompassSettingsRow(
            icon: Icons.trending_up_rounded,
            title: '若维持当前速度，月底将超支 MYR 320',
            onTap: _noop,
          ),
          const SizedBox(height: 18),
          CompassPrimaryButton(
            label: '查看可调整金额',
            icon: Icons.tune_rounded,
            outlined: true,
            color: FinanceColors.compassTeal,
            onPressed: _noop,
          ),
        ],
      );
}

class CashFlowForecastPage extends StatelessWidget {
  const CashFlowForecastPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) => _ReportDetailShell(
        title: '现金流预测',
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _OutlineChip(label: '未来 30 天⌄'),
              SizedBox(width: 10),
              _OutlineChip(label: '基准预测⌄'),
            ],
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最低可用余额'),
                    SizedBox(height: 5),
                    Text(
                      'MYR 6,240',
                      style: TextStyle(
                        color: FinanceColors.compassOrange,
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('预计出现在 8月10日'),
                  ],
                ),
              ),
              SizedBox(
                height: 74,
                child: VerticalDivider(color: FinanceColors.compassBorder),
              ),
              SizedBox(width: 18),
              Text.rich(
                TextSpan(
                  text: '安全缓冲\n',
                  children: [
                    TextSpan(
                      text: '充足',
                      style: TextStyle(
                        color: FinanceColors.compassTeal,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Icon(
                Icons.verified_user_outlined,
                color: FinanceColors.compassTeal,
                size: 42,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const CompassAreaChart(
            values: [11, 10, 10, 15, 14, 13, 12, 10, 9, 8, 6, 7, 9, 10],
            markerIndex: 10,
            markerColor: FinanceColors.compassOrange,
            height: 190,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('7月16日'), Text('8月10日'), Text('8月15日')],
          ),
          const SizedBox(height: 22),
          Text('未来事件', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const _ForecastEvent(
            date: '7月25日',
            icon: Icons.badge_outlined,
            title: '工资入账',
            amount: '+MYR 8,500',
            balance: '余额 MYR 14,920',
            positive: true,
          ),
          const _ForecastEvent(
            date: '8月3日',
            icon: Icons.credit_card_rounded,
            title: '主力信用卡还款',
            amount: '-MYR 2,860',
            balance: '余额 MYR 10,740',
          ),
          const _ForecastEvent(
            date: '8月8日',
            icon: Icons.shield_outlined,
            title: '保险自动扣款',
            amount: '-MYR 380',
            balance: '余额 MYR 8,040',
          ),
          const _ForecastEvent(
            date: '8月10日',
            icon: Icons.home_outlined,
            title: '房租',
            amount: '-MYR 1,800',
            balance: '余额 MYR 6,240',
            warning: true,
          ),
          const _ForecastEvent(
            date: '8月15日',
            icon: Icons.calendar_month_outlined,
            title: '周期收入',
            amount: '+MYR 1,200',
            balance: '余额 MYR 7,440',
            positive: true,
          ),
          const SizedBox(height: 22),
          Center(
            child: Text('已计入 18 项固定与预计交易',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(onPressed: _noop, child: const Text('查看预测依据  ›')),
        ],
      );
}

class _ReportDetailShell extends StatelessWidget {
  const _ReportDetailShell({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: CompassBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    const CompassBackButton(),
                    const Spacer(),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      onPressed: _noop,
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      );
}

class _EquationValue extends StatelessWidget {
  const _EquationValue({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          FittedBox(
              child: Text(value, style: TextStyle(color: color, fontSize: 17))),
        ],
      );
}

class _MiniPercent extends StatelessWidget {
  const _MiniPercent({
    required this.percent,
    required this.label,
    this.color,
  });
  final String percent;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(percent, style: TextStyle(color: color, fontSize: 11)),
          Text(label, style: const TextStyle(fontSize: 9)),
        ],
      );
}

class _NetWorthRow extends StatelessWidget {
  const _NetWorthRow({
    required this.icon,
    required this.title,
    required this.amount,
    required this.percent,
    this.color = FinanceColors.compassTeal,
  });
  final IconData icon;
  final String title;
  final String amount;
  final String percent;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
        ),
        child: Row(
          children: [
            CompassIconBadge(icon: icon, size: 40, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(amount, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(percent, style: TextStyle(color: color, fontSize: 17)),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
}

class _OutlineChip extends StatelessWidget {
  const _OutlineChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: FinanceColors.compassBorder),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.white = false,
    this.orange = false,
  });
  final String label;
  final String value;
  final bool white;
  final bool orange;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: orange
                      ? FinanceColors.compassOrange
                      : white
                          ? FinanceColors.compassText
                          : FinanceColors.compassTeal,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SixMonthBarChart extends StatelessWidget {
  const _SixMonthBarChart();
  @override
  Widget build(BuildContext context) {
    const values = [3.1, 3.4, 3.6, 3.7, 4.0, 4.9];
    const labels = ['2月', '3月', '4月', '5月', '6月', '7月'];
    return SizedBox(
      height: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final orange = index == values.length - 1;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${values[index]}k', style: const TextStyle(fontSize: 10)),
                const SizedBox(height: 4),
                Container(
                  width: 24,
                  height: values[index] / 6 * 200,
                  color: orange
                      ? FinanceColors.compassOrange
                      : FinanceColors.compassTeal.withValues(alpha: .75),
                ),
                const SizedBox(height: 6),
                Text(labels[index], style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _GrowthRow extends StatelessWidget {
  const _GrowthRow({
    required this.icon,
    required this.title,
    required this.amount,
    required this.percent,
    required this.progress,
    this.positive = false,
  });
  final IconData icon;
  final String title;
  final String amount;
  final String percent;
  final double progress;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
        ),
        child: Row(
          children: [
            CompassIconBadge(icon: icon, size: 36, outlined: true),
            const SizedBox(width: 12),
            SizedBox(width: 50, child: Text(title)),
            Expanded(
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                color: FinanceColors.compassTeal,
                backgroundColor: FinanceColors.compassBorder,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    color: positive
                        ? FinanceColors.compassTeal
                        : FinanceColors.compassOrange,
                  ),
                ),
                Text(percent, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
      );
}

class _BigBudgetMetric extends StatelessWidget {
  const _BigBudgetMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: FinanceColors.compassTeal,
              fontSize: 22,
            ),
          ),
        ],
      );
}

class _PaceRow extends StatelessWidget {
  const _PaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.orange = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final bool orange;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
        ),
        child: Row(
          children: [
            CompassIconBadge(icon: icon, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(title), Text(subtitle)],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: orange
                    ? FinanceColors.compassOrange
                    : FinanceColors.compassTeal,
                fontSize: 19,
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
}

class _ForecastEvent extends StatelessWidget {
  const _ForecastEvent({
    required this.date,
    required this.icon,
    required this.title,
    required this.amount,
    required this.balance,
    this.positive = false,
    this.warning = false,
  });
  final String date;
  final IconData icon;
  final String title;
  final String amount;
  final String balance;
  final bool positive;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                date,
                style: TextStyle(
                  color: warning ? FinanceColors.compassOrange : null,
                ),
              ),
            ),
            CompassIconBadge(
              icon: icon,
              size: 38,
              color: warning
                  ? FinanceColors.compassOrange
                  : FinanceColors.compassTeal,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Text(balance, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                color: positive
                    ? FinanceColors.compassTeal
                    : FinanceColors.compassOrange,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      );
}

void _noop() {}
