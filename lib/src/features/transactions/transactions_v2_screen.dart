import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/models/category_hierarchy.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart' show moneyDisplayParts;
import '../shared/compass_ui.dart';
import '../shared/finance_action_menu_button.dart';
import 'transaction_automation_pages.dart';
import 'transaction_composer_page.dart';
import 'transaction_form_dialog.dart';

enum _TransactionBasis {
  consumption,
  cash,
  committed,
}

enum _FilterDimension { account, type, category }

class TransactionsV2Screen extends ConsumerStatefulWidget {
  const TransactionsV2Screen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<TransactionsV2Screen> createState() =>
      _TransactionsV2ScreenState();
}

class _TransactionsV2ScreenState extends ConsumerState<TransactionsV2Screen> {
  int monthOffset = 0;
  bool includePlanned = false;
  _TransactionFilters filters = const _TransactionFilters();
  _TransactionBasis selectedBasis = _TransactionBasis.consumption;
  final Set<String> selectedTransactionIds = {};
  bool selectionMode = false;
  bool isDeleting = false;
  _TransactionsMonthData? _cachedMonthData;

  FinanceRepository get repository =>
      ref.read(financeRepositoryProvider).valueOrNull ?? widget.repository;

  bool get isSelecting => selectionMode || selectedTransactionIds.isNotEmpty;

  _TransactionsMonthData _monthDataFor(FinanceRepository currentRepo) {
    final now = DateTime.now();
    final dayKey = now.year * 10000 + now.month * 100 + now.day;
    final cached = _cachedMonthData;
    if (cached != null &&
        identical(cached.repository, currentRepo) &&
        cached.monthOffset == monthOffset &&
        cached.includePlanned == includePlanned &&
        cached.filters == filters &&
        cached.dayKey == dayKey) {
      return cached;
    }

    final month = DateTime(now.year, now.month + monthOffset);
    final monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999);
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final accountsById = {
      for (final account in currentRepo.accounts) account.id: account,
    };
    final realForMonth = currentRepo.transactions
        .where((item) =>
            item.transactionDate.year == month.year &&
            item.transactionDate.month == month.month)
        .toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    final matchedCategories = <String>{
      for (final id in filters.categoryIds)
        ...currentRepo.categoryHierarchy.descendantsOf(id),
    };
    final filteredForMonth = realForMonth
        .where((item) => filters.matches(item, matchedCategories))
        .toList();
    final visible = filteredForMonth
        .where((item) =>
            includePlanned || item.status != TransactionStatus.planned)
        .toList();
    final fundingNeed = monthOffset >= 0
        ? currentRepo.monthlyFundingNeedForMonth(
            monthKey,
            includePlanned: includePlanned,
          )
        : null;
    final basisSummaries = {
      for (final basis in _TransactionBasis.values)
        basis: _summaryFor(
          basis,
          visible,
          monthEnd: monthEnd,
          currentRepo: currentRepo,
          accountsById: accountsById,
          fundingNeed: fundingNeed,
        ),
    };
    final mobileEntries = _buildMobileEntries(
      visible,
      currentRepo: currentRepo,
    );
    return _cachedMonthData = _TransactionsMonthData(
      repository: currentRepo,
      month: month,
      monthOffset: monthOffset,
      includePlanned: includePlanned,
      filters: filters,
      dayKey: dayKey,
      accountsById: accountsById,
      visible: visible,
      fundingNeed: fundingNeed,
      basisSummaries: basisSummaries,
      mobileEntries: mobileEntries,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    if (!identical(_cachedMonthData?.repository, current) && filters.isActive) {
      filters = filters.normalized(current);
    }
    final data = _monthDataFor(current);
    final selectedSummary = data.basisSummaries[selectedBasis]!;

    return LayoutBuilder(
      builder: (context, constraints) => _ledger(
        context,
        desktop: constraints.maxWidth >= compassDesktopMinWidth,
        data: data,
        selectedSummary: selectedSummary,
      ),
    );
  }

