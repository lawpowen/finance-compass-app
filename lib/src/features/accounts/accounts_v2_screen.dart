import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/credit_card_billing.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart' show normalizeCurrency;
import '../shared/compass_ui.dart';
import '../shared/finance_donut.dart';
import '../settings/settings_reference_pages.dart';
import 'account_detail_screen.dart';
import 'account_form_dialog.dart';
import 'asset_goals_page.dart';
import 'credit_card_detail_screen.dart';
import 'loan_detail_screen.dart';

class AccountsV2Screen extends ConsumerStatefulWidget {
  const AccountsV2Screen({super.key, required this.repository, this.asOf});

  final FinanceRepository repository;
  final DateTime? asOf;

  @override
  ConsumerState<AccountsV2Screen> createState() => _AccountsV2ScreenState();
}

class _AccountsV2ScreenState extends ConsumerState<AccountsV2Screen> {
  int selectedGroup = 1;
  late DateTime selectedCutoffMonth = _currentMonth;

  DateTime get _now => widget.asOf ?? DateTime.now();
  DateTime get _currentMonth {
    final now = _now;
    return DateTime(now.year, now.month);
  }

  FinanceRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final now = _now;
    final cutoffDate = _endOfMonth(selectedCutoffMonth);
    final isHistorical = selectedCutoffMonth.year != now.year ||
        selectedCutoffMonth.month != now.month;
    final sheet = repository.balanceSheetAt(cutoffDate);
    final totalAssets = sheet.assets;
    final creditLiability = sheet.cardDebt;
    final loanLiability = sheet.loanDebt;
    final creditCardCredit = sheet.cardCredit;
    final liabilities = sheet.liabilities;
    final netAssets = sheet.netWorth;
    final historicalCutoff = isHistorical ? cutoffDate : null;
    final baseCurrency = repository.baseCurrency;
    final visibleAccounts = _accountsForGroup(repository, selectedGroup).where(
        (account) =>
            account.accountType != AccountType.loan ||
            account.loanStartDate == null ||
            !account.loanStartDate!.isAfter(cutoffDate));
    final goalSummaries =
        repository.assetGoalSummaries(cutoffDate: historicalCutoff);
    final featuredGoal =
        goalSummaries.cast<AssetGoalProgressSummary?>().firstWhere(
              (item) => item != null && !item.isReached,
              orElse: () => goalSummaries.isEmpty ? null : goalSummaries.last,
            );

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= compassDesktopMinWidth;
        final palette = financePaletteOf(context);
        final textTheme = Theme.of(context).textTheme;
        final accountManagement = IconButton(
          tooltip: '个人账户',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AccountSyncPage(repository: repository),
            ),
          ),
          icon: CompassIconBadge(
            icon: Icons.person_rounded,
            size: 38,
            color: palette.seed,
          ),
        );
        final heading = CompassPageHeader(
          title: '账户',
          actions: [
            if (!desktop) ...[
              IconButton(
                key: const Key('asset-goals-entry'),
                tooltip: '资产目标',
                onPressed: () => _openAssetGoals(context, historicalCutoff),
                icon: const CompassIconBadge(
                  icon: Icons.flag_outlined,
                  size: 38,
                  outlined: true,
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (!isHistorical) ...[
              accountManagement,
              const SizedBox(width: 10),
              if (desktop)
                FilledButton.icon(
                  onPressed: () => _editAccount(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('新增账户'),
                )
              else
                SizedBox(
                  width: 40,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: () => _editAccount(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      side: BorderSide(color: palette.textMuted),
                      foregroundColor: palette.textMuted,
                    ),
                    child: const Icon(Icons.add_rounded,
                        size: 26, semanticLabel: '新增账户'),
                  ),
                ),
            ],
          ],
        );
        final netAssetsSummary = [
          Text('净资产', style: textTheme.bodySmall),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              compassMoney(netAssets, currency: baseCurrency),
              key: const Key('accounts-net-worth'),
              style: TextStyle(
                color: netAssets < 0 ? palette.expense : palette.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
                fontFeatures: compassTabularFigures,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AmountSummary(
                  label: '总资产',
                  value: totalAssets,
                  currency: baseCurrency,
                ),
              ),
              Container(
                width: 1,
                height: 86,
                margin: EdgeInsets.symmetric(horizontal: desktop ? 12 : 18),
                color: palette.border,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AmountSummary(
                      label: '负债',
                      value: liabilities,
                      currency: baseCurrency,
                      valueColor: liabilities > 0 ? palette.expense : null,
                    ),
                    const SizedBox(height: 12),
                    _BreakdownLine(
                      label: '信用卡',
                      value: creditLiability,
                      currency: baseCurrency,
                    ),
                    const SizedBox(height: 5),
                    _BreakdownLine(
                      label: '贷款',
                      value: loanLiability,
                      currency: baseCurrency,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sheet.overdrafts > 0)
            _BreakdownLine(
                label: '其他账户负余额',
                value: sheet.overdrafts,
                currency: baseCurrency),
          if (sheet.loanCredit > 0)
            _BreakdownLine(
                label: '贷款溢还', value: sheet.loanCredit, currency: baseCurrency),
          if (creditCardCredit > 0) ...[
            const SizedBox(height: 8),
            _BreakdownLine(
              key: const Key('accounts-card-credit'),
              label: '信用卡溢缴款',
              value: creditCardCredit,
              currency: baseCurrency,
              decimals: 2,
              valueColor: palette.income,
            ),
          ],
        ];
        final goalDetails = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('资产目标', style: textTheme.titleMedium),
                ),
                if (featuredGoal != null)
                  Text(
                    !featuredGoal.valuationAvailable
                        ? '未估值'
                        : featuredGoal.isReached
                            ? '已达成'
                            : '${(featuredGoal.progressRatio * 100).clamp(0, 100).round()}%',
                    style: TextStyle(
                      color: featuredGoal.isReached
                          ? palette.income
                          : palette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
              ],
            ),
            if (featuredGoal != null) ...[
              const SizedBox(height: 3),
              Text(
                '${featuredGoal.goal.name} · 目标 ${compassMoney(featuredGoal.goal.targetAmount, currency: featuredGoal.goal.currency, decimals: 0)}'
                '${repository.assetGoals.length > 1 ? '（共 ${repository.assetGoals.length} 个）' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              if (featuredGoal.valuationAvailable)
                CompassDualProgressBar(
                  actualRatio: featuredGoal.progressRatio.clamp(0.0, 1.0),
                  alertThreshold: 1.0,
                  height: 5,
                  actualColor:
                      featuredGoal.isReached ? palette.income : palette.seed,
                ),
            ] else if (repository.assetGoals.isNotEmpty)
              Text(
                '${repository.assetGoals.length} 个目标',
                style: textTheme.bodySmall,
              ),
          ],
        );
        final assetGoals = CompassCard(
          key: const Key('asset-goals-card'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: () => _openAssetGoals(context, historicalCutoff),
          child: Row(
            children: [
              const CompassIconBadge(
                icon: Icons.flag_outlined,
                size: 42,
                outlined: true,
              ),
              const SizedBox(width: 12),
              Expanded(child: goalDetails),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        );
        final assetColors = desktop || palette.monochrome
            ? financeDonutSeries(context)
            : [palette.seed, const Color(0xFF8A63B4), const Color(0xFF6AA064)];
        final assetGroups = [
          (
            label: '现金',
            value: sheet.assetsIn(ReportGroup.cash),
            color: assetColors[0]
          ),
          (
            label: '投资',
            value: sheet.assetsIn(ReportGroup.investment),
            color: assetColors[2]
          ),
          (
            label: '退休',
            value: sheet.assetsIn(ReportGroup.retirement),
            color: assetColors[1]
          ),
          if (sheet.cardCredit + sheet.loanCredit > 0)
            (
              label: '溢付',
              value: sheet.cardCredit + sheet.loanCredit,
              color: palette.income
            ),
        ];
        final allocation = [
          CompassHelpHeading(
            title: Text('资产分布',
                style: textTheme.titleMedium?.copyWith(fontSize: 17)),
            label: '资产分布',
            message: '外币余额按账本设置的汇率换算为 $baseCurrency，再计入资产汇总。账户仍以原币记账。',
          ),
          const SizedBox(height: 9),
          if (desktop)
            for (final group in assetGroups)
              _AllocationMetric(
                label: group.label,
                value: group.value,
                total: totalAssets,
                currency: baseCurrency,
                color: group.color,
                desktop: true,
              )
          else ...[
            CompassDistributionBar(
              values: [for (final group in assetGroups) group.value],
              colors: [for (final group in assetGroups) group.color],
              height: 10,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (index, group) in assetGroups.indexed) ...[
                  if (index > 0) _VerticalDivider(),
                  Expanded(
                    child: _AllocationMetric(
                      label: group.label,
                      value: group.value,
                      total: totalAssets,
                      currency: baseCurrency,
                      color: group.color,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ];
        final cutoffControls = [
          Align(
            alignment:
                desktop ? AlignmentDirectional.centerStart : Alignment.center,
            child: Semantics(
              button: true,
              label: '选择账户统计截止月份',
              child: InkWell(
                key: const Key('account-cutoff-selector'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => _selectCutoffMonth(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '统计截止 · ${selectedCutoffMonth.year}年${selectedCutoffMonth.month}月',
                          style: textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_drop_down_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isHistorical) ...[
            const SizedBox(height: 8),
            Align(
              alignment:
                  desktop ? AlignmentDirectional.centerStart : Alignment.center,
              child: Container(
                key: const Key('account-historical-cutoff-banner'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.expense.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    CompassHelpHeading(
                      title: Text(
                        '历史统计 · 截至 ${selectedCutoffMonth.year}年${selectedCutoffMonth.month}月末',
                        style: TextStyle(
                          color: palette.expense,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      label: '历史统计',
                      message: '余额和负债统计截至所选月份末。进入账户详情后可查看当时的记录，返回本月即可继续编辑或记账。',
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() => selectedCutoffMonth = _currentMonth);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Text(
                          '返回本月',
                          style: TextStyle(
                            color: palette.seed,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ];
        final groupTotal = switch (selectedGroup) {
          0 => sheet.netIn(ReportGroup.cash),
          1 => creditLiability,
          2 => loanLiability,
          3 => sheet.netIn(ReportGroup.investment),
          _ => sheet.netIn(ReportGroup.retirement),
        };
        final groupTotalLabel = switch (selectedGroup) {
          1 => '负债总额  ${compassMoney(creditLiability, currency: baseCurrency)}',
          2 => '待还总额  ${compassMoney(loanLiability, currency: baseCurrency)}',
          _ => '合计  ${compassMoney(groupTotal, currency: baseCurrency)}',
        };
        final accountList = [
          ...cutoffControls,
          const SizedBox(height: 14),
          _AccountGroupSelector(
            selectedIndex: selectedGroup,
            onChanged: (index) => setState(() => selectedGroup = index),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _groupLabel(selectedGroup),
                  style: textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: Text(
                  groupTotalLabel,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: selectedGroup == 1 ||
                            (selectedGroup == 2 && loanLiability > 0)
                        ? palette.expense
                        : palette.textMuted,
                    fontWeight: FontWeight.w600,
                    fontFeatures: compassTabularFigures,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (visibleAccounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text('此分类还没有账户', style: textTheme.bodySmall),
              ),
            )
          else
            for (final (index, account) in visibleAccounts.indexed) ...[
              if (desktop && index > 0) compassHairline,
              _AccountRow(
                account: account,
                repository: repository,
                cutoffDate: cutoffDate,
                billingDate: isHistorical ? cutoffDate : now,
                isHistorical: isHistorical,
                onTap: () => _openAccount(
                  context,
                  account,
                  cutoffDate: isHistorical ? cutoffDate : null,
                ),
              ),
            ],
          if (selectedGroup == 1) ...[
            compassHairline,
            CompassSettingsRow(
              icon: Icons.calendar_month_outlined,
              title: '管理信用卡账期',
              onTap: () => _manageCreditCards(context, historicalCutoff),
            ),
          ],
        ];

        return ListView(
          padding: compassScrollPadding(
              context,
              desktop
                  ? compassDesktopPagePadding
                  : compassPagePadding.copyWith(bottom: 30)),
          children: [
            heading,
            const SizedBox(height: 18),
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CompassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: accountList,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 324,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CompassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...netAssetsSummary,
                              const SizedBox(height: 14),
                              compassHairline,
                              const SizedBox(height: 14),
                              ...allocation,
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        assetGoals,
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              ...netAssetsSummary,
              const SizedBox(height: 14),
              assetGoals,
              const SizedBox(height: 14),
              ...allocation,
              const SizedBox(height: 18),
              ...accountList,
            ],
          ],
        );
      },
    );
  }

  List<Account> _accountsForGroup(
    FinanceRepository activeRepository,
    int index,
  ) =>
      switch (index) {
        0 => activeRepository.accountsByGroup(ReportGroup.cash),
        1 => activeRepository.accounts
            .where((item) => item.accountType == AccountType.creditCard)
            .toList(),
        2 => activeRepository.accounts
            .where((item) => item.accountType == AccountType.loan)
            .toList(),
        3 => activeRepository.accountsByGroup(ReportGroup.investment),
        _ => activeRepository.accountsByGroup(ReportGroup.retirement),
      };

  Future<void> _selectCutoffMonth(BuildContext context) async {
    final months = _availableCutoffMonths();
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择统计截止月份',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(sheetContext, _currentMonth);
                      },
                      child: const Text('返回本月'),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              compassHairline,
              Expanded(
                child: ListView.separated(
                  key: const Key('account-cutoff-month-list'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: months.length,
                  separatorBuilder: (_, __) => compassHairline,
                  itemBuilder: (_, index) {
                    final month = months[index];
                    final selected = month.year == selectedCutoffMonth.year &&
                        month.month == selectedCutoffMonth.month;
                    return ListTile(
                      key: Key('account-cutoff-${month.year}-${month.month}'),
                      leading: const CompassIconBadge(
                        icon: Icons.calendar_month_outlined,
                        size: 38,
                        outlined: true,
                      ),
                      title: Text('${month.year}年${month.month}月'),
                      trailing: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                        color: selected
                            ? financePaletteOf(context).seed
                            : financePaletteOf(context).textMuted,
                      ),
                      onTap: () => Navigator.pop(sheetContext, month),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => selectedCutoffMonth = selected);
  }

  List<DateTime> _availableCutoffMonths() {
    final now = _now;
    final candidates = <DateTime>[
      DateTime(now.year, now.month),
      ...repository.transactions.map(
        (item) => DateTime(
          item.transactionDate.year,
          item.transactionDate.month,
        ),
      ),
      ...repository.snapshots.map(
        (item) => DateTime(item.snapshotDate.year, item.snapshotDate.month),
      ),
      ...repository.accounts
          .where((item) => item.loanTrackingStartDate != null)
          .map(
            (item) => DateTime(
              item.loanTrackingStartDate!.year,
              item.loanTrackingStartDate!.month,
            ),
          ),
    ];
    candidates
        .removeWhere((item) => item.isAfter(DateTime(now.year, now.month)));
    candidates.sort();
    final first = candidates.first;
    final result = <DateTime>[];
    var cursor = DateTime(first.year, first.month);
    final last = DateTime(now.year, now.month);
    while (!cursor.isAfter(last)) {
      result.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result.reversed.toList();
  }

  Future<void> _editAccount(BuildContext context) async {
    final account = await showDialog<Account>(
      context: context,
      builder: (_) =>
          AccountFormDialog(defaultCurrency: repository.baseCurrency),
    );
    if (account != null) {
      await ref.read(accountMutationsProvider.notifier).addAccount(account);
      if (!mounted || account.accountType != AccountType.loan) return;
      final updatedRepository =
          await ref.read(financeRepositoryProvider.future);
      if (!mounted) return;
      await Navigator.of(this.context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoanDetailScreen(
            account: account,
            repository: updatedRepository,
            promptForPlannedGeneration: true,
          ),
        ),
      );
    }
  }

  void _openAssetGoals(BuildContext context, DateTime? cutoffDate) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AssetGoalsPage(repository: repository, cutoffDate: cutoffDate),
      ),
    );
  }

  void _openAccount(
    BuildContext context,
    Account account, {
    DateTime? cutoffDate,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (account.accountType) {
          AccountType.creditCard => CreditCardDetailScreen(
              account: account,
              repository: repository,
              cutoffDate: cutoffDate,
            ),
          AccountType.loan => LoanDetailScreen(
              account: account,
              repository: repository,
              cutoffDate: cutoffDate,
            ),
          _ => AccountDetailScreen(
              account: account,
              repository: repository,
              cutoffDate: cutoffDate,
            ),
        },
      ),
    );
  }

  Future<void> _manageCreditCards(
      BuildContext context, DateTime? cutoffDate) async {
    final cards = repository.accounts
        .where((item) => item.accountType == AccountType.creditCard)
        .toList();
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有信用卡账户。')),
      );
      return;
    }
    final selected = await showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择信用卡', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...cards.map(
              (card) => ListTile(
                title: Text(card.name),
                subtitle: Text(
                    '结算日 ${card.statementDay ?? '-'} · 还款日 ${card.paymentDueDay ?? '-'}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, card),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      _openAccount(context, selected, cutoffDate: cutoffDate);
    }
  }
}

class _AmountSummary extends StatelessWidget {
  const _AmountSummary({
    required this.label,
    required this.value,
    required this.currency,
    this.valueColor,
  });

  final String label;
  final double value;
  final String currency;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              compassMoney(value, currency: currency),
              style: TextStyle(
                color: valueColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFeatures: compassTabularFigures,
              ),
            ),
          ),
        ],
      );
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({
    super.key,
    required this.label,
    required this.value,
    required this.currency,
    this.decimals = 0,
    this.valueColor,
  });

  final String label;
  final double value;
  final String currency;
  final int decimals;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              compassMoney(value, currency: currency, decimals: decimals),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: valueColor,
                    fontWeight: valueColor != null ? FontWeight.w600 : null,
                    fontFeatures: compassTabularFigures,
                  ),
            ),
          ),
        ],
      );
}

class _AllocationMetric extends StatelessWidget {
  const _AllocationMetric({
    required this.label,
    required this.value,
    required this.total,
    required this.currency,
    required this.color,
    this.desktop = false,
  });

  final String label;
  final double value;
  final double total;
  final String currency;
  final Color color;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final share = '${total == 0 ? 0 : (value / total * 100).round()}%';
    final amount = compassMoney(value, currency: currency);
    final amountStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFeatures: compassTabularFigures,
        );
    final shareColor = palette.monochrome ? palette.textPrimary : color;
    if (desktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 8),
            Text(label),
            const SizedBox(width: 12),
            Expanded(
              child: Text(amount, style: amountStyle, textAlign: TextAlign.end),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 42,
              child: FittedBox(
                alignment: AlignmentDirectional.centerEnd,
                fit: BoxFit.scaleDown,
                child: Text(
                  share,
                  style: amountStyle?.copyWith(
                    color: shareColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Text(
          share,
          style: TextStyle(
            color: shareColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFeatures: compassTabularFigures,
          ),
        ),
        const SizedBox(height: 4),
        Text(label),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(amount, style: amountStyle),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 48,
        color: financePaletteOf(context).border,
      );
}

class _AccountGroupSelector extends StatelessWidget {
  const _AccountGroupSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['现金', '信用', '贷款', '投资', '退休'];
    final palette = financePaletteOf(context);
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? palette.seed : Colors.transparent,
                  border: index == 0
                      ? null
                      : Border(
                          left: BorderSide(color: palette.border),
                        ),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected
                        ? financeForegroundOn(palette.seed)
                        : palette.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.repository,
    required this.cutoffDate,
    required this.billingDate,
    required this.isHistorical,
    required this.onTap,
  });

  final Account account;
  final FinanceRepository repository;
  final DateTime cutoffDate;
  final DateTime billingDate;
  final bool isHistorical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final scopedTransactions = isHistorical
        ? repository.transactions
            .where((t) => !t.transactionDate.isAfter(cutoffDate))
        : repository.transactions;
    final rawBalance = repository.accountBalanceAt(account.id, cutoffDate);
    final usageAmount = account.accountType == AccountType.creditCard
        ? isHistorical
            ? repository.creditCardOutstandingBalance(account.id,
                cutoffDate: cutoffDate)
            : repository.creditCardCommittedOutstandingBalance(account.id)
        : null;
    final overpaid = account.accountType == AccountType.creditCard
        ? repository.creditCardCreditBalance(
            account.id,
            cutoffDate: cutoffDate,
          )
        : 0.0;
    final billing = account.accountType == AccountType.creditCard
        ? repository.creditCardBillingSummary(
            account.id,
            cutoffDate: isHistorical ? cutoffDate : null,
            now: billingDate,
          )
        : null;
    final cardDisplay = billing == null || usageAmount == null
        ? null
        : _accountCardDisplay(
            resolveCreditCardDisplayState(
              summary: billing,
              hasBilledActivity: hasCreditCardBilledActivity(
                account: account,
                transactions: scopedTransactions,
                now: billingDate,
              ),
              now: billingDate,
              committedOutstanding: usageAmount,
            ),
            billing,
            palette,
            usageAmount: usageAmount,
            historical: isHistorical,
          );
    final amount = cardDisplay?.amount ??
        (account.accountType == AccountType.loan
            ? (-rawBalance).clamp(0.0, double.infinity).toDouble()
            : rawBalance.abs());
    final isNegativeCash = account.accountType != AccountType.creditCard &&
        account.accountType != AccountType.loan &&
        rawBalance < 0;
    final baseCurrency = repository.baseCurrency;
    final foreignCurrency = account.currency.trim().toUpperCase() !=
        baseCurrency.trim().toUpperCase();
    final baseEquivalent = foreignCurrency
        ? repository.tryConvertAmount(
            amount: isNegativeCash ? -amount : amount,
            fromCurrency: account.currency,
            toCurrency: baseCurrency,
          )
        : null;
    final savedReconciliation =
        repository.reconciledMonthForAccount(account.id);
    final cutoffMonth =
        '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}';
    final reconciledMonth = isHistorical &&
            savedReconciliation != null &&
            savedReconciliation.compareTo(cutoffMonth) > 0
        ? null
        : savedReconciliation;
    final isInvestmentGroup =
        account.effectiveReportGroup == ReportGroup.investment ||
            account.effectiveReportGroup == ReportGroup.retirement;
    double? investmentReturnRatio;
    if (isInvestmentGroup) {
      final remainingCost = repository.remainingCostBasisForAccount(
        account.id,
        upToDate: cutoffDate,
      );
      if (remainingCost > 0) {
        investmentReturnRatio = (rawBalance - remainingCost) / remainingCost;
      }
    }
    final creditLimit = account.creditLimit;
    final creditUtilization = usageAmount != null &&
            creditLimit != null &&
            creditLimit.isFinite &&
            creditLimit > 0
        ? (usageAmount / creditLimit).clamp(0.0, 1.0)
        : null;
    final subtitle = billing == null
        ? [
            if (!account.isActive && !isHistorical) '已停用',
            account.institution,
            if (account.accountType == AccountType.loan && rawBalance > 0)
              '溢还 ${compassMoney(rawBalance, currency: account.currency)}',
            if (account.accountType == AccountType.loan &&
                account.hasCompleteLoanProfile)
              '${account.loanAnnualInterestRate!.toStringAsFixed(2)}% · ${account.loanTermMonths}期',
            account.currency,
            if (reconciledMonth != null) '已对账 $reconciledMonth',
          ].whereType<String>().where((item) => item.isNotEmpty).join(' · ')
        : [
            if (!account.isActive && !isHistorical) '已停用',
            if (!isHistorical &&
                usageAmount != null &&
                ((usageAmount - amount).abs() > .005 ||
                    (usageAmount - billing.outstandingBalance).abs() > .005 ||
                    (account.currentBalance - rawBalance).abs() > .005))
              '含未来承诺余额 ${compassMoney(account.currentBalance, currency: account.currency)}',
            billing.isEstimated
                ? '当前为估算提醒'
                : '结算日 ${account.statementDay}日 · 还款日 ${account.paymentDueDay}日',
            if (reconciledMonth != null) '已对账 $reconciledMonth',
          ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            CompassIconBadge(
              icon: _accountIcon(account.accountType),
              color: palette.seed,
              size: 46,
              outlined: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  if (billing != null ||
                      investmentReturnRatio != null ||
                      creditUtilization != null)
                    _AccountStatusExtras(
                      cardDisplay: cardDisplay,
                      overpaid: overpaid,
                      currency: account.currency,
                      investmentReturnRatio: investmentReturnRatio,
                      creditUtilization: creditUtilization,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _AccountAmountColumn(
              amountLabel: cardDisplay?.amountLabel,
              isNegativeCash: isNegativeCash,
              amount: amount,
              currency: account.currency,
              amountColor: cardDisplay?.amountColor ??
                  (isNegativeCash ? palette.expense : palette.textPrimary),
              baseEquivalent: baseEquivalent,
              baseCurrency: baseCurrency,
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 24),
          ],
        ),
      ),
    );
  }
}

class _AccountStatusExtras extends StatelessWidget {
  const _AccountStatusExtras({
    required this.cardDisplay,
    required this.overpaid,
    required this.currency,
    required this.investmentReturnRatio,
    required this.creditUtilization,
  });

  final _AccountCardDisplay? cardDisplay;
  final double overpaid;
  final String currency;
  final double? investmentReturnRatio;
  final double? creditUtilization;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cardDisplay != null || investmentReturnRatio != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (cardDisplay case final display?) ...[
                CompassStatusBadge(
                  label: display.statusLabel,
                  color: display.badgeColor,
                ),
                if (display.nextUsage case final next?)
                  Text('下期已用 ${compassMoney(next, currency: currency)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                          fontFeatures: compassTabularFigures)),
                if (display.otherStatements > 0)
                  Text('另有 ${display.otherStatements} 期已出账待还',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.textMuted)),
              ],
              if (overpaid > 0)
                CompassStatusBadge(
                  label: '溢缴 ${compassMoney(overpaid, currency: currency)}',
                  color: palette.income,
                ),
              if (investmentReturnRatio case final rate?)
                CompassStatusBadge(
                  label:
                      '${rate >= 0 ? '+' : ''}${(rate * 100).toStringAsFixed(1)}%',
                  color: rate >= 0 ? palette.income : palette.expense,
                ),
            ],
          ),
        ],
        if (creditUtilization case final ratio?) ...[
          const SizedBox(height: 7),
          CompassDualProgressBar(
            actualRatio: ratio,
            alertThreshold: 0.75,
            height: 4,
          ),
          const SizedBox(height: 3),
          Text(
            '额度已用 ${(ratio * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  fontFeatures: compassTabularFigures,
                ),
          ),
        ],
      ],
    );
  }
}

