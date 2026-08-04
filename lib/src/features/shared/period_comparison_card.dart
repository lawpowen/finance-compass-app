import 'package:flutter/material.dart';

import '../../core/models/period_comparison.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/currency_formatter.dart';

class PeriodComparisonCard extends StatelessWidget {
  const PeriodComparisonCard({
    super.key,
    required this.label,
    required this.currentPeriodLabel,
    required this.previousPeriodLabel,
    required this.comparison,
    required this.accentColor,
    required this.icon,
  });

  final String label;
  final String currentPeriodLabel;
  final String previousPeriodLabel;
  final PeriodComparison comparison;
  final Color accentColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = comparison.direction;
    final statusColor = switch (comparison.isFavorable) {
      true => FinanceColors.income,
      false => FinanceColors.expense,
      null => theme.colorScheme.onSurfaceVariant,
    };
    final directionIcon = switch (direction) {
      PeriodChangeDirection.increase => Icons.arrow_upward_rounded,
      PeriodChangeDirection.decrease => Icons.arrow_downward_rounded,
      PeriodChangeDirection.unchanged => Icons.remove_rounded,
    };
    final directionText = switch (direction) {
      PeriodChangeDirection.increase => '增加',
      PeriodChangeDirection.decrease => '减少',
      PeriodChangeDirection.unchanged => '持平',
    };
    final percentage = comparison.percentageChange;
    final percentageText = percentage == null
        ? '百分比不可用'
        : '${percentage > 0 ? '+' : ''}${percentage.toStringAsFixed(1)}%';
    final semanticSummary =
        '$label，$currentPeriodLabel ${formatMoney(comparison.currentValue)}，'
        '$previousPeriodLabel ${formatMoney(comparison.previousValue)}，'
        '$directionText ${formatMoney(comparison.delta.abs())}，$percentageText';

    return Semantics(
      container: true,
      label: semanticSummary,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: accentColor),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(directionIcon, size: 14, color: statusColor),
                      const SizedBox(width: 3),
                      Text(
                        percentageText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PeriodValue(
                    label: currentPeriodLabel,
                    value: comparison.currentValue,
                    emphasized: true,
                  ),
                ),
                Container(
                  height: 38,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
                Expanded(
                  child: _PeriodValue(
                    label: previousPeriodLabel,
                    value: comparison.previousValue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '金额差 · $directionText',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    _formatSignedMoney(comparison.delta),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (percentage == null) ...[
              const SizedBox(height: 8),
              Text(
                '$previousPeriodLabel 为 0，百分比变化不具可比性。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatSignedMoney(double value) {
    if (value > 0) return '+${formatMoney(value)}';
    return formatMoney(value);
  }
}

class _PeriodValue extends StatelessWidget {
  const _PeriodValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          formatMoney(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
