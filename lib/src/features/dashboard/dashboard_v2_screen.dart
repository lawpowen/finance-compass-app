import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/month_key.dart';
import '../accounts/credit_card_detail_screen.dart';
import '../accounts/accounts_v2_screen.dart';
import '../budgets/budgets_v2_screen.dart';
import '../shared/compass_ui.dart';
import '../settings/settings_reference_pages.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';

class DashboardV2Screen extends ConsumerStatefulWidget {
  const DashboardV2Screen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<DashboardV2Screen> createState() => _DashboardV2ScreenState();
}

class _DashboardV2ScreenState extends ConsumerState<DashboardV2Screen> {
  int forecastDays = 30;

  FinanceRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final forecastEnd = today.add(Duration(days: forecastDays));
    final monthKey = monthKeyFromDate(now);
    final reminders = repository.creditCardPaymentReminders();
    final notificationsEnabled =
        repository.metaValues['notifications_enabled'] != 'false';
    final notificationPreferences = _notificationPreferences(repository);
    final showCreditAttention = notificationsEnabled &&
        (notificationPreferences[0] || notificationPreferences[1]);
    final showBudgetAttention =
        notificationsEnabled && notificationPreferences[4];
    final budgets = repository.activeBudgetsForMonth(monthKey);
    final cash = repository.totalAssetsByGroup(ReportGroup.cash);
    final investment = repository.totalAssetsByGroup(ReportGroup.investment);
    final retirement = repository.totalAssetsByGroup(ReportGroup.retirement);
    final total = cash + investment + retirement;
    final reminder = reminders.isEmpty ? null : reminders.first;
    final attentionReminder = showCreditAttention ? reminder : null;
    final due = reminder?.amountDue ?? 0;
    final todayCutoff = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
      999,
    );
    final liquid = repository.displayTotalAssetsByGroup(
      ReportGroup.cash,
      cutoffDate: todayCutoff,
    );
    final dueInRange = reminder != null &&
            !reminder.dueDate.isBefore(today) &&
            !reminder.dueDate.isAfter(forecastEnd)
        ? due
        : 0.0;
    final projectionStart = today.add(const Duration(days: 1));
    final projected = liquid -
        dueInRange +
        repository.cashFlowNetBetween(
          startInclusive: projectionStart,
          endInclusive: forecastEnd,
        );
    final chartValues = List<double>.generate(6, (index) {
      if (index == 0) return liquid;
      final sampleEnd = today.add(
        Duration(days: (forecastDays * index / 5).round()),
      );
      final reminderEffect = reminder != null &&
              !reminder.dueDate.isBefore(today) &&
              !reminder.dueDate.isAfter(sampleEnd)
          ? due
          : 0.0;
      return liquid -
          reminderEffect +
          repository.cashFlowNetBetween(
            startInclusive: projectionStart,
            endInclusive: sampleEnd,
          );
    });
    final attentionBudget =
        !showBudgetAttention || budgets.isEmpty ? null : budgets.first;
    final attentionBudgetUsed = attentionBudget == null
        ? 0.0
        : repository.expenseTotalForCategory(
              attentionBudget.categoryId,
              monthKey,
            ) +
            repository.plannedExpenseTotalForCategory(
              attentionBudget.categoryId,
              monthKey,
            );

    return ListView(
      padding: compassPagePadding.copyWith(bottom: 34),
      children: [
        CompassPageHeader(
          title: '财务罗盘',
          actions: [
            const CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFF2A7A74),
              child: Text('L', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountSyncPage(repository: repository),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    Text('个人账户', style: Theme.of(context).textTheme.bodyMedium),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsPage(repository: repository),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_none_rounded, size: 27),
                ),
                Positioned(
                  right: 5,
                  top: 3,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: FinanceColors.compassOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 15),
        CompassCard(
          padding: EdgeInsets.zero,
          borderColor: Colors.transparent,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PopupMenuButton<int>(
                                initialValue: forecastDays,
                                onSelected: (value) =>
                                    setState(() => forecastDays = value),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 7, child: Text('未来 7 天')),
                                  PopupMenuItem(
                                    value: 30,
                                    child: Text('未来 30 天'),
                                  ),
                                  PopupMenuItem(
                                    value: 60,
                                    child: Text('未来 60 天'),
                                  ),
                                  PopupMenuItem(
                                    value: 90,
                                    child: Text('未来 90 天'),
                                  ),
                                ],
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '未来 $forecastDays 天',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(fontSize: 22),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Icon(Icons.arrow_drop_down_rounded),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '今天 ${now.month}月${now.day}日',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('预计余额',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 5),
                              SizedBox(
                                width: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    compassMoney(projected),
                                    style: const TextStyle(
                                      color: FinanceColors.compassTeal,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${forecastEnd.month}月${forecastEnd.day}日',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Stack(
                      children: [
                        CompassAreaChart(
                          values: chartValues,
                          height: 190,
                          markerIndex: 1,
                        ),
                        Positioned(
                          left: 0,
                          top: 49,
                          child: Text(
                            compassMoney(liquid, decimals: 0),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (reminder != null)
                          Positioned(
                            right: 77,
                            top: 6,
                            child: Column(
                              children: [
                                Text(
                                  '${reminder.dueDate.month}月${reminder.dueDate.day}日',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const Text('信用卡还款'),
                                Text(
                                  '- ${compassMoney(due)}',
                                  style: const TextStyle(
                                    color: FinanceColors.compassOrange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Positioned(
                          left: 75,
                          top: 136,
                          child: Text(
                            '今天\n${now.month}月${now.day}日',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: List.generate(6, (index) {
                        final date = today.add(
                          Duration(days: (forecastDays * index / 5).round()),
                        );
                        return '${date.month}月${date.day}日';
                      })
                          .map(
                            (label) => Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: () => _showTransactionEditor(
                                context,
                                planned: true,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: FinanceColors.compassOrange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              icon:
                                  const Icon(Icons.add_circle_outline_rounded),
                              label: const Text('规划交易'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => _showTransactionEditor(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: FinanceColors.compassText,
                                side: const BorderSide(
                                  color: FinanceColors.compassBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              icon: const Icon(Icons.edit_note_rounded),
                              label: const Text('记账'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              compassHairline,
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  children: [
                    const CompassSectionTitle('需要关注'),
                    const SizedBox(height: 8),
                    _AttentionRow(
                      icon: Icons.credit_card_rounded,
                      title: !showCreditAttention
                          ? '信用卡应用内提醒已关闭'
                          : attentionReminder == null
                              ? '目前没有待还信用卡账单'
                              : '${now.month}月信用卡账单',
                      subtitle: !showCreditAttention
                          ? '可在设置的“通知与提醒”重新开启'
                          : attentionReminder == null
                              ? '建立信用卡账户并设置结算日、还款日后显示'
                              : '还款日 ${attentionReminder.dueDate.month}月${attentionReminder.dueDate.day}日',
                      amount: attentionReminder == null
                          ? '—'
                          : compassMoney(due, decimals: 0),
                      color: FinanceColors.compassOrange,
                      badge: attentionReminder == null ? null : '待还款',
                      onTap: attentionReminder == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CreditCardDetailScreen(
                                    account: attentionReminder.account,
                                    repository: repository,
                                  ),
                                ),
                              ),
                    ),
                    const SizedBox(height: 6),
                    _AttentionRow(
                      icon: Icons.pie_chart_outline_rounded,
                      title: !showBudgetAttention
                          ? '预算应用内提醒已关闭'
                          : attentionBudget == null
                              ? '本月尚未设置预算'
                              : '${repository.categoryName(attentionBudget.categoryId)}预算状态',
                      subtitle: showBudgetAttention
                          ? '${now.month}月预算'
                          : '可在设置的“通知与提醒”重新开启',
                      amount: attentionBudget == null
                          ? '—'
                          : '已用 ${compassMoney(attentionBudgetUsed, decimals: 0)}',
                      color: FinanceColors.compassTeal,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            body: SafeArea(
                              child: BudgetsV2Screen(repository: repository),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const CompassSectionTitle('资金分布'),
                    const SizedBox(height: 10),
                    CompassDistributionBar(
                      values: [cash, investment, retirement],
                      colors: const [
                        FinanceColors.compassTeal,
                        FinanceColors.compassOrange,
                        Color(0xFF5B8D58),
                      ],
                      labels: [
                        '${total == 0 ? 0 : (cash / total * 100).round()}%',
                        '${total == 0 ? 0 : (investment / total * 100).round()}%',
                        '${total == 0 ? 0 : (retirement / total * 100).round()}%',
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DistributionLegend(
                            label: '现金',
                            value: cash,
                            color: FinanceColors.compassTeal,
                          ),
                        ),
                        Expanded(
                          child: _DistributionLegend(
                            label: '投资',
                            value: investment,
                            color: FinanceColors.compassOrange,
                          ),
                        ),
                        Expanded(
                          child: _DistributionLegend(
                            label: '退休',
                            value: retirement,
                            color: const Color(0xFF5B8D58),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              body: SafeArea(
                                child: AccountsV2Screen(
                                  repository: repository,
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            '总计  ${compassMoney(total)}  ›',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<bool> _notificationPreferences(FinanceRepository repository) {
    const defaults = [true, true, true, true, true, false, true];
    final raw = repository.metaValues['notification_preferences_json'];
    if (raw == null) return List<bool>.from(defaults);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.length == defaults.length) {
        return decoded.map((value) => value == true).toList();
      }
    } catch (_) {}
    return List<bool>.from(defaults);
  }

  Future<void> _showTransactionEditor(
    BuildContext context, {
    bool planned = false,
  }) async {
    final now = DateTime.now();
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: repository,
          draft: planned
              ? FinanceTransaction(
                  id: 'draft_planned',
                  type: TransactionType.expense,
                  accountId: repository.accounts.isEmpty
                      ? ''
                      : repository.accounts.first.id,
                  amount: 0,
                  currency: repository.baseCurrency,
                  recordDate: now,
                  transactionDate: now,
                  status: TransactionStatus.planned,
                  description: '',
                )
              : null,
        ),
      ),
    );
    if (result == null) return;
    final mutations = ref.read(transactionMutationsProvider.notifier);
    if (result.transactions.length == 1) {
      await mutations.addTransaction(result.transactions.first);
    } else {
      await mutations.addTransactions(result.transactions);
    }
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.color,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;
  final Color color;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CompassIconBadge(icon: icon, color: color, size: 45),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                if (badge != null) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: FinanceColors.compassOrange.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: FinanceColors.compassOrange,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    amount,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                if (onTap != null)
                  Text('查看明细  ›', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

class _DistributionLegend extends StatelessWidget {
  const _DistributionLegend({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(label),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            compassMoney(value),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}
