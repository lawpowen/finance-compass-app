import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/month_key.dart';
import '../accounts/credit_card_detail_screen.dart';
import '../accounts/accounts_v2_screen.dart';
import '../budgets/budgets_v2_screen.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_donut.dart';
import '../settings/settings_reference_pages.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';

class DashboardV2Screen extends ConsumerStatefulWidget {
  const DashboardV2Screen({
    super.key,
    required this.repository,
    this.onOpenAccounts,
    this.onOpenBudgets,
  });

  final FinanceRepository repository;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenBudgets;

  @override
  ConsumerState<DashboardV2Screen> createState() => _DashboardV2ScreenState();
}

class _DashboardV2ScreenState extends ConsumerState<DashboardV2Screen> {
  int forecastDays = 30;

  FinanceRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
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
    double positiveBalance(ReportGroup group) =>
        repository.displayTotalAssetsByGroup(group, positiveOnly: true);
    final cash = positiveBalance(ReportGroup.cash);
    final investment = positiveBalance(ReportGroup.investment);
    final retirement = positiveBalance(ReportGroup.retirement);
    final liabilities = repository.accountLiabilities();
    final debt = liabilities.credit + liabilities.loans;
    final assets = cash + investment + retirement;
    final assetColors = financeDonutSeries(context);
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
    final balanceUnchanged = chartValues.every((amount) => amount == liquid);
    ({
      String categoryId,
      double used,
      double planned,
      double limit,
      double rate,
    })? budgetAlert;
    if (showBudgetAttention) {
      for (final budget in budgets) {
        final limit = repository.effectiveBudgetForMonth(budget, monthKey);
        if (limit <= 0) continue;
        final planned = repository.plannedExpenseTotalForCategory(
          budget.categoryId,
          monthKey,
        );
        final used =
            repository.expenseTotalForCategory(budget.categoryId, monthKey) +
                planned;
        final rate = used / limit;
        if (used <= 0 || rate < budget.alertThreshold) continue;
        if (budgetAlert == null || rate > budgetAlert.rate) {
          budgetAlert = (
            categoryId: budget.categoryId,
            used: used,
            planned: planned,
            limit: limit,
            rate: rate
          );
        }
      }
    }

    Widget header({required bool wide}) => CompassPageHeader(
          title: '财务罗盘',
          actions: [
            if (wide) ...[
              OutlinedButton.icon(
                onPressed: () => _showTransactionEditor(context, planned: true),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('规划交易'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _showTransactionEditor(context),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('记账'),
              ),
              const SizedBox(width: 20),
            ],
            CircleAvatar(
              radius: 17,
              backgroundColor: palette.seed,
              child: Text('L',
                  style: TextStyle(color: financeForegroundOn(palette.seed))),
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
            IconButton(
              tooltip: '通知与提醒',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationsPage(repository: repository),
                ),
              ),
              icon: const Icon(Icons.notifications_none_rounded, size: 27),
            ),
          ],
        );

