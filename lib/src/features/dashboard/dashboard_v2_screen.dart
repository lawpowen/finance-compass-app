import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/month_key.dart';
import '../../core/utils/currency_formatter.dart' show moneyDisplayParts;
import '../accounts/credit_card_detail_screen.dart';
import '../accounts/accounts_v2_screen.dart';
import '../ai/ai_chat_screen.dart';
import '../budgets/budgets_v2_screen.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_donut.dart';
import '../settings/settings_reference_pages.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';
import '../transactions/transactions_v2_screen.dart';

const _forecastHelp = '以今日现金余额为起点，计入期间的实际与预计现金流。'
    '各卡到期账单按本位币汇总。已安排的还款计入现金流，其余应还金额在到期时扣除。'
    '图表按六个日期取样，区间最低是这些取样点中的最低余额。';
const _attentionHelp = '此处按通知设置显示信用卡账单，以及达到提醒阈值的预算。'
    '预算提醒包含已发生和预计支出，优先显示使用比例最高的三项。';
const _assetHelp = '环形图按基础币汇总现金、投资和退休账户的正余额。'
    '溢付余额计入资产。负债单独列示，包含透支、信用卡和贷款欠款。';

class DashboardV2Screen extends ConsumerStatefulWidget {
  const DashboardV2Screen({
    super.key,
    required this.repository,
    this.onOpenAccounts,
    this.onOpenTransactions,
    this.onOpenBudgets,
  });

  final FinanceRepository repository;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenTransactions;
  final VoidCallback? onOpenBudgets;

  @override
  ConsumerState<DashboardV2Screen> createState() => _DashboardV2ScreenState();
}

class _DashboardV2ScreenState extends ConsumerState<DashboardV2Screen> {
  int forecastDays = 30;
  _DashboardViewData? _cachedData;

  FinanceRepository get repository => widget.repository;

  _DashboardViewData _viewDataFor(DateTime now) {
    final todayKey = now.year * 10000 + now.month * 100 + now.day;
    final cached = _cachedData;
    if (cached != null &&
        identical(cached.repository, repository) &&
        cached.forecastDays == forecastDays &&
        cached.todayKey == todayKey) {
      return cached;
    }

    final today = DateTime(now.year, now.month, now.day);
    final forecastEnd =
        DateTime(today.year, today.month, today.day + forecastDays);
    final monthKey = monthKeyFromDate(now);
    final notificationsEnabled =
        repository.metaValues['notifications_enabled'] != 'false';
    final notificationPreferences = _notificationPreferences(repository);
    final showRepayments = notificationsEnabled && notificationPreferences[0];
    final showStatements = notificationsEnabled && notificationPreferences[1];
    final showBudgetAttention =
        notificationsEnabled && notificationPreferences[4];
    final budgets = repository.activeBudgetsForMonth(monthKey);
    final sheet =
        repository.balanceSheetAt(repository.currentMonthCutoffDate());
    final cash = sheet.assetsIn(ReportGroup.cash);
    final investment = sheet.assetsIn(ReportGroup.investment);
    final retirement = sheet.assetsIn(ReportGroup.retirement);
    final debt = sheet.liabilities;
    final assets = sheet.assets;
    final netWorth = sheet.netWorth;
    final monthlyIncome = repository.totalIncomeForMonth(monthKey);
    final monthlyExpense = repository.totalExpenseForMonth(monthKey);
    final monthlyNet = monthlyIncome - monthlyExpense;
    final savingsRate =
        monthlyIncome > 0 ? (monthlyNet / monthlyIncome * 100).round() : null;
    final activeReminders = showRepayments
        ? repository
            .creditCardPaymentReminders(asOf: now)
            .where((reminder) =>
                notificationPreferences[6] ||
                !DateUtils.isSameDay(reminder.dueDate, today))
            .toList()
        : const <CreditCardPaymentReminder>[];
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    final closingCards = showStatements
        ? repository.accounts.where((card) {
            final day = card.statementDay;
            return card.isActive &&
                card.accountType == AccountType.creditCard &&
                day != null &&
                day >= 1 &&
                day <= 31 &&
                today.day == math.min(day, lastDay);
          }).toList()
        : const <Account>[];
    final cashForecast =
        repository.cashForecast(asOf: now, endInclusive: forecastEnd);
    final todayCutoff = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
      999,
    );
    final liquid = cashForecast.openingCash;
    final dueInRange = cashForecast.uncoveredCreditDue;
    final projected = cashForecast.endingCash;
    final chartDates = List<DateTime>.generate(
      6,
      (index) => DateTime(
        today.year,
        today.month,
        today.day + (forecastDays * index / 5).round(),
      ),
    );
    final chartLabels = [
      for (final date in chartDates) '${date.month}月${date.day}日',
    ];
    final chartValues = [
      liquid,
      ...chartDates.skip(1).map(cashForecast.balanceAt)
    ];
    final balanceUnchanged = chartValues.every((amount) => amount == liquid);
    final minProjected = chartValues.reduce(math.min);
    final forecastDelta = projected - liquid;
    final budgetAlerts = <({
      String categoryId,
      double used,
      double planned,
      double limit,
      double rate,
    })>[];
    if (showBudgetAttention) {
      for (final budget in budgets) {
        final limit = repository.effectiveBudgetForMonth(budget, monthKey);
        if (limit <= 0) continue;
        final usage = repository.budgetUsageFor(budget.categoryId, monthKey);
        if (!repository.budgetLimitIsValued(budget.categoryId, monthKey) ||
            !usage.actualValued ||
            !usage.plannedValued) {
          continue;
        }
        final planned = usage.planned;
        final used = usage.actual + planned;
        final rate = used / limit;
        if (used <= 0 || rate < budget.alertThreshold) continue;
        budgetAlerts.add((
          categoryId: budget.categoryId,
          used: used,
          planned: planned,
          limit: limit,
          rate: rate,
        ));
      }
      budgetAlerts.sort((a, b) => b.rate.compareTo(a.rate));
    }
    final recentActualTransactions = repository.transactions
        .where((item) =>
            item.status != TransactionStatus.planned &&
            !item.transactionDate.isAfter(todayCutoff))
        .toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    final recentItems = recentActualTransactions.take(4).toList();