  Widget _ledger(
    BuildContext context, {
    required bool desktop,
    required _TransactionsMonthData data,
    required _BasisSummary selectedSummary,
  }) {
    final month = data.month;
    final basisSummaries = data.basisSummaries;
    final fundingNeed = data.fundingNeed;
    final visible = data.visible;
    final mobileEntries = data.mobileEntries;
    final palette = financePaletteOf(context);
    final baseCurrency = repository.baseCurrency;
    final searchAction = _HeaderAction(
      icon: Icons.search_rounded,
      tooltip: '搜索交易',
      onPressed: _openSearch,
    );
    final filterAction = _HeaderAction(
      icon: Icons.filter_alt_outlined,
      tooltip: '高级筛选',
      onPressed: () => _openFilterSheet(_FilterDimension.values.toSet()),
    );
    final monthSelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded, size: 19),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
          ),
        ),
        Text('${month.year}年${month.month}月',
            style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          tooltip: '下个月',
          onPressed: monthOffset >= 120 ? null : () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right_rounded, size: 19),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
          ),
        ),
        if (monthOffset != 0)
          TextButton(
            key: const Key('transaction-month-today'),
            onPressed: _resetToCurrentMonth,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('本月'),
          ),
      ],
    );
    final statusSwitch = _StatusSwitch(
      includePlanned: includePlanned,
      onChanged: (value) => setState(() {
        selectionMode = false;
        selectedTransactionIds.clear();
        includePlanned = value;
      }),
    );
    final hasActiveFilters = filters.isActive;
    final filterPills = [
      _QuickFilterPill(
        key: const Key('transaction-filter-account'),
        icon: Icons.account_balance_wallet_outlined,
        label: _selectionLabel(
          filters.accountIds,
          allLabel: '全部账户',
          unit: '个账户',
          nameOf: (id) => data.accountsById[id]?.name ?? '账户已移除',
        ),
        selected: filters.accountIds.isNotEmpty,
        onTap: () => _openFilterSheet({_FilterDimension.account}),
      ),
      _QuickFilterPill(
        key: const Key('transaction-filter-type'),
        icon: Icons.list_alt_rounded,
        label: _selectionLabel(
          filters.types,
          allLabel: '全部类型',
          unit: '种类型',
          nameOf: _typeName,
        ),
        selected: filters.types.isNotEmpty,
        onTap: () => _openFilterSheet({_FilterDimension.type}),
      ),
      _QuickFilterPill(
        key: const Key('transaction-filter-category'),
        icon: Icons.sell_outlined,
        label: _selectionLabel(
          filters.categoryIds,
          allLabel: '全部类别',
          unit: '个类别',
          nameOf: (id) =>
              data.repository.categoryHierarchy.byId[id]?.name ?? '类别已移除',
        ),
        selected: filters.categoryIds.isNotEmpty,
        onTap: () => _openFilterSheet({_FilterDimension.category}),
      ),
      if (hasActiveFilters)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ActionChip(
            key: const Key('transaction-filter-reset'),
            avatar: Icon(Icons.close_rounded, size: 15, color: palette.expense),
            label: Text(
              '清除筛选',
              style: TextStyle(fontSize: 11, color: palette.expense),
            ),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: palette.expense.withValues(alpha: .35)),
            onPressed: _resetFilters,
          ),
        ),
    ];
    final (primaryDotColor, secondaryDotColor) = switch (selectedBasis) {
      _TransactionBasis.consumption => (palette.income, palette.expense),
      _TransactionBasis.cash => (
          fundingNeed != null && !hasActiveFilters
              ? palette.textPrimary
              : palette.income,
          fundingNeed != null && !hasActiveFilters
              ? palette.warning
              : palette.expense,
        ),
      _TransactionBasis.committed => (palette.warning, palette.income),
    };
    final breakdown = [
      _FlowLegend(
        key: const Key('transaction-basis-primary'),
        color: primaryDotColor,
        label:
            '${selectedSummary.primaryLabel} ${compassMoney(selectedSummary.primary, currency: baseCurrency, decimals: 0)}',
        compact: desktop,
      ),
      _FlowLegend(
        key: const Key('transaction-basis-secondary'),
        color: secondaryDotColor,
        label:
            '${selectedSummary.secondaryLabel} ${compassMoney(selectedSummary.secondary, currency: baseCurrency, decimals: 0)}',
        compact: desktop,
      ),
    ];
    final basisHelp = CompassHelpButton(
      title: '${selectedSummary.title}口径',
      message: switch (selectedBasis) {
        _TransactionBasis.consumption =>
          '按交易发生日统计收入和消费。账户间转账不计入消费。「包含预计」会计入本期预计交易。',
        _TransactionBasis.cash => hasActiveFilters
            ? '流入和流出按所选月份及筛选条件统计。筛选账户时，只计算所选现金账户的变动。全月需准备现金独立统计。'
            : fundingNeed == null
                ? '统计历史月份现金账户的流入和流出。信用卡与贷款还款按现金支付金额计入。「包含预计」会计入本期预计交易。'
                : '需准备现金包括本月已知现金流出，以及尚未安排的到期信用卡和贷款还款。已安排的还款不会重复计入。这个总额不会随下方筛选变化。',
        _TransactionBasis.committed =>
          '按所选月末逐户统计欠款。选择类型或类别时，显示筛选流水在本月增加或减少的欠款。「包含预计」加入所选月份的预计交易。',
      },
    );
    final desktopActionStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );

    final headerControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompassPageHeader(
          title: isSelecting ? '已选择 ${selectedTransactionIds.length} 笔' : '交易',
          leading: isSelecting
              ? IconButton(
                  tooltip: '退出选择',
                  onPressed: isDeleting ? null : _clearSelection,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          actions: isSelecting
              ? [
                  _HeaderAction(
                    icon: Icons.select_all_rounded,
                    tooltip: '选择当前列表全部交易',
                    onPressed:
                        isDeleting ? null : () => _selectAllVisible(visible),
                  ),
                  const SizedBox(width: 8),
                  _HeaderAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: '删除所选交易',
                    color: financePaletteOf(context).expense,
                    onPressed: isDeleting ? null : _deleteSelected,
                  ),
                ]
              : desktop
                  ? [
                      OutlinedButton.icon(
                        onPressed: () => _showQuickTemplates(context),
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('快捷模板'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _showTransactionEditor(context),
                        icon: const Icon(Icons.add_rounded, size: 19),
                        label: const Text('记账'),
                      ),
                    ]
                  : [searchAction, const SizedBox(width: 8), filterAction],
        ),
        const SizedBox(height: 14),
        if (!desktop) Center(child: monthSelector),
        _BasisCards(
          summaries: basisSummaries,
          selected: selectedBasis,
          desktop: desktop,
          currency: baseCurrency,
          onSelected: (basis) => setState(() => selectedBasis = basis),
        ),
        if (!desktop) ...[
          const SizedBox(height: 12),
          statusSwitch,
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: desktop
                  ? Wrap(spacing: 20, runSpacing: 4, children: breakdown)
                  : Row(
                      children: [
                        for (final entry in breakdown) Expanded(child: entry),
                      ],
                    ),
            ),
            basisHelp,
          ],
        ),
        if (selectedBasis == _TransactionBasis.cash && fundingNeed != null) ...[
          Text(
            '${hasActiveFilters ? '全月需准备现金 ${compassMoney(fundingNeed.totalCashRequired, currency: baseCurrency, decimals: 0)} · ' : ''}'
            '到期信用 ${compassMoney(fundingNeed.creditDue, currency: baseCurrency, decimals: 0)} · '
            '到期贷款 ${compassMoney(fundingNeed.loanDue, currency: baseCurrency, decimals: 0)} · '
            '已安排 ${compassMoney(fundingNeed.coveredDebtPayments, currency: baseCurrency, decimals: 0)}',
            key: const Key('monthly-funding-need-note'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFeatures: compassTabularFigures,
                ),
          ),
        ],
        SizedBox(height: desktop ? 20 : 10),
        if (desktop) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    monthSelector,
                    ...filterPills,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          style: desktopActionStyle,
                          onPressed: _openSearch,
                          icon: const Icon(Icons.search_rounded, size: 17),
                          label: const Text('搜索'),
                        ),
                        TextButton.icon(
                          style: desktopActionStyle,
                          onPressed: () => _openFilterSheet(
                            _FilterDimension.values.toSet(),
                          ),
                          icon: const Icon(
                            Icons.filter_alt_outlined,
                            size: 17,
                          ),
                          label: const Text('高级筛选'),
                        ),
                        if (visible.isNotEmpty && !isSelecting)
                          TextButton.icon(
                            style: desktopActionStyle,
                            onPressed: () =>
                                setState(() => selectionMode = true),
                            icon: const Icon(
                              Icons.checklist_rounded,
                              size: 17,
                            ),
                            label: const Text('多选'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: SizedBox(width: 168, child: statusSwitch),
              ),
            ],
          ),
        ] else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filterPills,
            ),
          ),
        const SizedBox(height: 12),
      ],
    );

    final useCompactDesktopCard = desktop && visible.length <= 40;
    final itemCount = visible.isEmpty
        ? 2
        : desktop
            ? (useCompactDesktopCard ? 2 : visible.length + 2)
            : 1 + mobileEntries.length;

    return Stack(
      children: [
        ListView.builder(
          cacheExtent: 600,
          padding: compassScrollPadding(
              context,
              desktop
                  ? compassDesktopPagePadding
                  : compassPagePadding.copyWith(bottom: 108)),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) return headerControls;
            if (visible.isEmpty) {
              return CompassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Text(
                        hasActiveFilters ? '当前筛选下没有交易' : '这个月份没有符合条件的交易',
                      ),
                      const SizedBox(height: 10),
                      if (hasActiveFilters)
                        OutlinedButton(
                          onPressed: _resetFilters,
                          child: const Text('清除筛选'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () => _showTransactionEditor(context),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('记一笔'),
                        ),
                    ],
                  ),
                ),
              );
            }
            if (desktop) {
              if (useCompactDesktopCard) {
                return CompassCard(
                  padding: EdgeInsets.zero,
                  radius: 14,
                  child: Column(
                    children: [
                      const _DesktopLedgerHeader(),
                      ..._transactionWidgets(context, visible, desktop: true),
                    ],
                  ),
                );
              }
              return _desktopVirtualItem(context, visible, index - 1, palette);
            }
            final entry = mobileEntries[index - 1];
            if (entry.transaction == null) {
              return _mobileDayHeader(
                context,
                palette,
                entry.dateLabel!,
                entry.daySummary!,
              );
            }
            final item = entry.transaction!;
            final row = _buildTransactionRow(context, item, desktop: false);
            if (!entry.showDivider) return row;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [row, const Divider()],
            );
          },
        ),
        if (!desktop && !isSelecting)
          Positioned(
            right: 18,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: Column(
              children: [
                CompassActionBubble(
                  key: const Key('transactions_v2_quick'),
                  heroTag: 'transactions_v2_quick',
                  icon: Icons.bolt_rounded,
                  color: palette.surface,
                  foregroundColor: palette.textPrimary,
                  borderColor: palette.border,
                  elevation: 3,
                  onPressed: () => _showQuickTemplates(context),
                ),
                const SizedBox(height: 9),
                CompassActionBubble(
                  heroTag: 'transactions_v2_add',
                  icon: Icons.add_rounded,
                  color: palette.resolvedPrimaryAction,
                  onPressed: () => _showTransactionEditor(context),
                ),
              ],
            ),
          ),
      ],
    );
  }

  _BasisSummary _summaryFor(
    _TransactionBasis basis,
    List<FinanceTransaction> scopedTransactions, {
    required DateTime monthEnd,
    required FinanceRepository currentRepo,
    required Map<String, Account> accountsById,
    MonthlyFundingNeed? fundingNeed,
  }) {
    switch (basis) {
      case _TransactionBasis.consumption:
        final income = scopedTransactions
            .where((item) => item.type == TransactionType.income)
            .fold<double>(
              0,
              (sum, item) => sum + currentRepo.transactionAmountInBase(item),
            );
        final expense = scopedTransactions
            .where((item) => item.type == TransactionType.expense)
            .fold<double>(
              0,
              (sum, item) => sum + currentRepo.transactionAmountInBase(item),
            );
        return _BasisSummary(
          title: '实际消费',
          subtitle: '收支净额',
          value: income - expense,
          primaryLabel: '收入',
          primary: income,
          secondaryLabel: '支出',
          secondary: expense,
          icon: Icons.receipt_long_outlined,
        );
      case _TransactionBasis.cash:
        var inflow = 0.0;
        var outflow = 0.0;
        for (final item in scopedTransactions) {
          final delta = _cashDelta(item, currentRepo, accountsById);
          if (delta >= 0) {
            inflow += delta;
          } else {
            outflow += -delta;
          }
        }
        if (fundingNeed != null && !filters.isActive) {
          return _BasisSummary(
            title: '实际现金',
            subtitle: '需准备现金',
            value: fundingNeed.totalCashRequired,
            primaryLabel: '已知流出',
            primary: fundingNeed.knownCashOutflow,
            secondaryLabel: '尚未安排',
            secondary: fundingNeed.uncoveredDebtDue,
            icon: Icons.account_balance_wallet_outlined,
            valueIsOutflow: true,
          );
        }
        return _BasisSummary(
          title: '实际现金',
          subtitle: filters.isActive
              ? '筛选现金流出'
              : includePlanned
                  ? '历史流出含预计'
                  : '历史实际流出',
          value: outflow,
          primaryLabel: '流入',
          primary: inflow,
          secondaryLabel: '流出',
          secondary: outflow,
          icon: Icons.account_balance_wallet_outlined,
          valueIsOutflow: true,
        );
      case _TransactionBasis.committed:
        final creditAccounts = {
          for (final account in accountsById.values)
            if (account.effectiveReportGroup == ReportGroup.credit &&
                (filters.accountIds.isEmpty ||
                    filters.accountIds.contains(account.id)))
              account.id: account,
        };
        final plannedDeltas = <String, double>{};
        var additions = 0.0;
        var reductions = 0.0;
        void applyMovement(String accountId, FinanceTransaction item) {
          final account = creditAccounts[accountId];
          if (account == null) return;
          final delta = currentRepo.valuationBook
              .deltaFor(accountId, item, includePlanned: true);
          if (item.status == TransactionStatus.planned) {
            plannedDeltas[accountId] = (plannedDeltas[accountId] ?? 0) + delta;
          }
          final amount = currentRepo.convertToBase(delta, account.currency);
          if (amount < 0) {
            additions -= amount;
          } else {
            reductions += amount;
          }
        }
        for (final item in scopedTransactions) {
          applyMovement(item.accountId, item);
          final target = item.toAccountId;
          if (item.type == TransactionType.transfer &&
              target != null &&
              target != item.accountId) {
            applyMovement(target, item);
          }
        }
        final value = filters.hasTransactionCriteria
            ? additions - reductions
            : creditAccounts.values.fold<double>(0, (sum, account) {
                final balance =
                    currentRepo.accountBalanceAt(account.id, monthEnd) +
                        (plannedDeltas[account.id] ?? 0);
                return balance < 0
                    ? sum +
                        currentRepo.convertToBase(-balance, account.currency)
                    : sum;
              });
        return _BasisSummary(
          title: '信用/贷款',
          subtitle: filters.hasTransactionCriteria
              ? '筛选欠款净变动'
              : includePlanned
                  ? '月末含预计'
                  : '月末欠款',
          value: value,
          primaryLabel: '新增承诺',
          primary: additions,
          secondaryLabel: '偿还抵扣',
          secondary: reductions,
          icon: Icons.verified_user_outlined,
        );
    }
  }

  double _cashDelta(
    FinanceTransaction transaction,
    FinanceRepository currentRepo,
    Map<String, Account> accountsById,
  ) {
    bool isSelectedCash(String? id) =>
        id != null &&
        (filters.accountIds.isEmpty || filters.accountIds.contains(id)) &&
        accountsById[id]?.effectiveReportGroup == ReportGroup.cash;
    final sourceIsCash = isSelectedCash(transaction.accountId);
    final targetIsCash = isSelectedCash(transaction.toAccountId);
    final amount = currentRepo.transactionAmountInBase(transaction);
    switch (transaction.type) {
      case TransactionType.income:
        return sourceIsCash ? amount : 0;
      case TransactionType.expense:
        return sourceIsCash ? -amount : 0;
      case TransactionType.adjustment:
        return sourceIsCash ? amount : 0;
      case TransactionType.transfer:
        var delta = 0.0;
        if (sourceIsCash) delta -= amount;
        if (targetIsCash) {
          delta += currentRepo.transferIncomingAmountInBase(transaction);
        }
        return delta;
    }
  }

  List<_MobileLedgerEntry> _buildMobileEntries(
    List<FinanceTransaction> transactions, {
    required FinanceRepository currentRepo,
  }) {
    final entries = <_MobileLedgerEntry>[];
    final baseCurrency = currentRepo.baseCurrency;
    var index = 0;
    while (index < transactions.length) {
      final date = DateUtils.dateOnly(transactions[index].transactionDate);
      var dayIncome = 0.0;
      var dayExpense = 0.0;
      var probe = index;
      while (probe < transactions.length &&
          DateUtils.dateOnly(transactions[probe].transactionDate) == date) {
        final row = transactions[probe];
        final baseAmount = currentRepo.transactionAmountInBase(row);
        if (row.type == TransactionType.income) {
          dayIncome += baseAmount;
        } else if (row.type == TransactionType.expense) {
          dayExpense += baseAmount;
        }
        probe++;
      }
      final dayCount = probe - index;
      final summaryParts = <String>[
        if (moneyDisplayParts(dayIncome).sign != 0)
          '收 ${dayIncome > 0 ? '+' : ''}${compassMoney(dayIncome, currency: baseCurrency)}',
        if (moneyDisplayParts(dayExpense).sign != 0)
          '支 ${compassMoney(dayExpense, currency: baseCurrency)}',
      ];
      entries.add(
        _MobileLedgerEntry.dayHeader(
          dateLabel: '${date.month}月${date.day}日',
          daySummary:
              summaryParts.isEmpty ? '$dayCount 笔' : summaryParts.join(' · '),
        ),
      );
      for (var i = index; i < probe; i++) {
        entries.add(
          _MobileLedgerEntry.row(
            transaction: transactions[i],
            showDivider: true,
          ),
        );
      }
      index = probe;
    }
    return entries;
  }

  Widget _mobileDayHeader(
    BuildContext context,
    FinanceThemePalette palette,
    String dateLabel,
    String daySummary,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 5),
        child: Row(
          children: [
            Text(
              dateLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                daySummary,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontFeatures: compassTabularFigures,
                    ),
              ),
            ),
          ],
        ),
      );

  Widget _desktopVirtualItem(
    BuildContext context,
    List<FinanceTransaction> visible,
    int tableIndex,
    FinanceThemePalette palette,
  ) {
    final borderSide = BorderSide(
      color: palette.border,
      width: palette.monochrome ? 1.0 : .8,
    );
    if (tableIndex == 0) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border(top: borderSide, left: borderSide, right: borderSide),
        ),
        child: const _DesktopLedgerHeader(),
      );
    }
    final rowIndex = tableIndex - 1;
    final isLast = rowIndex == visible.length - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.resolvedCardSurface,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(14))
            : BorderRadius.zero,
        border: Border(
          left: borderSide,
          right: borderSide,
          bottom: isLast ? borderSide : BorderSide.none,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTransactionRow(context, visible[rowIndex], desktop: true),
          if (!isLast) const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(
    BuildContext context,
    FinanceTransaction item, {
    required bool desktop,
  }) =>
      _TransactionRow(
        item: item,
        repository: repository,
        desktop: desktop,
        selected: selectedTransactionIds.contains(item.id),
        onLongPress: () => _toggleSelection(item.id),
        onTap: () => isSelecting
            ? _toggleSelection(item.id)
            : _showTransactionEditor(
                context,
                draft: item,
                editExisting: true,
              ),
        onAction: isSelecting
            ? null
            : (value) => _handleTransactionAction(
                  context,
                  value,
                  item,
                ),
      );

  List<Widget> _transactionWidgets(
    BuildContext context,
    List<FinanceTransaction> transactions, {
    required bool desktop,
  }) {
    final widgets = <Widget>[];
    for (var index = 0; index < transactions.length; index++) {
      final item = transactions[index];
      widgets.add(_buildTransactionRow(context, item, desktop: desktop));
      if (!desktop || index < transactions.length - 1) {
        widgets.add(desktop ? const Divider(height: 1) : const Divider());
      }
    }
    return widgets;
  }

  Future<void> _showTransactionEditor(
    BuildContext context, {
    FinanceTransaction? draft,
    bool editExisting = false,
    String? title,
  }) async {
    final opening = repository;
    final scope = ProviderScope.containerOf(context, listen: false);
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => UncontrolledProviderScope(
          container: scope,
          child: TransactionComposerPage(
            repository: opening,
            draft: draft,
            editExisting: editExisting,
            title: title,
          ),
        ),
      ),
    );
    if (result == null || !mounted || !context.mounted) return;
    if (!identical(opening.database, repository.database)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账本已切换，请重新选择交易。')),
      );
      return;
    }
    final mutations = ref.read(transactionMutationsProvider.notifier);
    try {
      if (result.deletedTransactionId case final transactionId?) {
        await mutations.deleteTransaction(transactionId,
            expectedDatabase: opening.database);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('交易已删除')),
          );
        }
        return;
      }
      if (editExisting && result.transactions.length == 1) {
        await mutations.updateTransaction(result.transactions.first,
            expectedDatabase: opening.database);
      } else if (result.transactions.length == 1) {
        await mutations.addTransaction(result.transactions.first,
            expectedDatabase: opening.database);
      } else {
        await mutations.addTransactions(result.transactions,
            expectedDatabase: opening.database);
      }
      if (!editExisting && result.transactions.length > 1 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已生成 ${result.transactions.length} 笔周期交易')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('交易操作失败：$error')));
      }
    }
  }

  Future<void> _handleTransactionAction(
    BuildContext context,
    String value,
    FinanceTransaction transaction,
  ) async {
    if (value == 'edit') {
      await _showTransactionEditor(
        context,
        draft: transaction,
        editExisting: true,
      );
      return;
    }
    if (value == 'reuse') {
      await _showTransactionEditor(
        context,
        draft: transaction,
        title: '复制新增交易',
      );
      return;
    }
    if (value == 'template') {
      await _saveTransactionTemplate(context, transaction);
      return;
    }
    if (value == 'recurring') {
      await _saveRecurringRule(context, transaction);
      return;
    }
    if (value == 'delete') {
      await _confirmAndDelete(context, [transaction.id]);
    }
  }

  Future<void> _saveTransactionTemplate(
    BuildContext context,
    FinanceTransaction transaction,
  ) async {
    final opening = repository;
    var pendingName = _transactionActionName(transaction);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存为模板'),
        content: TextFormField(
          initialValue: pendingName,
          autofocus: true,
          onChanged: (value) => pendingName = value,
          decoration: const InputDecoration(
            labelText: '模板名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, pendingName.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    if (!context.mounted ||
        !await saveTransactionPreset(context, ref,
            expectedDatabase: opening.database,
            name: name,
            transaction: transaction,
            fromStoredTransaction: true)) {
      return;
    }
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('模板「$name」已保存')),
    );
  }

  Future<void> _saveRecurringRule(
    BuildContext context,
    FinanceTransaction transaction,
  ) async {
    final opening = repository;
    var pendingName = _transactionActionName(transaction);
    var intervalMonths = 1;
    final result = await showDialog<_RecurringRuleDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('保存为周期规则'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: pendingName,
                autofocus: true,
                onChanged: (value) => pendingName = value,
                decoration: const InputDecoration(
                  labelText: '规则名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: intervalMonths,
                decoration: const InputDecoration(
                  labelText: '重复间隔',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('每月')),
                  DropdownMenuItem(value: 2, child: Text('每 2 个月')),
                  DropdownMenuItem(value: 3, child: Text('每季')),
                  DropdownMenuItem(value: 12, child: Text('每年')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => intervalMonths = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _RecurringRuleDraft(
                  name: pendingName.trim(),
                  intervalMonths: intervalMonths,
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !context.mounted || result == null || result.name.isEmpty) {
      return;
    }
    if (!await saveTransactionPreset(context, ref,
        expectedDatabase: opening.database,
        name: result.name,
        transaction: transaction,
        intervalMonths: result.intervalMonths,
        fromStoredTransaction: true)) {
      return;
    }
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('周期规则「${result.name}」已保存，并生成未来 3 个完整月份的预计交易'),
      ),
    );
  }

  String _transactionActionName(FinanceTransaction transaction) {
    final direct = transaction.description?.trim().isNotEmpty == true
        ? transaction.description!.trim()
        : transaction.merchant?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (transaction.categoryId != null) {
      return repository.categoryHierarchy.byId[transaction.categoryId]?.name ??
          _typeName(transaction.type);
    }
    return _typeName(transaction.type);
  }

  void _openSearch() {
    final scope = ProviderScope.containerOf(context, listen: false);
    final opening = repository;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: scope,
          child: _TransactionSearchPage(
            repository: opening,
            onAction: (searchContext, value, item) async {
              if (mounted && identical(opening.database, repository.database)) {
                await _handleTransactionAction(searchContext, value, item);
              }
            },
            onDelete: (searchContext, ids) async {
              if (!mounted || !identical(opening.database, repository.database)) {
                return false;
              }
              return _confirmAndDelete(searchContext, ids);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openFilterSheet(Set<_FilterDimension> dimensions) async {
    final title = dimensions.length == 1
        ? switch (dimensions.first) {
            _FilterDimension.account => '筛选账户',
            _FilterDimension.type => '筛选类型',
            _FilterDimension.category => '筛选类别',
          }
        : '筛选交易';
    final ledgerScope = ProviderScope.containerOf(context, listen: false);
    final openingRepository = repository;
    final result = await showModalBottomSheet<_TransactionFilters>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => UncontrolledProviderScope(
          container: ledgerScope,
          child: Consumer(builder: (context, sheetRef, _) {
            final current =
                sheetRef.watch(financeRepositoryProvider).valueOrNull ??
                    openingRepository;
            return _TransactionFilterSheet(
              title: title,
              dimensions: dimensions,
              initial: filters,
              accounts: {
                for (final account in current.accounts) account.id: account.name
              },
              categories: current.sortedCategories(),
              categoryPath: current.categoryHierarchy.pathOf,
            );
          })),
    );
    if (!mounted || result == null) return;
    setState(() {
      selectedTransactionIds.clear();
      filters = result.normalized(repository);
    });
  }

  String _selectionLabel<T>(
    Set<T> values, {
    required String allLabel,
    required String unit,
    required String Function(T value) nameOf,
  }) {
    if (values.isEmpty) return allLabel;
    if (values.length == 1) return nameOf(values.first);
    return '已选 ${values.length} $unit';
  }

  void _changeMonth(int delta) {
    setState(() {
      selectionMode = false;
      selectedTransactionIds.clear();
      monthOffset = (monthOffset + delta).clamp(-120, 120);
      if (monthOffset > 0) includePlanned = true;
    });
  }

  void _resetToCurrentMonth() {
    setState(() {
      selectionMode = false;
      selectedTransactionIds.clear();
      monthOffset = 0;
    });
  }

  void _resetFilters() {
    setState(() {
      selectionMode = false;
      selectedTransactionIds.clear();
      filters = const _TransactionFilters();
    });
  }

  void _toggleSelection(String transactionId) {
    if (isDeleting) return;
    setState(() {
      if (!selectedTransactionIds.add(transactionId)) {
        selectedTransactionIds.remove(transactionId);
      }
    });
  }

  void _selectAllVisible(List<FinanceTransaction> visible) {
    setState(() {
      selectedTransactionIds.addAll(visible.map((item) => item.id));
    });
  }

  void _clearSelection() {
    setState(() {
      selectionMode = false;
      selectedTransactionIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final ids = selectedTransactionIds.toList(growable: false);
    if (ids.isEmpty) return;
    if (await _confirmAndDelete(context, ids) && mounted) _clearSelection();
  }

  Future<bool> _confirmAndDelete(
      BuildContext actionContext, List<String> ids) async {
    if (isDeleting || ids.isEmpty) return false;
    final opening = repository;
    final confirmed = await showDialog<bool>(
          context: actionContext,
          builder: (dialogContext) => AlertDialog(
            title: Text('删除 ${ids.length} 笔交易？'),
            content: Text(
              ids.length == 1
                  ? '删除后会立即撤销这笔交易对账户余额的影响。'
                  : '删除后会一次性撤销所选交易对账户余额的影响。此操作无法撤销。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: financePaletteOf(dialogContext).expense,
                  foregroundColor: financeForegroundOn(
                      financePaletteOf(dialogContext).expense),
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted || !actionContext.mounted) return false;
    if (!identical(opening.database, repository.database)) {
      ScaffoldMessenger.of(actionContext).showSnackBar(
        const SnackBar(content: Text('账本已切换，请重新选择交易。')),
      );
      return false;
    }

    setState(() => isDeleting = true);
    try {
      await ref
          .read(transactionMutationsProvider.notifier)
          .deleteTransactions(ids, expectedDatabase: opening.database);
      if (actionContext.mounted) {
        ScaffoldMessenger.of(actionContext).showSnackBar(
          SnackBar(content: Text('已删除 ${ids.length} 笔交易')),
        );
      }
      return true;
    } catch (error) {
      if (actionContext.mounted) {
        ScaffoldMessenger.of(actionContext).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => isDeleting = false);
    }
  }

  Future<void> _showQuickTemplates(BuildContext context) async {
    final templates = repository.transactionTemplates;
    final draft = await showGeneralDialog<FinanceTransaction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭快速模板',
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Align(
          alignment: const Alignment(.9, .45),
          child: Material(
            color: financePaletteOf(context).surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: financePaletteOf(context).border),
            ),
            child: SizedBox(
              width: 258,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('快速记账',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '关闭快速模板',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (templates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          '还没有快速模板，请先到“管理”建立模板。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ...templates.take(5).map(
                          (item) => InkWell(
                            onTap: () => Navigator.pop(
                                dialogContext,
                                item.toTransaction(
                                    id: 'draft_${item.id}',
                                    date: DateTime.now())),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: financePaletteOf(context).border,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CompassIconBadge(
                                    icon: _typeIcon(item.type),
                                    size: 34,
                                    color: item.type == TransactionType.income
                                        ? financePaletteOf(context).seed
                                        : financePaletteOf(context).expense,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(item.name),
                                  ),
                                  Text(
                                    compassMoney(
                                      item.amount,
                                      currency: item.currency,
                                    ),
                                    style: TextStyle(
                                      color: item.type == TransactionType.income
                                          ? financePaletteOf(context).seed
                                          : financePaletteOf(context).expense,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QuickTemplateManagerPage(
                                  repository: repository,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.grid_view_rounded, size: 18),
                          label: const Text('管理模板'),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecurringPlanPage(
                                  repository: repository,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.repeat_rounded, size: 18),
                          label: const Text('周期计划'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (draft == null || !mounted) return;
    await _showTransactionEditor(context, draft: draft);
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, size: 19, color: color),
        ),
      );
}

class _TransactionsMonthData {
  const _TransactionsMonthData({
    required this.repository,
    required this.month,
    required this.monthOffset,
    required this.includePlanned,
    required this.filters,
    required this.dayKey,
    required this.accountsById,
    required this.visible,
    required this.fundingNeed,
    required this.basisSummaries,
    required this.mobileEntries,
  });

  final FinanceRepository repository;
  final DateTime month;
  final int monthOffset;
  final bool includePlanned;
  final _TransactionFilters filters;
  final int dayKey;
  final Map<String, Account> accountsById;
  final List<FinanceTransaction> visible;
  final MonthlyFundingNeed? fundingNeed;
  final Map<_TransactionBasis, _BasisSummary> basisSummaries;
  final List<_MobileLedgerEntry> mobileEntries;
}

class _MobileLedgerEntry {
  const _MobileLedgerEntry.dayHeader({
    required this.dateLabel,
    required this.daySummary,
  })  : transaction = null,
        showDivider = false;

  const _MobileLedgerEntry.row({
    required FinanceTransaction this.transaction,
    required this.showDivider,
  })  : dateLabel = null,
        daySummary = null;

  final String? dateLabel;
  final String? daySummary;
  final FinanceTransaction? transaction;
  final bool showDivider;
}

@immutable
class _TransactionFilters {
  const _TransactionFilters({
    this.accountIds = const {},
    this.types = const {},
    this.categoryIds = const {},
  });

  /// 空集合表示“全部”；同一维度内为 OR，不同维度之间为 AND。
  /// 转账的来源账户或目标账户任一命中即视为命中账户筛选。
  final Set<String> accountIds;
  final Set<TransactionType> types;
  final Set<String> categoryIds;

  bool get hasTransactionCriteria => types.isNotEmpty || categoryIds.isNotEmpty;
  bool get isActive => accountIds.isNotEmpty || hasTransactionCriteria;

  _TransactionFilters normalized(FinanceRepository current) {
    final accountKeys = current.accounts.map((a) => a.id).toSet();
    final tree = current.categoryHierarchy;
    return _TransactionFilters(
      accountIds: accountIds.intersection(accountKeys),
      types: types,
      categoryIds: categoryIds.where((id) {
        final category = tree.byId[id];
        return category != null && _allowsCategory(types, category);
      }).toSet(),
    );
  }

  bool matches(FinanceTransaction item, Set<String> matchedCategories) {
    final matchesAccount = accountIds.isEmpty ||
        accountIds.contains(item.accountId) ||
        (item.type == TransactionType.transfer &&
            accountIds.contains(item.toAccountId));
    final matchesType = types.isEmpty || types.contains(item.type);
    final matchesCategory = categoryIds.isEmpty ||
        (item.categoryId != null &&
            matchedCategories.contains(item.categoryId));
    return matchesAccount && matchesType && matchesCategory;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TransactionFilters &&
          setEquals(accountIds, other.accountIds) &&
          setEquals(types, other.types) &&
          setEquals(categoryIds, other.categoryIds);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(accountIds),
        Object.hashAllUnordered(types),
        Object.hashAllUnordered(categoryIds),
      );
}

bool _allowsCategory(Set<TransactionType> types, Category category) =>
    types.isEmpty ||
    types.any((type) => allowedCategoryTypes(type).contains(category.type));

class _TransactionFilterSheet extends StatefulWidget {
  const _TransactionFilterSheet({
    required this.title,
    required this.dimensions,
    required this.initial,
    required this.accounts,
    required this.categories,
    required this.categoryPath,
  });

  final String title;
  final Set<_FilterDimension> dimensions;
  final _TransactionFilters initial;
  final Map<String, String> accounts;
  final List<Category> categories;
  final List<Category> Function(String) categoryPath;

  @override
  State<_TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<_TransactionFilterSheet> {
  late final Set<String> accountIds = {...widget.initial.accountIds};
  late final Set<TransactionType> types = {...widget.initial.types};
  late final Set<String> categoryIds = {...widget.initial.categoryIds};

  @override
  void didUpdateWidget(_TransactionFilterSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    accountIds.retainWhere(widget.accounts.containsKey);
    _pruneCategories();
  }

  void _pruneCategories() {
    final allowed = widget.categories
        .where((c) => _allowsCategory(types, c))
        .map((c) => c.id)
        .toSet();
    categoryIds.retainWhere(allowed.contains);
  }

  void _clearVisibleDimensions() {
    setState(() {
      if (widget.dimensions.contains(_FilterDimension.account)) {
        accountIds.clear();
      }
      if (widget.dimensions.contains(_FilterDimension.type)) types.clear();
      if (widget.dimensions.contains(_FilterDimension.category)) {
        categoryIds.clear();
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _TransactionFilters(
        accountIds: Set.unmodifiable(accountIds),
        types: Set.unmodifiable(types),
        categoryIds: Set.unmodifiable(categoryIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(widget.title, style: textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '同一项内满足任一选项即可，不同项需同时满足。未勾选表示全部。父类别包含下级类别。',
                style: textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (widget.dimensions.contains(_FilterDimension.account))
                    ..._section(
                      title: '账户',
                      keyPrefix: 'account',
                      options: widget.accounts,
                      selected: accountIds,
                      keyOf: (id) => id,
                    ),
                  if (widget.dimensions.contains(_FilterDimension.type))
                    ..._section(
                      title: '类型',
                      keyPrefix: 'type',
                      options: {
                        for (final type in TransactionType.values)
                          type: _typeName(type),
                      },
                      selected: types,
                      keyOf: (type) => type.name,
                      afterChange: _pruneCategories,
                    ),
                  if (widget.dimensions.contains(_FilterDimension.category))
                    ..._section(
                      title: '类别',
                      keyPrefix: 'category',
                      options: {
                        for (final category in widget.categories
                            .where((c) => _allowsCategory(types, c)))
                          category.id: [
                            widget
                                .categoryPath(category.id)
                                .map((c) => c.name)
                                .join(' › '),
                            if (category.isArchived) '已归档',
                          ].join(' · '),
                      },
                      selected: categoryIds,
                      keyOf: (id) => id,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    key: const Key('transaction-filter-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const Key('transaction-filter-clear'),
                    onPressed: _clearVisibleDimensions,
                    child: const Text('全部'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('transaction-filter-apply'),
                    onPressed: _apply,
                    child: const Text('应用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section<T>({
    required String title,
    required String keyPrefix,
    required Map<T, String> options,
    required Set<T> selected,
    required String Function(T value) keyOf,
    VoidCallback? afterChange,
  }) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Text(
          selected.isEmpty ? '$title · 全部' : '$title · 已选 ${selected.length}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      if (options.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Text('暂无可选项'),
        ),
      for (final entry in options.entries)
        CheckboxListTile(
          key: Key('transaction-filter-option-$keyPrefix-${keyOf(entry.key)}'),
          value: selected.contains(entry.key),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(entry.value),
          onChanged: (checked) => setState(() {
            if (checked == true) {
              selected.add(entry.key);
            } else {
              selected.remove(entry.key);
            }
            afterChange?.call();
          }),
        ),
    ];
  }
}

class _BasisSummary {
  const _BasisSummary({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.primaryLabel,
    required this.primary,
    required this.secondaryLabel,
    required this.secondary,
    required this.icon,
    this.valueIsOutflow = false,
  });

  final String title;
  final String subtitle;
  final double value;
  final String primaryLabel;
  final double primary;
  final String secondaryLabel;
  final double secondary;
  final IconData icon;
  final bool valueIsOutflow;
}

class _BasisCards extends StatelessWidget {
  const _BasisCards({
    required this.summaries,
    required this.selected,
    required this.onSelected,
    required this.desktop,
    required this.currency,
  });

  final Map<_TransactionBasis, _BasisSummary> summaries;
  final _TransactionBasis selected;
  final ValueChanged<_TransactionBasis> onSelected;
  final bool desktop;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cards = Row(
      crossAxisAlignment:
          desktop ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
      children: [
        for (final basis in _TransactionBasis.values) ...[
          Expanded(
            flex: desktop ? 1 : (basis == selected ? 18 : 11),
            child: _BasisCard(
              key: Key('basis-card-${basis.name}'),
              summary: summaries[basis]!,
              selected: basis == selected,
              desktop: desktop,
              currency: currency,
              onTap: () => onSelected(basis),
            ),
          ),
          if (basis != _TransactionBasis.committed)
            SizedBox(width: desktop ? 12 : 7),
        ],
      ],
    );
    if (desktop) return cards;

    return Column(
      children: [
        SizedBox(height: 118, child: cards),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _TransactionBasis.values
              .map(
                (basis) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: basis == selected ? 18 : 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: basis == selected
                        ? financePaletteOf(context).seed
                        : financePaletteOf(context).border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _BasisCard extends StatelessWidget {
  const _BasisCard({
    super.key,
    required this.summary,
    required this.selected,
    required this.onTap,
    required this.desktop,
    required this.currency,
  });

  final _BasisSummary summary;
  final bool selected;
  final VoidCallback onTap;
  final bool desktop;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final valueColor = summary.valueIsOutflow || summary.value < 0
        ? palette.expense
        : (summary.title == '实际消费' && summary.value > 0
            ? palette.income
            : palette.textPrimary);
    final glass = palette.glassHighlightColor != null;
    final radius = BorderRadius.circular(14);
    final card = Material(
      color: glass
          ? Colors.white.withValues(alpha: selected ? .74 : .40)
          : (selected ? palette.resolvedCardSurface : palette.surfaceAlt),
      elevation: selected && palette.monochrome ? 1.5 : 0,
      shadowColor: palette.cardShadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected
              ? (palette.monochrome
                  ? palette.seed
                  : palette.seed.withValues(alpha: glass ? .55 : .8))
              : (glass ? Colors.white.withValues(alpha: .7) : palette.border),
          width: selected && palette.monochrome ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 14 : (selected ? 12 : 8),
            vertical: desktop ? 12 : 10,
          ),
          child: Column(
            mainAxisSize: desktop ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    summary.icon,
                    size: desktop || selected ? 18 : 16,
                    color: selected ? palette.seed : palette.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: desktop || selected ? 13 : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (desktop) const SizedBox(height: 9) else const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  compassMoney(summary.value, currency: currency, decimals: 0),
                  key: selected
                      ? const Key('transaction-basis-selected-value')
                      : null,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: desktop || selected ? 23 : 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: compassTabularFigures,
                    height: 1,
                  ),
                ),
              ),
              if (desktop || selected) ...[
                const SizedBox(height: 7),
                Text(
                  summary.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: desktop ? 12 : 9.5,
                        color: palette.textMuted,
                      ),
                ),
              ] else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    return compassGlassHighlight(
      color: palette.glassHighlightColor,
      borderRadius: radius,
      intensity: selected ? 1 : .45,
      child: card,
    );
  }
}

class _FlowLegend extends StatelessWidget {
  const _FlowLegend({
    super.key,
    required this.color,
    required this.label,
    this.compact = false,
  });

  final Color color;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFeatures: compassTabularFigures,
          ),
    );
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        if (compact)
          Flexible(child: text)
        else
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: text,
            ),
          ),
      ],
    );
  }
}

class _StatusSwitch extends StatelessWidget {
  const _StatusSwitch({
    required this.includePlanned,
    required this.onChanged,
  });

  final bool includePlanned;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final glass = palette.glassHighlightColor != null;
    final track = Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: glass ? Colors.white.withValues(alpha: .46) : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: glass ? Colors.white.withValues(alpha: .78) : palette.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatusButton(
              label: '已发生',
              selected: !includePlanned,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _StatusButton(
              label: '包含预计',
              selected: includePlanned,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
    return compassGlassHighlight(
      color: palette.glassHighlightColor,
      borderRadius: BorderRadius.circular(18),
      intensity: .5,
      child: track,
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final glassLens = selected && palette.glassHighlightColor != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: glassLens
              ? null
              : (selected
                  ? palette.seed.withValues(alpha: .18)
                  : Colors.transparent),
          // Liquid Glass: raised white-ice lens like the dock's active pill.
          gradient: glassLens
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: .96),
                    const Color(0xFFDDF0FF).withValues(alpha: .86),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(15),
          boxShadow: glassLens && !compassIsCpuSoftwareWeb
              ? [
                  BoxShadow(
                    color: palette.seed.withValues(alpha: .16),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.seed : null,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QuickFilterPill extends StatelessWidget {
  const _QuickFilterPill({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        constraints: const BoxConstraints(maxWidth: 124),
        margin: const EdgeInsets.only(right: 7),
        child: Material(
          color: selected
              ? financePaletteOf(context).seed.withValues(alpha: .12)
              : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? financePaletteOf(context).seed
                  : financePaletteOf(context).border,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: financePaletteOf(context).seed,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? financePaletteOf(context).seed : null,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DesktopLedgerHeader extends StatelessWidget {
  const _DesktopLedgerHeader();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: financePaletteOf(context).surfaceAlt,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(
            bottom: BorderSide(color: financePaletteOf(context).border),
          ),
        ),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
              ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: _DesktopLedgerCells(
              date: Text('日期'),
              details: Text('交易'),
              account: Text('账户'),
              category: Text('类别'),
              amount: Text('金额'),
              status: Text('状态'),
            ),
          ),
        ),
      );
}

class _DesktopLedgerCells extends StatelessWidget {
  const _DesktopLedgerCells({
    required this.date,
    required this.details,
    required this.account,
    required this.category,
    required this.amount,
    required this.status,
    this.action,
  });

  final Widget date;
  final Widget details;
  final Widget account;
  final Widget category;
  final Widget amount;
  final Widget status;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            SizedBox(width: 78, child: date),
            Expanded(flex: 8, child: details),
            const SizedBox(width: 14),
            Expanded(flex: 5, child: account),
            const SizedBox(width: 14),
            Expanded(flex: 3, child: category),
            const SizedBox(width: 14),
            Expanded(
              flex: 4,
              child: Align(alignment: Alignment.centerRight, child: amount),
            ),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: status),
            SizedBox(width: 44, child: Center(child: action)),
          ],
        ),
      );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    super.key,
    required this.item,
    required this.repository,
    this.onTap,
    this.onLongPress,
    this.onAction,
    this.selected = false,
    this.desktop = false,
  });

  final FinanceTransaction item;
  final FinanceRepository repository;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onAction;
  final bool selected;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final isExpense = item.type == TransactionType.expense;
    final isIncome = item.type == TransactionType.income;
    final isTransfer = item.type == TransactionType.transfer;
    final signedAmount = isExpense ? -item.amount : item.amount;
    final sign = moneyDisplayParts(signedAmount).sign;
    final showsDirectionalSign =
        isExpense || isIncome || item.type == TransactionType.adjustment;
    final color = switch (sign) {
      0 => palette.textPrimary,
      _ when isExpense || sign < 0 => palette.expense,
      _ when isIncome || item.type == TransactionType.adjustment => palette.income,
      _ => palette.textPrimary,
    };
    final categoryId = item.categoryId;
    final category = categoryId == null
        ? _typeName(item.type)
        : repository.categoryName(categoryId);
    final title =
        item.merchant ?? item.description ?? (isTransfer ? '账户转账' : category);
    final accountName = repository.accountName(item.accountId);
    final toAccountId = item.toAccountId;
    final mobileAccountLabel = toAccountId == null
        ? accountName
        : '$accountName → ${repository.accountName(toAccountId)}';
    final subtitle = title == category
        ? mobileAccountLabel
        : '$mobileAccountLabel · $category';
    final amount = Text(
      compassMoney(signedAmount, currency: item.currency, showPositiveSign: showsDirectionalSign),
      style: TextStyle(
        color: color,
        fontSize: desktop ? 14 : 13.5,
        fontWeight: FontWeight.w600,
        fontFeatures: compassTabularFigures,
      ),
    );
    final planned = item.status == TransactionStatus.planned;
    final plannedLabel = desktop
        ? Align(
            alignment: Alignment.centerLeft,
            child: CompassStatusBadge(label: '预计', color: palette.warning),
          )
        : CompassStatusBadge(label: '预计', color: palette.warning);
    final action = _rowAction(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: desktop
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? financePaletteOf(context).seed.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(
                  color: financePaletteOf(context).seed.withValues(alpha: .55),
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: desktop ? 6 : 7),
          child: desktop
              ? _DesktopLedgerCells(
                  date: _secondaryCell(
                    context,
                    '${item.transactionDate.month}月${item.transactionDate.day}日',
                  ),
                  details: _details(
                    context,
                    color: color,
                    title: title,
                    subtitle:
                        title == item.description ? null : item.description,
                  ),
                  account: _secondaryCell(
                    context,
                    toAccountId == null
                        ? accountName
                        : '$accountName → ${repository.accountName(toAccountId)}',
                  ),
                  category: _secondaryCell(context, category),
                  amount: FittedBox(fit: BoxFit.scaleDown, child: amount),
                  status:
                      planned ? plannedLabel : _secondaryCell(context, '已发生'),
                  action: action,
                )
              : Row(
                  children: [
                    Expanded(
                      child: _details(
                        context,
                        color: color,
                        title: title,
                        subtitle: subtitle,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        amount,
                        if (planned) ...[
                          const SizedBox(height: 3),
                          plannedLabel,
                        ],
                      ],
                    ),
                    if (action != null) ...[
                      SizedBox(width: selected ? 7 : 2),
                      action,
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _secondaryCell(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );

  Widget _details(
    BuildContext context, {
    required Color color,
    required String title,
    required String? subtitle,
  }) =>
      Row(
        children: [
          CompassIconBadge(icon: _typeIcon(item.type), color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  Widget? _rowAction(BuildContext context) {
    if (selected) {
      return Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: financePaletteOf(context).seed,
      );
    }
    final onAction = this.onAction;
    if (onAction == null) return null;
    return SizedBox.square(
      dimension: desktop ? 44 : 32,
      child: FinanceActionMenuButton<String>(
        tooltip: '交易操作',
        iconSize: 19,
        onSelected: onAction,
        items: const [
          FinanceActionMenuItem(
            value: 'edit',
            label: '编辑',
            icon: Icons.edit_outlined,
          ),
          FinanceActionMenuItem(
            value: 'reuse',
            label: '复用新增',
            icon: Icons.copy_outlined,
          ),
          FinanceActionMenuItem(
            value: 'template',
            label: '保存模板',
            icon: Icons.bolt_outlined,
          ),
          FinanceActionMenuItem(
            value: 'recurring',
            label: '保存周期',
            icon: Icons.repeat_rounded,
          ),
          FinanceActionMenuItem(
            value: 'delete',
            label: '删除',
            icon: Icons.delete_outline,
            destructive: true,
            dividerBefore: true,
          ),
        ],
      ),
    );
  }
}

class _TransactionSearchPage extends ConsumerStatefulWidget {
  const _TransactionSearchPage({
    required this.repository,
    required this.onAction,
    required this.onDelete,
  });

  final FinanceRepository repository;
  final Future<void> Function(BuildContext, String, FinanceTransaction)
      onAction;
  final Future<bool> Function(BuildContext, List<String>) onDelete;

  @override
  ConsumerState<_TransactionSearchPage> createState() =>
      _TransactionSearchPageState();
}

class _TransactionSearchPageState
    extends ConsumerState<_TransactionSearchPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _selected = <String>{};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _queryChanged() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(_selected.clear);
  }

  void _toggle(String id) {
    _focus.unfocus();
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _delete(List<String> ids) async {
    if (_deleting || ids.isEmpty) return;
    _focus.unfocus();
    setState(() => _deleting = true);
    try {
      final deleted = await widget.onDelete(context, ids);
      if (deleted && mounted) _selected.clear();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _act(String value, FinanceTransaction item) {
    _focus.unfocus();
    if (value == 'delete') {
      _delete([item.id]);
    } else {
      widget.onAction(context, value, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final sameLedger =
        identical(repository.database, widget.repository.database);
    final needle = _input.text.trim().toLowerCase();
    final matches = sameLedger
        ? repository.transactions
            .where((item) {
              if (needle.isEmpty) return true;
              return [
                item.merchant,
                item.description,
                repository.accountName(item.accountId),
                if (item.categoryId != null)
                  repository.categoryName(item.categoryId!),
              ]
                  .whereType<String>()
                  .any((value) => value.toLowerCase().contains(needle));
            })
            .take(50)
            .toList()
        : const <FinanceTransaction>[];
    final visibleIds = matches.map((item) => item.id).toSet();
    _selected.retainAll(visibleIds);
    final selecting = _selected.isNotEmpty;

    return PopScope<void>(
      canPop: !selecting && !_deleting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting && !_deleting) setState(_selected.clear);
      },
      child: Scaffold(
        key: const Key('transaction-search-page'),
        appBar: AppBar(
          leading: IconButton(
            tooltip: selecting
                ? '退出选择'
                : MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(
                selecting ? Icons.close_rounded : Icons.arrow_back_rounded),
            onPressed:
                _deleting ? null : () => Navigator.of(context).maybePop(),
          ),
          title: selecting
              ? Text('已选择 ${_selected.length} 笔')
              : TextField(
                  key: const Key('transaction-search-input'),
                  controller: _input,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                      hintText: '搜索交易', border: InputBorder.none),
                  onChanged: (_) => _queryChanged(),
                  onSubmitted: (_) => _focus.unfocus(),
                ),
          actions: [
            if (selecting) ...[
              IconButton(
                tooltip: '选择当前搜索结果',
                icon: const Icon(Icons.select_all_rounded),
                onPressed: _deleting
                    ? null
                    : () => setState(() => _selected.addAll(visibleIds)),
              ),
              IconButton(
                tooltip: '删除所选交易',
                color: financePaletteOf(context).expense,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _deleting
                    ? null
                    : () => _delete(_selected.toList(growable: false)),
              ),
            ] else
              IconButton(
                tooltip: '清空搜索',
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _input.clear();
                  _queryChanged();
                  _focus.requestFocus();
                },
              ),
          ],
        ),
        body: matches.isEmpty
            ? Center(child: Text(sameLedger ? '没有匹配的交易' : '账本已切换，请返回后重新搜索。'))
            : ListView.builder(
                key: const Key('transaction-search-results'),
                controller: _scroll,
                padding: compassPagePadding,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final item = matches[index];
                  return _TransactionRow(
                    key: ValueKey(item.id),
                    item: item,
                    repository: repository,
                    selected: _selected.contains(item.id),
                    onTap: _deleting
                        ? null
                        : () =>
                            selecting ? _toggle(item.id) : _act('edit', item),
                    onLongPress: _deleting ? null : () => _toggle(item.id),
                    onAction: _deleting || selecting
                        ? null
                        : (value) => _act(value, item),
                  );
                },
              ),
      ),
    );
  }
}

class _RecurringRuleDraft {
  const _RecurringRuleDraft({
    required this.name,
    required this.intervalMonths,
  });

  final String name;
  final int intervalMonths;
}

String _typeName(TransactionType type) => switch (type) {
      TransactionType.income => '收入',
      TransactionType.expense => '支出',
      TransactionType.transfer => '转账',
      TransactionType.adjustment => '调整',
    };

IconData _typeIcon(TransactionType type) => switch (type) {
      TransactionType.income => Icons.south_west_rounded,
      TransactionType.expense => Icons.shopping_bag_outlined,
      TransactionType.transfer => Icons.swap_horiz_rounded,
      TransactionType.adjustment => Icons.tune_rounded,
    };