class _AccountAmountColumn extends StatelessWidget {
  const _AccountAmountColumn({
    required this.amountLabel,
    required this.isNegativeCash,
    required this.amount,
    required this.currency,
    required this.amountColor,
    required this.baseEquivalent,
    required this.baseCurrency,
  });

  final String? amountLabel;
  final bool isNegativeCash;
  final double amount;
  final String currency;
  final Color amountColor;
  final double? baseEquivalent;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (amountLabel case final label?)
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            '${isNegativeCash ? '- ' : ''}${compassMoney(amount, currency: currency)}',
            style: TextStyle(
              color: amountColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: compassTabularFigures,
            ),
          ),
          if (baseEquivalent case final eq?) ...[
            const SizedBox(height: 2),
            Text(
              '≈ ${compassMoney(eq, currency: baseCurrency)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontFeatures: compassTabularFigures,
                  ),
            ),
          ] else if (normalizeCurrency(currency) !=
              normalizeCurrency(baseCurrency))
            Text('未估值', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _AccountCardDisplay {
  const _AccountCardDisplay({
    required this.statusLabel,
    required this.badgeColor,
    required this.amountLabel,
    required this.amount,
    required this.amountColor,
    this.nextUsage,
    this.otherStatements = 0,
  });

  final String statusLabel;
  final Color badgeColor;
  final String amountLabel;
  final double amount;
  final Color amountColor;
  final double? nextUsage;
  final int otherStatements;
}

_AccountCardDisplay _accountCardDisplay(
  CreditCardDisplayState state,
  CreditCardBillingSummary summary,
  FinanceThemePalette palette, {
  required double usageAmount,
  required bool historical,
}) {
  final hasNextUsage = summary.unbilledBalance > .005;
  final paymentDue = state == CreditCardDisplayState.overdue ||
      state == CreditCardDisplayState.dueToday ||
      state == CreditCardDisplayState.paymentDue;
  final warningBadge =
      paymentDue || state == CreditCardDisplayState.profileIncomplete;
  final (badge, label, liveAmount) = switch (state) {
    CreditCardDisplayState.overdue => ('逾期未还', '逾期应还', summary.billedBalance),
    CreditCardDisplayState.dueToday => ('今日到期', '今日应还', summary.billedBalance),
    CreditCardDisplayState.paymentDue => ('待还款', '本期应还', summary.billedBalance),
    CreditCardDisplayState.paidThisCycle when hasNextUsage => (
        '本期已还清',
        '下期已使用',
        summary.unbilledBalance
      ),
    CreditCardDisplayState.paidThisCycle => ('本期已还清', '本期账单', 0.0),
    CreditCardDisplayState.unbilledOnly when hasNextUsage => (
        '尚未出账',
        '下期已使用',
        summary.unbilledBalance
      ),
    CreditCardDisplayState.unbilledOnly => ('尚未出账', '当前欠款', usageAmount),
    CreditCardDisplayState.noBalance => ('暂无欠款', '当前欠款', 0.0),
    CreditCardDisplayState.profileIncomplete => (
        '账期待设置',
        '当前欠款（估算）',
        usageAmount
      ),
  };
  // In history usageAmount is the debt at the selected cutoff. A positive
  // balance owed can have a paid badge when it belongs to a later statement.
  final amount = historical ? usageAmount : liveAmount;
  final colorAsDue = historical ? paymentDue && amount > .005 : warningBadge;
  final amountColor = colorAsDue
      ? palette.expense
      : amount > .005
          ? palette.textPrimary
          : palette.income;
  return _AccountCardDisplay(
    statusLabel: badge,
    badgeColor: warningBadge ? palette.expense : palette.income,
    amountLabel: historical ? '月末欠款' : label,
    amount: amount,
    amountColor: amountColor,
    nextUsage: !historical && paymentDue && hasNextUsage
        ? summary.unbilledBalance
        : null,
    otherStatements:
        !historical && paymentDue && summary.openStatements.length > 1
            ? summary.openStatements.length - 1
            : 0,
  );
}

String _groupLabel(int index) => switch (index) {
      0 => '现金账户',
      1 => '信用卡',
      2 => '贷款',
      3 => '投资账户',
      _ => '退休账户',
    };

IconData _accountIcon(AccountType type) => switch (type) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.bankSaving => Icons.account_balance_outlined,
      AccountType.eWallet => Icons.wallet_outlined,
      AccountType.creditCard => Icons.credit_card_rounded,
      AccountType.moneyMarketFund || AccountType.fund => Icons.savings_outlined,
      AccountType.pension => Icons.beach_access_outlined,
      AccountType.stock ||
      AccountType.trading =>
        Icons.candlestick_chart_outlined,
      AccountType.crypto => Icons.currency_bitcoin,
      AccountType.loan => Icons.request_quote_outlined,
      AccountType.other => Icons.account_balance_wallet_outlined,
    };

DateTime _endOfMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999);