    return _cachedData = _DashboardViewData(
      repository: repository,
      forecastDays: forecastDays,
      todayKey: todayKey,
      today: today,
      forecastEnd: forecastEnd,
      cash: cash,
      investment: investment,
      retirement: retirement,
      debt: debt,
      creditBalances: sheet.cardCredit + sheet.loanCredit,
      assets: assets,
      netWorth: netWorth,
      monthlyIncome: monthlyIncome,
      monthlyExpense: monthlyExpense,
      monthlyNet: monthlyNet,
      savingsRate: savingsRate,
      activeReminders: activeReminders,
      closingCards: closingCards,
      liquid: liquid,
      dueInRange: dueInRange,
      projected: projected,
      chartLabels: chartLabels,
      chartValues: chartValues,
      balanceUnchanged: balanceUnchanged,
      minProjected: minProjected,
      forecastDelta: forecastDelta,
      budgetAlerts: budgetAlerts,
      recentItems: recentItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final now = DateTime.now();
    final data = _viewDataFor(now);
    final today = data.today;
    final forecastEnd = data.forecastEnd;
    final cash = data.cash;
    final investment = data.investment;
    final retirement = data.retirement;
    final debt = data.debt;
    final assets = data.assets;
    final netWorth = data.netWorth;
    final baseCurrency = repository.baseCurrency;
    final monthlyIncome = data.monthlyIncome;
    final monthlyExpense = data.monthlyExpense;
    final monthlyNet = data.monthlyNet;
    final savingsRate = data.savingsRate;
    final assetColors = financeDonutSeries(context);
    final activeReminders = data.activeReminders;
    final closingCards = data.closingCards;
    final liquid = data.liquid;
    final dueInRange = data.dueInRange;
    final projected = data.projected;
    final chartLabels = data.chartLabels;
    final chartValues = data.chartValues;
    final balanceUnchanged = data.balanceUnchanged;
    final minProjected = data.minProjected;
    final forecastDelta = data.forecastDelta;
    final budgetAlerts = data.budgetAlerts;
    final recentItems = data.recentItems;

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
            const AiChatEntryButton(),
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
                        CompassHelpHeading(
                          title: Text(
                            '预计余额',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          label: '现金预测',
                          message: _forecastHelp,
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              compassMoney(projected, currency: baseCurrency),
                              style: TextStyle(
                                color: projected < 0
                                    ? palette.expense
                                    : palette.textPrimary,
                                fontSize: wide ? 28 : 20,
                                fontWeight: FontWeight.w700,
                                fontFeatures: compassTabularFigures,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              '${forecastEnd.month}月${forecastEnd.day}日',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (forecastDelta.abs() < 0.5)
                              CompassStatusBadge(
                                label: '预计持平',
                                color: palette.textMuted,
                              )
                            else
                              CompassStatusBadge(
                                label:
                                    '${forecastDelta > 0 ? '+ ' : ''}${compassMoney(forecastDelta, currency: baseCurrency, decimals: 0)}',
                                color: forecastDelta > 0
                                    ? palette.income
                                    : palette.expense,
                                icon: forecastDelta > 0
                                    ? Icons.north_east_rounded
                                    : Icons.south_east_rounded,
                              ),
                          ],
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
                labels: chartLabels,
                formatValue: (value) =>
                    compassMoney(value, currency: baseCurrency, decimals: 0),
                showMinMaxLabels: !balanceUnchanged,
              ),
              Row(
                children: chartLabels
                    .map(
                      (label) => Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: wide ? 12 : 10,
                              color: palette.textMuted,
                            ),
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
                spacing: 18,
                children: [
                  Text(
                    '今日余额 ${compassMoney(liquid, currency: baseCurrency)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFeatures: compassTabularFigures,
                        ),
                  ),
                  if (minProjected < liquid)
                    Text(
                      '区间最低 ${compassMoney(minProjected, currency: baseCurrency, decimals: 0)}',
                      style: TextStyle(
                        color: minProjected < 0
                            ? palette.expense
                            : palette.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: compassTabularFigures,
                      ),
                    ),
                  if (dueInRange > 0)
                    Text(
                      '未安排信用卡还款 ${compassMoney(dueInRange, currency: baseCurrency)}',
                      style: TextStyle(
                        color: palette.expense,
                        fontFeatures: compassTabularFigures,
                      ),
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
                        child: OutlinedButton.icon(
                          onPressed: () => _showTransactionEditor(
                            context,
                            planned: true,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.textPrimary,
                            side: BorderSide(color: palette.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.event_available_outlined),
                          label: const Text('规划交易'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => _showTransactionEditor(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.resolvedPrimaryAction,
                            foregroundColor: financeForegroundOn(
                                palette.resolvedPrimaryAction),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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

    final openAccounts = widget.onOpenAccounts ??
        () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body:
                      SafeArea(child: AccountsV2Screen(repository: repository)),
                ),
              ),
            );
    final openTransactions = widget.onOpenTransactions ??
        () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: SafeArea(
                    child: TransactionsV2Screen(repository: repository),
                  ),
                ),
              ),
            );
    final openBudgets = widget.onOpenBudgets ??
        () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body:
                      SafeArea(child: BudgetsV2Screen(repository: repository)),
                ),
              ),
            );

    final visibleBudgetAlerts = budgetAlerts.take(3).toList();
    final cardAttentionCount = activeReminders.length + closingCards.length;
    final totalAttentionCount = cardAttentionCount + budgetAlerts.length;

    List<Widget> attention() => [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: CompassHelpHeading(
                    title: Text(
                      '需要关注',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    label: '需要关注',
                    message: _attentionHelp,
                  ),
                ),
              ),
              if (totalAttentionCount > 0)
                CompassStatusBadge(
                  label: '$totalAttentionCount 项',
                  color: palette.expense,
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < activeReminders.length; i++) ...[
            if (i > 0) compassHairline,
            Builder(builder: (context) {
              final item = activeReminders[i];
              final dueDay = DateTime.utc(
                item.dueDate.year,
                item.dueDate.month,
                item.dueDate.day,
              );
              final daysUntil = dueDay
                  .difference(DateTime.utc(today.year, today.month, today.day))
                  .inDays;
              final isEstimated = !item.account.hasCompleteCreditCardProfile;
              final badgeLabel = isEstimated
                  ? '估算提醒'
                  : daysUntil < 0
                      ? '已逾期 ${daysUntil.abs()} 天'
                      : daysUntil == 0
                          ? '今日到期'
                          : '剩 $daysUntil 天';
              final badgeColor = daysUntil <= 0
                  ? palette.expense
                  : (daysUntil <= 3 ? palette.warning : palette.textMuted);
              return _AttentionRow(
                icon: Icons.credit_card_rounded,
                title: isEstimated
                    ? '${item.account.name} · 估算还款'
                    : '${item.account.name} · ${item.billingMonthDate.month}月账单',
                subtitle: [
                  '还款日 ${item.dueDate.month}月${item.dueDate.day}日',
                  if (item.account.currency != baseCurrency)
                    compassMoney(item.amountDue,
                        currency: item.account.currency),
                ].join(' · '),
                badgeLabel: badgeLabel,
                badgeColor: badgeColor,
                badgeInverted: daysUntil <= 0 && !isEstimated,
                amount: repository.hasExchangeRate(item.account.currency)
                    ? compassMoney(item.amountDueInBase, currency: baseCurrency)
                    : '未估值',
                color: daysUntil <= 3 ? palette.expense : palette.textPrimary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CreditCardDetailScreen(
                      account: item.account,
                      repository: repository,
                    ),
                  ),
                ),
              );
            }),
          ],
          for (var i = 0; i < closingCards.length; i++) ...[
            if (activeReminders.isNotEmpty || i > 0) compassHairline,
            _AttentionRow(
              icon: Icons.receipt_long_outlined,
              title: '${closingCards[i].name} · 账单结算',
              subtitle: '今天是结算日',
              amount: '${today.month}月${today.day}日',
              color: palette.textPrimary,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CreditCardDetailScreen(
                    account: closingCards[i], repository: repository),
              )),
            ),
          ],
          for (var i = 0; i < visibleBudgetAlerts.length; i++) ...[
            if (cardAttentionCount > 0 || i > 0) compassHairline,
            Builder(builder: (context) {
              final warning = visibleBudgetAlerts[i];
              final hasPlanned = warning.planned > 0;
              final spending = compassMoney(
                warning.used,
                currency: baseCurrency,
                decimals: 0,
              );
              final usedLabel = '${hasPlanned ? '含预计' : '已用'} $spending';
              final overspend = warning.used - warning.limit;
              final overspendLabel = compassMoney(
                overspend,
                currency: baseCurrency,
                decimals: 0,
              );
              final isOverspent = overspend > 0;
              final alertColor =
                  isOverspent ? palette.expense : palette.warning;
              return _AttentionRow(
                icon: Icons.pie_chart_outline_rounded,
                title: '${repository.categoryName(warning.categoryId)}预算',
                subtitle: isOverspent
                    ? usedLabel
                    : '预算 ${compassMoney(warning.limit, currency: baseCurrency, decimals: 0)}',
                badgeLabel: isOverspent
                    ? '超出 ${(warning.rate * 100).round()}%'
                    : '已达 ${(warning.rate * 100).round()}%',
                badgeColor: alertColor,
                badgeInverted: isOverspent,
                amount: isOverspent
                    ? '${hasPlanned ? '预计超出' : '超出'} $overspendLabel'
                    : usedLabel,
                color: alertColor,
                onTap: openBudgets,
              );
            }),
          ],
          if (budgetAlerts.length > visibleBudgetAlerts.length) ...[
            compassHairline,
            InkWell(
              onTap: openBudgets,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '还有 ${budgetAlerts.length - visibleBudgetAlerts.length} 项预算提醒',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '查看预算',
                      style: TextStyle(
                        color: palette.seed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
          if (totalAttentionCount == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: palette.income,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '暂无待处理事项',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ];

    final debtLabel =
        '负债 ${compassMoney(debt, currency: baseCurrency, decimals: 0)}';
    final distribution = FinanceDonutPanel(
      key: const Key('dashboard-asset-composition'),
      title: '资产构成',
      titleHelp: _assetHelp,
      totalLabel: '总资产',
      totalValue: compassMoney(assets, currency: baseCurrency, decimals: 0),
      formatLegendAmount: (amount) =>
          compassMoney(amount, currency: baseCurrency, decimals: 0),
      slices: [
        if (data.creditBalances > 0)
          FinanceDonutSlice(
              label: '溢付余额', value: data.creditBalances, color: palette.income),
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
                Expanded(
                  child: Text(
                    debtLabel,
                    style: TextStyle(
                      color: debt > 0 ? palette.expense : palette.textMuted,
                      fontWeight: debt > 0 ? FontWeight.w600 : FontWeight.w400,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );

    final recentTransactionsCard = CompassCard(
      key: const Key('dashboard-recent-transactions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CompassSectionTitle(
            '近期交易',
            trailing: TextButton(
              onPressed: openTransactions,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('查看全部'),
            ),
          ),
          const SizedBox(height: 6),
          if (recentItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '暂无近期交易',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showTransactionEditor(context),
                    child: const Text('记一笔'),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < recentItems.length; i++) ...[
              if (i > 0) compassHairline,
              _RecentTransactionRow(
                transaction: recentItems[i],
                repository: repository,
                onTap: () => _showTransactionEditor(
                  context,
                  draft: recentItems[i],
                  editExisting: true,
                ),
              ),
            ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= compassDesktopMinWidth;
        final kpiStrip = _DashboardKpiStrip(
          wide: wide,
          baseCurrency: baseCurrency,
          netWorth: netWorth,
          totalAssets: assets,
          debt: debt,
          monthlyIncome: monthlyIncome,
          monthlyExpense: monthlyExpense,
          monthlyNet: monthlyNet,
          savingsRate: savingsRate,
          onOpenAccounts: openAccounts,
          onOpenTransactions: openTransactions,
        );
        return ListView(
          cacheExtent: 500,
          padding: compassScrollPadding(
              context,
              wide
                  ? compassDesktopPagePadding
                  : compassPagePadding.copyWith(bottom: 34)),
          children: [
            header(wide: wide),
            SizedBox(height: wide ? 20 : 14),
            kpiStrip,
            const SizedBox(height: 16),
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
                        CompassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: attention(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 360,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        distribution,
                        const SizedBox(height: 16),
                        recentTransactionsCard,
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              CompassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    forecast(wide: false),
                    compassHairline,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: attention(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              distribution,
              const SizedBox(height: 16),
              recentTransactionsCard,
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
    FinanceTransaction? draft,
    bool editExisting = false,
    bool planned = false,
  }) async {
    final now = DateTime.now();
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: repository,
          editExisting: editExisting,
          draft: draft ??
              (planned
                  ? FinanceTransaction(
                      id: 'draft_planned',
                      type: TransactionType.expense,
                      accountId:
                          repository.entryAccounts().firstOrNull?.id ?? '',
                      amount: 0,
                      currency: repository.baseCurrency,
                      recordDate: now,
                      transactionDate: now,
                      status: TransactionStatus.planned,
                      description: '',
                    )
                  : null),
        ),
      ),
    );
    if (result == null) return;
    final mutations = ref.read(transactionMutationsProvider.notifier);
    if (result.deletedTransactionId case final transactionId?) {
      await mutations.deleteTransaction(transactionId);
      return;
    }
    if (editExisting && result.transactions.length == 1) {
      await mutations.updateTransaction(result.transactions.first);
    } else if (result.transactions.length == 1) {
      await mutations.addTransaction(result.transactions.first);
    } else {
      await mutations.addTransactions(result.transactions);
    }
  }
}

class _DashboardKpiStrip extends StatelessWidget {
  const _DashboardKpiStrip({
    required this.wide,
    required this.baseCurrency,
    required this.netWorth,
    required this.totalAssets,
    required this.debt,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.monthlyNet,
    required this.savingsRate,
    required this.onOpenAccounts,
    required this.onOpenTransactions,
  });

  final bool wide;
  final String baseCurrency;
  final double netWorth;
  final double totalAssets;
  final double debt;
  final double monthlyIncome;
  final double monthlyExpense;
  final double monthlyNet;
  final int? savingsRate;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final cards = [
      _DashboardKpiCard(
        key: const Key('dashboard-kpi-net-worth'),
        label: '净资产',
        value: compassMoney(netWorth, currency: baseCurrency, decimals: 0),
        subtitle:
            '资产 ${compassMoney(totalAssets, currency: baseCurrency, decimals: 0)} · 负债 ${compassMoney(debt, currency: baseCurrency, decimals: 0)}',
        valueColor: moneyDisplayParts(netWorth, decimals: 0).sign < 0 ? palette.expense : palette.textPrimary,
        onTap: onOpenAccounts,
      ),
      _DashboardKpiCard(
        key: const Key('dashboard-kpi-income'),
        label: '本月收入',
        value: compassMoney(monthlyIncome, currency: baseCurrency, decimals: 0),
        subtitle: '实际入账',
        valueColor: monthlyIncome > 0 ? palette.income : palette.textMuted,
        onTap: onOpenTransactions,
      ),
      _DashboardKpiCard(
        key: const Key('dashboard-kpi-expense'),
        label: '本月支出',
        value:
            compassMoney(monthlyExpense, currency: baseCurrency, decimals: 0),
        subtitle: '消费支出',
        valueColor: monthlyExpense > 0 ? palette.expense : palette.textMuted,
        onTap: onOpenTransactions,
      ),
      _DashboardKpiCard(
        key: const Key('dashboard-kpi-net'),
        label: '本月结余',
        value:
            '${monthlyNet > 0 ? '+ ' : ''}${compassMoney(monthlyNet, currency: baseCurrency, decimals: 0)}',
        subtitle: savingsRate == null ? '收支差额' : '结余率 $savingsRate%',
        valueColor: monthlyNet > 0
            ? palette.income
            : (monthlyNet < 0 ? palette.expense : palette.textMuted),
        onTap: onOpenTransactions,
      ),
    ];

    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 10),
            Expanded(child: cards[3]),
          ],
        ),
      ],
    );
  }
}

class _DashboardKpiCard extends StatelessWidget {
  const _DashboardKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.valueColor,
    required this.onTap,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color valueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return CompassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 16,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.bodySmall),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: compassTabularFigures,
                  height: 1.15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.badgeLabel,
    this.badgeColor,
    this.badgeInverted = false,
    required this.amount,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badgeLabel;
  final Color? badgeColor;
  final bool badgeInverted;
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
          fontFeatures: compassTabularFigures,
        ),
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CompassIconBadge(icon: icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null || badgeLabel != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (badgeLabel case final badge?)
                        CompassStatusBadge(
                          label: badge,
                          color: badgeColor ?? color,
                          inverted: badgeInverted,
                        ),
                      if (subtitle case final sub?)
                        Text(sub, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: content,
    );
  }
}