    Widget forecast({required bool wide}) => Padding(
          padding: wide
              ? const EdgeInsets.all(22)
              : const EdgeInsets.fromLTRB(18, 20, 18, 0),
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
                            PopupMenuItem(value: 7, child: Text('未来 7 天')),
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
                              style: TextStyle(
                                color: financePaletteOf(context).seed,
                                fontSize: wide ? 28 : 20,
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
              CompassAreaChart(
                values: chartValues,
                height: balanceUnchanged ? 92 : (wide ? 200 : 190),
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
                            style: TextStyle(fontSize: wide ? 12 : 10),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (wide) ...[
                const SizedBox(height: 16),
                compassHairline,
              ],
              const SizedBox(height: 12),
              Wrap(
                runSpacing: 6,
                spacing: 20,
                children: [
                  Text(
                    '今日余额 ${compassMoney(liquid, currency: repository.baseCurrency)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (balanceUnchanged)
                    Text('期末余额与今日相同',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (dueInRange > 0)
                    Text(
                      '期间信用卡还款 ${compassMoney(dueInRange, currency: repository.baseCurrency)}',
                      style: TextStyle(color: palette.expense),
                    ),
                ],
              ),
              if (!wide) ...[
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
                            backgroundColor: palette.expense,
                            foregroundColor:
                                financeForegroundOn(palette.expense),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          icon: const Icon(Icons.add_circle_outline_rounded),
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
                            foregroundColor:
                                financePaletteOf(context).textPrimary,
                            side: BorderSide(
                              color: financePaletteOf(context).border,
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
            ],
          ),
        );

    Widget? budgetAttention;
    if (budgetAlert case final warning?) {
      final hasPlanned = warning.planned > 0;
      final spending = compassMoney(warning.used,
          currency: repository.baseCurrency, decimals: 0);
      final usedLabel = '${hasPlanned ? '含预计' : '已用'} $spending';
      final overspend = warning.used - warning.limit;
      final overspendLabel = compassMoney(
        overspend,
        currency: repository.baseCurrency,
        decimals: 0,
      );
      budgetAttention = _AttentionRow(
        icon: Icons.pie_chart_outline_rounded,
        title: '${repository.categoryName(warning.categoryId)}预算',
        subtitle: overspend > 0 ? usedLabel : null,
        amount: overspend > 0
            ? '${hasPlanned ? '预计超出' : '超出'} $overspendLabel'
            : usedLabel,
        color: palette.expense,
        onTap: widget.onOpenBudgets ??
            () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: SafeArea(
                        child: BudgetsV2Screen(repository: repository),
                      ),
                    ),
                  ),
                ),
      );
    }

    List<Widget> attention() => [
          const CompassSectionTitle('需要关注'),
          const SizedBox(height: 8),
          if (attentionReminder != null)
            _AttentionRow(
              icon: Icons.credit_card_rounded,
              title: '${now.month}月信用卡账单',
              subtitle:
                  '还款日 ${attentionReminder.dueDate.month}月${attentionReminder.dueDate.day}日',
              amount: compassMoney(due, decimals: 0),
              color: financePaletteOf(context).expense,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CreditCardDetailScreen(
                    account: attentionReminder.account,
                    repository: repository,
                  ),
                ),
              ),
            ),
          if (attentionReminder != null && budgetAttention != null)
            const SizedBox(height: 6),
          if (budgetAttention case final item?) item,
          if (attentionReminder == null && budgetAttention == null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child:
                  Text('暂无待处理事项', style: Theme.of(context).textTheme.bodySmall),
            ),
        ];

    final openAccounts = widget.onOpenAccounts ??
        () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body:
                      SafeArea(child: AccountsV2Screen(repository: repository)),
                ),
              ),
            );
    final debtLabel =
        '负债 ${compassMoney(debt, currency: repository.baseCurrency, decimals: 0)}';
    final distribution = FinanceDonutPanel(
      key: const Key('dashboard-asset-composition'),
      title: '资产构成',
      totalLabel: '总资产',
      totalValue:
          compassMoney(assets, currency: repository.baseCurrency, decimals: 0),
      slices: [
        FinanceDonutSlice(label: '现金', value: cash, color: assetColors[0]),
        FinanceDonutSlice(
            label: '投资', value: investment, color: assetColors[2]),
        FinanceDonutSlice(
            label: '退休', value: retirement, color: assetColors[1]),
      ],
      footer: Semantics(
        container: true,
        button: true,
        excludeSemantics: true,
        label: '查看账户，$debtLabel',
        onTap: openAccounts,
        child: InkWell(
          key: const Key('dashboard-asset-accounts'),
          borderRadius: BorderRadius.circular(8),
          onTap: openAccounts,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(child: Text(debtLabel)),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= compassDesktopMinWidth;
        return ListView(
          padding: compassScrollPadding(
              context,
              wide
                  ? compassDesktopPagePadding
                  : compassPagePadding.copyWith(bottom: 34)),
          children: [
            header(wide: wide),
            SizedBox(height: wide ? 24 : 15),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CompassCard(
                          padding: EdgeInsets.zero,
                          child: forecast(wide: true),
                        ),
                        const SizedBox(height: 16),
                        CompassCard(child: Column(children: attention())),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(width: 360, child: distribution),
                ],
              )
            else ...[
              CompassCard(
                padding: EdgeInsets.zero,
                borderColor: Colors.transparent,
                child: Column(
                  children: [
                    forecast(wide: false),
                    compassHairline,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        children: attention(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              distribution,
            ],
          ],
        );
      },
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
    this.subtitle,
    required this.amount,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String amount;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amountLabel = FittedBox(
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
    );
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
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 138),
            child: amountLabel,
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
