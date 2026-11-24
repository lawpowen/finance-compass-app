import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/asset_snapshot.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/mutations/asset_mutations.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';
import '../shared/simple_charts.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';
import 'account_form_dialog.dart';
import 'asset_snapshot_form_dialog.dart';

class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({
    super.key,
    required this.account,
    required this.repository,
    this.cutoffDate,
  });

  final Account account;
  final FinanceRepository repository;
  final DateTime? cutoffDate;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  bool _isSaving = false;
  bool _showAllTransactions = false;
  DateTime? _historicalCutoff;

  @override
  void initState() {
    super.initState();
    _historicalCutoff = widget.cutoffDate;
  }

  FinanceRepository get _repository {
    final async = ref.watch(financeRepositoryProvider);
    return async.valueOrNull ?? widget.repository;
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final liveAccount = repository.accounts.firstWhere(
      (item) => item.id == widget.account.id,
      orElse: () => widget.account,
    );
    final palette = financePaletteOf(context);
    final supportsMarketValue =
        liveAccount.reportGroup == ReportGroup.investment ||
            liveAccount.reportGroup == ReportGroup.retirement;
    final cutoffDate = _historicalCutoff ?? repository.currentMonthCutoffDate();
    final isHistorical = _historicalCutoff != null;
    final visibleSnapshots =
        repository.snapshotsForAccountUpTo(liveAccount.id, cutoffDate);
    final latestSnapshot =
        visibleSnapshots.isEmpty ? null : visibleSnapshots.last;
    final displayedMarketValue = latestSnapshot == null
        ? 0.0
        : repository.accountBalanceAt(liveAccount.id, cutoffDate);
    final displayedCostBasis = latestSnapshot == null
        ? 0.0
        : repository.costBasisForAccount(
            liveAccount.id,
            upToDate: cutoffDate,
          );
    final displayedCashBalance = latestSnapshot == null
        ? 0.0
        : repository.cashBalanceForAccount(
            liveAccount.id,
            upToDate: cutoffDate,
          );
    final displayedRemainingCostBasis = latestSnapshot == null
        ? 0.0
        : repository.remainingCostBasisForAccount(
            liveAccount.id,
            upToDate: cutoffDate,
          );
    final latestFlow = latestSnapshot == null
        ? const InvestmentFlowSummary(contribution: 0, withdrawal: 0)
        : repository.investmentFlowSummaryForAccount(
            liveAccount.id,
            upToDate: cutoffDate,
          );

    final subtitleParts = [
      _groupLabel(liveAccount.reportGroup),
      liveAccount.currency,
      if (liveAccount.institution != null &&
          liveAccount.institution!.trim().isNotEmpty)
        liveAccount.institution!.trim(),
    ];

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          body: CompassBackground(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sidePadding =
                      math.max(20.0, (constraints.maxWidth - 840) / 2);
                  return ListView(
                    padding: compassScrollPadding(
                      context,
                      EdgeInsets.fromLTRB(sidePadding, 14, sidePadding, 32),
                    ),
                    children: [
                      CompassPageHeader(
                        leading: const CompassBackButton(),
                        title: liveAccount.name,
                        subtitle: subtitleParts.join(' · '),
                        actions: isHistorical
                            ? const []
                            : [
                                IconButton(
                                  tooltip: '编辑账户',
                                  onPressed: () => _editAccount(liveAccount),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                      ),
                      if (isHistorical) ...[
                        const SizedBox(height: 12),
                        _HistoricalCutoffBanner(
                          cutoffDate: cutoffDate,
                          onReturnCurrent: () =>
                              setState(() => _historicalCutoff = null),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (supportsMarketValue)
                        ..._buildInvestmentSections(
                          context,
                          repository: repository,
                          account: liveAccount,
                          palette: palette,
                          cutoffDate: cutoffDate,
                          isHistorical: isHistorical,
                          visibleSnapshots: visibleSnapshots,
                          latestSnapshot: latestSnapshot,
                          displayedMarketValue: displayedMarketValue,
                          displayedCostBasis: displayedCostBasis,
                          displayedCashBalance: displayedCashBalance,
                          displayedRemainingCostBasis:
                              displayedRemainingCostBasis,
                          latestFlow: latestFlow,
                        )
                      else
                        ..._buildCashAccountSections(
                          context,
                          repository: repository,
                          account: liveAccount,
                          palette: palette,
                          cutoffDate: cutoffDate,
                          isHistorical: isHistorical,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (_isSaving)
          IgnorePointer(
            child: Container(
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCashAccountSections(
    BuildContext context, {
    required FinanceRepository repository,
    required Account account,
    required FinanceThemePalette palette,
    required DateTime cutoffDate,
    required bool isHistorical,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final balance = repository.accountBalanceAt(account.id, cutoffDate);
    final baseCurrency = repository.baseCurrency;
    final foreignCurrency = account.currency.trim().toUpperCase() !=
        baseCurrency.trim().toUpperCase();
    final cutoffMonth = monthKeyFromDate(cutoffDate);
    final reconciledMonth = repository.reconciledMonthForAccount(account.id);
    final isReconciledForCutoff = reconciledMonth == cutoffMonth;
    final accountTransactions = repository.transactions
        .where((item) =>
            (item.accountId == account.id || item.toAccountId == account.id) &&
            !item.transactionDate.isAfter(cutoffDate))
        .toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    var monthInflow = 0.0;
    var monthOutflow = 0.0;
    for (final item in accountTransactions) {
      if (!item.affectsBalance ||
          monthKeyFromDate(item.transactionDate) != cutoffMonth) {
        continue;
      }
      final delta = repository.transactionDeltaForAccount(account.id, item);
      if (delta >= 0) {
        monthInflow += delta;
      } else {
        monthOutflow += -delta;
      }
    }
    final monthNet = monthInflow - monthOutflow;
    final visibleTransactions = _showAllTransactions
        ? accountTransactions
        : accountTransactions.take(15).toList();
    final trace = repository.accountBalanceTrace(account.id, cutoffDate);

    return [
      CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isHistorical ? '截至月末余额' : '当前余额',
                    style: textTheme.bodySmall,
                  ),
                ),
                CompassStatusBadge(
                  label: reconciledMonth == null
                      ? '未标记对账'
                      : '已对账 $reconciledMonth',
                  color: reconciledMonth == null
                      ? palette.textMuted
                      : palette.income,
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                compassMoney(balance, currency: account.currency),
                key: const Key('account-detail-balance'),
                style: TextStyle(
                  color: balance < 0 ? palette.expense : palette.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFeatures: compassTabularFigures,
                ),
              ),
            ),
            if (foreignCurrency) ...[
              const SizedBox(height: 4),
              CompassHelpHeading(
                title: Text(
                  '≈ ${compassMoney(repository.convertToBase(balance, account.currency), currency: baseCurrency)}',
                  style: textTheme.bodySmall?.copyWith(
                    fontFeatures: compassTabularFigures,
                  ),
                ),
                label: '外币折合',
                message:
                    '按账本设置的汇率将 ${account.currency} 余额折合为 $baseCurrency。原币余额用于记账及对账。',
              ),
            ],
            if (account.note != null && account.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(account.note!.trim(), style: textTheme.bodySmall),
            ],
            if (!isHistorical && !isReconciledForCutoff) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _markReconciled(account.id, cutoffMonth),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: Text('标记已对账至 $cutoffMonth'),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CompassSectionTitle('$cutoffMonth 账户收支'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: '流入',
                    value:
                        compassMoney(monthInflow, currency: account.currency),
                    accent: monthInflow > 0 ? palette.income : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    label: '流出',
                    value:
                        compassMoney(monthOutflow, currency: account.currency),
                    accent: monthOutflow > 0 ? palette.expense : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    label: '净变化',
                    value:
                        '${monthNet > 0 ? '+ ' : ''}${compassMoney(monthNet, currency: account.currency)}',
                    accent: monthNet > 0
                        ? palette.income
                        : (monthNet < 0 ? palette.expense : null),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CompassSectionTitle(
              '账户流水明细',
              trailing: Text(
                '${accountTransactions.length} 笔',
                style: textTheme.bodySmall?.copyWith(
                  fontFeatures: compassTabularFigures,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (visibleTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '暂无账户流水记录。',
                  style: textTheme.bodySmall,
                ),
              )
            else ...[
              for (var i = 0; i < visibleTransactions.length; i++) ...[
                if (i > 0) compassHairline,
                _AccountTransactionRow(
                  transaction: visibleTransactions[i],
                  account: account,
                  repository: repository,
                  onTap: isHistorical
                      ? null
                      : () => _editTransaction(
                            repository,
                            visibleTransactions[i],
                          ),
                ),
              ],
              if (accountTransactions.length > 15) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(
                    () => _showAllTransactions = !_showAllTransactions,
                  ),
                  child: Text(
                    _showAllTransactions
                        ? '收起至最近 15 笔'
                        : '展开全部 ${accountTransactions.length} 笔流水',
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CompassSectionTitle('余额追溯'),
            const SizedBox(height: 10),
            _TraceSummaryLine(
              label: trace.sourceLabel,
              value: compassMoney(
                trace.sourceAmount,
                currency: account.currency,
              ),
            ),
            for (final entry in trace.entries.take(6)) ...[
              const SizedBox(height: 6),
              _TraceSummaryLine(
                label:
                    '${entry.date.month}月${entry.date.day}日 · ${entry.title}',
                value:
                    '${entry.delta >= 0 ? '+ ' : ''}${compassMoney(entry.delta, currency: account.currency)}',
                accent: entry.delta >= 0 ? palette.income : palette.expense,
              ),
            ],
            if (trace.entries.length > 6) ...[
              const SizedBox(height: 6),
              Text(
                '另有 ${trace.entries.length - 6} 笔期后调整',
                style: textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            compassHairline,
            const SizedBox(height: 8),
            _TraceSummaryLine(
              label: '截至余额',
              value: compassMoney(
                trace.endingBalance,
                currency: account.currency,
              ),
              emphasized: true,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildInvestmentSections(
    BuildContext context, {
    required FinanceRepository repository,
    required Account account,
    required FinanceThemePalette palette,
    required DateTime cutoffDate,
    required bool isHistorical,
    required List<AssetSnapshot> visibleSnapshots,
    required AssetSnapshot? latestSnapshot,
    required double displayedMarketValue,
    required double displayedCostBasis,
    required double displayedCashBalance,
    required double displayedRemainingCostBasis,
    required InvestmentFlowSummary latestFlow,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final unrealized = displayedMarketValue - displayedRemainingCostBasis;
    final unrealizedRatio = displayedRemainingCostBasis == 0
        ? 0.0
        : (unrealized / displayedRemainingCostBasis) * 100;
    return [
      CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CompassHelpHeading(
              title: Text(isHistorical ? '历史资产' : '当前资产',
                  style: textTheme.titleMedium?.copyWith(fontSize: 17)),
              label: isHistorical ? '历史资产' : '当前资产',
              message: isHistorical
                  ? '资产数据计算到所选月份末。历史记录为只读。'
                  : '投入与取出根据交易记录计算。录入市值后可查看走势及未实现盈亏。',
            ),
            const SizedBox(height: 14),
            if (!isHistorical) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : () => _addSnapshot(account.id),
                  icon: const Icon(Icons.show_chart_rounded),
                  label: Text(latestSnapshot == null ? '录入当前市值' : '更新当前市值'),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (latestSnapshot == null)
              Text(
                '暂无市值记录',
                style: textTheme.bodySmall,
              )
            else ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricPill(
                    label: '总市值',
                    value: compassMoney(
                      displayedMarketValue,
                      currency: account.currency,
                    ),
                  ),
                  _MetricPill(
                    label: '累计投入',
                    value: compassMoney(
                      latestFlow.contribution,
                      currency: account.currency,
                    ),
                  ),
                  _MetricPill(
                    label: '累计取出',
                    value: compassMoney(
                      latestFlow.withdrawal,
                      currency: account.currency,
                    ),
                  ),
                  _MetricPill(
                    label: '累计成本',
                    value: compassMoney(
                      displayedCostBasis,
                      currency: account.currency,
                    ),
                  ),
                  _MetricPill(
                    label: '现金余额',
                    value: compassMoney(
                      displayedCashBalance,
                      currency: account.currency,
                    ),
                  ),
                  _MetricPill(
                    label: '未实现盈亏',
                    value:
                        '${unrealized > 0 ? '+ ' : ''}${compassMoney(unrealized, currency: account.currency)} '
                        '(${unrealizedRatio.toStringAsFixed(1)}%)',
                    accent: unrealized >= 0 ? palette.income : palette.expense,
                  ),
                ],
              ),
              if (visibleSnapshots.length > 1) ...[
                const SizedBox(height: 16),
                MultiLineChart(
                  series: _buildFlowSeries(visibleSnapshots, repository),
                  amountBuilder: (value) => compassMoney(
                    value,
                    currency: account.currency,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      CompassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CompassHelpHeading(
              title: Text('快照记录',
                  style: textTheme.titleMedium?.copyWith(fontSize: 17)),
              label: '快照记录',
              message:
                  isHistorical ? '仅显示统计截止日及以前的快照。' : '修改或删除快照后，账户余额与资产图表会重新计算。',
            ),
            const SizedBox(height: 12),
            if (visibleSnapshots.isEmpty)
              Text('还没有资产快照。', style: textTheme.bodySmall)
            else
              for (final snapshot in visibleSnapshots.reversed)
                _SnapshotRow(
                  snapshot: snapshot,
                  repository: repository,
                  currency: account.currency,
                  onEdit: isHistorical ? null : () => _editSnapshot(snapshot),
                  onDelete:
                      isHistorical ? null : () => _deleteSnapshot(snapshot),
                ),
          ],
        ),
      ),
    ];
  }

  Future<void> _editAccount(Account current) async {
    final updated = await showDialog<Account>(
      context: context,
      builder: (_) => AccountFormDialog(initialAccount: current),
    );
    if (!mounted || updated == null) return;
    await ref.read(accountMutationsProvider.notifier).updateAccount(updated);
  }

  Future<void> _markReconciled(String accountId, String monthKey) async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(accountMutationsProvider.notifier)
          .setAccountReconciledMonth(accountId, monthKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已标记对账至 $monthKey')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editTransaction(
    FinanceRepository repository,
    FinanceTransaction transaction,
  ) async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: repository,
          draft: transaction,
          editExisting: true,
        ),
      ),
    );
    if (result == null) return;
    final mutations = ref.read(transactionMutationsProvider.notifier);
    if (result.deletedTransactionId case final transactionId?) {
      await mutations.deleteTransaction(transactionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('交易已删除')),
        );
      }
      return;
    }
    if (result.transactions.length == 1) {
      await mutations.updateTransaction(result.transactions.single);
    }
  }

  Future<void> _addSnapshot(String accountId) async {
    final result = await showDialog<AssetSnapshot>(
      context: context,
      builder: (_) => AssetSnapshotFormDialog(
        repository: _repository,
        initialAccountId: accountId,
      ),
    );
    if (!mounted || result == null) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(assetMutationsProvider.notifier).addSnapshot(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前市值已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editSnapshot(AssetSnapshot snapshot) async {
    final result = await showDialog<AssetSnapshot>(
      context: context,
      builder: (_) => AssetSnapshotFormDialog(
        repository: _repository,
        initialSnapshot: snapshot,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(assetMutationsProvider.notifier).updateSnapshot(result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资产快照已保存')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteSnapshot(AssetSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除资产快照'),
            content: const Text('删除后会重新计算这个账户的当前余额。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(assetMutationsProvider.notifier)
          .deleteSnapshot(snapshot.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资产快照已删除')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  List<ChartSeries> _buildFlowSeries(
      List<AssetSnapshot> snapshots, FinanceRepository repository) {
    final contributionPoints = <ChartPoint>[];
    final withdrawalPoints = <ChartPoint>[];
    final marketValuePoints = <ChartPoint>[];

    for (final snapshot in snapshots) {
      final summary = repository.investmentFlowSummaryForAccount(
        snapshot.accountId,
        upToDate: snapshot.snapshotDate,
      );
      final label =
          '${snapshot.snapshotDate.month}/${snapshot.snapshotDate.day}';
      contributionPoints.add(
        ChartPoint(label: label, value: summary.contribution),
      );
      withdrawalPoints.add(
        ChartPoint(label: label, value: summary.withdrawal),
      );
      marketValuePoints.add(
        ChartPoint(
          label: label,
          value: repository.accountBalanceAt(
              snapshot.accountId, snapshot.snapshotDate),
        ),
      );
    }

    return const [
      Color(0xFF0F766E),
      Color(0xFFB45309),
      Color(0xFF1D4ED8),
    ].asMap().entries.map((entry) {
      final index = entry.key;
      final color = entry.value;
      switch (index) {
        case 0:
          return ChartSeries(
            label: '累计投入',
            points: contributionPoints,
            color: color,
          );
        case 1:
          return ChartSeries(
            label: '累计取出',
            points: withdrawalPoints,
            color: color,
          );
        default:
          return ChartSeries(
            label: '总市值',
            points: marketValuePoints,
            color: color,
          );
      }
    }).toList();
  }

  String _groupLabel(ReportGroup group) {
    switch (group) {
      case ReportGroup.cash:
        return '现金';
      case ReportGroup.credit:
        return '信用';
      case ReportGroup.investment:
        return '投资';
      case ReportGroup.retirement:
        return '退休';
    }
  }
}

class _HistoricalCutoffBanner extends StatelessWidget {
  const _HistoricalCutoffBanner({
    required this.cutoffDate,
    required this.onReturnCurrent,
  });

  final DateTime cutoffDate;
  final VoidCallback onReturnCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Container(
      key: const Key('account-detail-historical-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.expense.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 20, color: palette.expense),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '历史统计 · 截至 ${cutoffDate.year}年${cutoffDate.month}月末 · 只读',
            ),
          ),
          const CompassHelpButton(
            title: '账户历史统计',
            message: '余额、流水和资产按所选月末统计。切换到当前后可编辑账户和交易。',
          ),
          TextButton(
            key: const Key('account-detail-return-current'),
            onPressed: onReturnCurrent,
            child: const Text('切换到当前'),
          ),
        ],
      ),
    );
  }
}

class _AccountTransactionRow extends StatelessWidget {
  const _AccountTransactionRow({
    required this.transaction,
    required this.account,
    required this.repository,
    this.onTap,
  });

  final FinanceTransaction transaction;
  final Account account;
  final FinanceRepository repository;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final delta =
        repository.transactionDeltaForAccount(account.id, transaction);
    final color = delta > 0
        ? palette.income
        : (delta < 0 ? palette.expense : palette.textPrimary);
    final categoryName = transaction.categoryId == null
        ? null
        : repository.categoryName(transaction.categoryId!);
    final isTransfer = transaction.type == TransactionType.transfer;
    final counterparty = isTransfer
        ? (transaction.accountId == account.id
            ? '转出至 ${transaction.toAccountId == null ? '其他账户' : repository.accountName(transaction.toAccountId!)}'
            : '转入自 ${repository.accountName(transaction.accountId)}')
        : (categoryName ?? '调整');
    final title = transaction.merchant?.trim().isNotEmpty == true
        ? transaction.merchant!.trim()
        : (transaction.description?.trim().isNotEmpty == true
            ? transaction.description!.trim()
            : counterparty);
    final date = transaction.transactionDate;
    final planned = transaction.status == TransactionStatus.planned;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
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
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${date.month}月${date.day}日 · $counterparty',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (planned)
                      CompassStatusBadge(label: '预计', color: palette.warning),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${delta > 0 ? '+ ' : ''}${compassMoney(delta, currency: account.currency)}',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: compassTabularFigures,
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: row,
    );
  }
}

class _TraceSummaryLine extends StatelessWidget {
  const _TraceSummaryLine({
    required this.label,
    required this.value,
    this.accent,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color? accent;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: emphasized
                ? Theme.of(context).textTheme.titleSmall
                : Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: accent ??
                (emphasized ? palette.textPrimary : palette.textMuted),
            fontSize: emphasized ? 14 : 12,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: compassTabularFigures,
          ),
        ),
      ],
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.snapshot,
    required this.repository,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final AssetSnapshot snapshot;
  final FinanceRepository repository;
  final String currency;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final flow = repository.investmentFlowSummaryForAccount(
      snapshot.accountId,
      upToDate: snapshot.snapshotDate,
    );
    final displayedMarketValue = repository.accountBalanceAt(
      snapshot.accountId,
      snapshot.snapshotDate,
    );
    final pnl =
        displayedMarketValue - repository.snapshotRemainingCostBasis(snapshot);
    final ratio = repository.snapshotPnlRatio(snapshot);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: palette.surfaceAlt.withValues(alpha: 0.72),
        border: Border.all(color: palette.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${snapshot.snapshotDate.year}-${snapshot.snapshotDate.month.toString().padLeft(2, '0')}-${snapshot.snapshotDate.day.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (onEdit != null)
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑',
                ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                  '总市值 ${compassMoney(displayedMarketValue, currency: currency)}'),
              Text(
                  '累计投入 ${compassMoney(flow.contribution, currency: currency)}'),
              Text('累计取出 ${compassMoney(flow.withdrawal, currency: currency)}'),
              Text(
                  '累计成本 ${compassMoney(repository.snapshotCostBasis(snapshot), currency: currency)}'),
              Text(
                  '现金余额 ${compassMoney(snapshot.cashBalance, currency: currency)}'),
              Text(
                '未实现盈亏 ${compassMoney(pnl, currency: currency)} (${(ratio * 100).toStringAsFixed(1)}%)',
                style: TextStyle(
                  color: pnl >= 0 ? palette.income : palette.expense,
                  fontWeight: FontWeight.w700,
                  fontFeatures: compassTabularFigures,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.surfaceAlt.withValues(alpha: 0.72),
        border: Border.all(color: palette.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: accent ?? palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: compassTabularFigures,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