class _RecentTransactionRow extends StatelessWidget {
  const _RecentTransactionRow({
    required this.transaction,
    required this.repository,
    required this.onTap,
  });

  final FinanceTransaction transaction;
  final FinanceRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final isExpense = transaction.type == TransactionType.expense;
    final isIncome = transaction.type == TransactionType.income;
    final signed = isExpense ? -transaction.amount : transaction.amount;
    final amountColor = moneyDisplayParts(signed).sign == 0
        ? palette.textPrimary
        : isExpense ? palette.expense : (isIncome ? palette.income : palette.textPrimary);
    final categoryName = transaction.categoryId == null
        ? (transaction.type == TransactionType.transfer ? '账户转账' : '调整')
        : repository.categoryName(transaction.categoryId!);
    final title = transaction.merchant?.trim().isNotEmpty == true
        ? transaction.merchant!.trim()
        : (transaction.description?.trim().isNotEmpty == true
            ? transaction.description!.trim()
            : categoryName);
    final accountName = repository.accountName(transaction.accountId);
    final accountLabel = transaction.type == TransactionType.transfer &&
            transaction.toAccountId != null
        ? '$accountName → ${repository.accountName(transaction.toAccountId!)}'
        : accountName;
    final date = transaction.transactionDate;
    final icon = switch (transaction.type) {
      TransactionType.income => Icons.south_west_rounded,
      TransactionType.expense => Icons.shopping_bag_outlined,
      TransactionType.transfer => Icons.swap_horiz_rounded,
      TransactionType.adjustment => Icons.tune_rounded,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CompassIconBadge(icon: icon, color: amountColor, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.month}月${date.day}日 · $accountLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  compassMoney(signed, currency: transaction.currency, showPositiveSign: isIncome),
                  style: TextStyle(
                    color: amountColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: compassTabularFigures,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardViewData {
  const _DashboardViewData({
    required this.repository,
    required this.forecastDays,
    required this.todayKey,
    required this.today,
    required this.forecastEnd,
    required this.cash,
    required this.investment,
    required this.retirement,
    required this.debt,
    required this.assets,
    required this.creditBalances,
    required this.netWorth,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.monthlyNet,
    required this.savingsRate,
    required this.activeReminders,
    required this.closingCards,
    required this.liquid,
    required this.dueInRange,
    required this.projected,
    required this.chartLabels,
    required this.chartValues,
    required this.balanceUnchanged,
    required this.minProjected,
    required this.forecastDelta,
    required this.budgetAlerts,
    required this.recentItems,
  });

  final FinanceRepository repository;
  final int forecastDays;
  final int todayKey;
  final DateTime today;
  final DateTime forecastEnd;
  final double cash;
  final double investment;
  final double retirement;
  final double debt;
  final double assets;
  final double creditBalances;
  final double netWorth;
  final double monthlyIncome;
  final double monthlyExpense;
  final double monthlyNet;
  final int? savingsRate;
  final List<CreditCardPaymentReminder> activeReminders;
  final List<Account> closingCards;
  final double liquid;
  final double dueInRange;
  final double projected;
  final List<String> chartLabels;
  final List<double> chartValues;
  final bool balanceUnchanged;
  final double minProjected;
  final double forecastDelta;
  final List<
      ({
        String categoryId,
        double used,
        double planned,
        double limit,
        double rate,
      })> budgetAlerts;
  final List<FinanceTransaction> recentItems;
}
