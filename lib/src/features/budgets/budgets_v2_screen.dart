import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared/category_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/budget.dart';
import '../../core/models/category.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/budget_mutations.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_amount_field.dart';
import '../shared/finance_donut.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';
import 'budget_rule_ui.dart';

class BudgetsV2Screen extends ConsumerStatefulWidget {
  const BudgetsV2Screen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<BudgetsV2Screen> createState() => _BudgetsV2ScreenState();
}

class _BudgetsV2ScreenState extends ConsumerState<BudgetsV2Screen> {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final month = monthKeyFromDate(selectedMonth);
    final rows = _budgetRows(repository, month);
    final monthValued = repository.budgetMonthIsValued(month);
    final total = rows.fold<double>(0, (sum, row) => sum + row.budget);
    final allocationTotal = rows.where((row) => row.hasAllocation).fold(
          0.0,
          (sum, row) => sum + row.budget,
        );
    final used = rows.fold<double>(0, (sum, row) => sum + row.actual);
    final planned = rows.fold<double>(0, (sum, row) => sum + row.planned);
    final rollover = rows.fold<double>(0, (sum, row) => sum + row.rollover);
    final textTheme = Theme.of(context).textTheme;
    final mono = financePaletteOf(context).monochrome;
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;
    final daysInMonth =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
    final daysRemaining = isCurrentMonth ? (daysInMonth - now.day + 1) : null;
    final remaining = total + rollover - used - planned;
    final monthControls = [
      IconButton(
        tooltip: '上个月',
        onPressed: () => _changeMonth(-1),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Text(
        '${selectedMonth.year}年${selectedMonth.month}月',
        style: textTheme.titleMedium,
      ),
      IconButton(
        tooltip: '下个月',
        onPressed: () => _changeMonth(1),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
      if (!isCurrentMonth)
        TextButton(
          key: const Key('budget-month-today'),
          onPressed: () => setState(
            () => selectedMonth = DateTime(now.year, now.month),
          ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('本月'),
        ),
    ];
    void openEditor() => _openEditor(context, repository);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= compassDesktopMinWidth;
        final allocation = FinanceDonutPanel(
          title: '预算分配',
          totalLabel: rows.every(
                  (row) => repository.hasExchangeRate(row.source.currency))
              ? '已分配'
              : '已估值分配',
          totalValue: compassMoney(
            total,
            currency: repository.baseCurrency,
            decimals: _budgetDecimals(total),
          ),
          slices: _budgetAllocationSlices(context, rows),
          formatLegendAmount: desktop && mono
              ? (value) => compassMoney(value,
                  decimals: _budgetDecimals(value), showCurrency: false)
              : null,
          footer: desktop
              ? _BudgetUsageSummary(
                  actual: rows.every((r) => r.actualValued) ? used : null,
                  planned: rows.every((r) => r.plannedValued) ? planned : null,
                  remaining: monthValued ? remaining : null,
                  totalAvailable: total + rollover,
                  baseCurrency: repository.baseCurrency,
                  daysRemaining: daysRemaining,
                )
              : Text(
                  !monthValued
                      ? '剩余 未估值'
                      : '${remaining < 0 ? '超出' : '剩余'} '
                          '${compassMoney(remaining.abs(), currency: repository.baseCurrency, decimals: _budgetDecimals(remaining))}',
                  key: const Key('budget-mobile-total-remaining'),
                  style: const TextStyle(fontFeatures: compassTabularFigures),
                ),
        );
        final details = [
          Row(
            children: [
              Expanded(
                flex: 6,
                child: Semantics(
                  container: true,
                  header: true,
                  child: Text('预算明细', style: textTheme.titleMedium),
                ),
              ),
              if (desktop) const SizedBox(width: 48),
              const Expanded(flex: 2, child: _BudgetColumnLabel('占比')),
              if (desktop) ...[
                Expanded(
                  flex: 5,
                  child: _BudgetSpendColumns(
                    actual: const _BudgetColumnLabel(
                      '实际支出',
                      alignment: Alignment.centerRight,
                    ),
                    planned: const _BudgetColumnLabel(
                      '预计支出',
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: _BudgetColumnLabel('结转'),
                ),
              ],
              Expanded(
                flex: desktop ? 3 : 4,
                child: const _BudgetColumnLabel(
                  '剩余',
                  alignment: Alignment.centerRight,
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
          const SizedBox(height: 8),
          compassHairline,
          if (rows.isEmpty)
            if (desktop)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('本月还没有预算')),
              )
            else
              const CompassCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('本月还没有预算')),
                ),
              ),
          for (final row in rows)
            Column(
              children: [
                _BudgetRow(
                  row: row,
                  allocationTotal: allocationTotal,
                  desktop: desktop,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BudgetCategoryDetailPage(
                        repository: repository,
                        categoryId: row.source.categoryId,
                        monthKey: month,
                      ),
                    ),
                  ),
                ),
                compassHairline,
              ],
            ),
        ];
        return ListView(
          padding: compassScrollPadding(
            context,
            desktop ? compassDesktopPagePadding : compassPagePadding,
          ),
          children: [
            Row(
              children: [
                Text('预算', style: textTheme.headlineSmall),
                if (!desktop) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: monthControls,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ] else ...[
                  const Spacer(),
                  ...monthControls,
                ],
                if (desktop) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: openEditor,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('调整预算'),
                  ),
                ] else ...[
                  if (mono)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: openEditor,
                      child: const Text('调整'),
                    )
                  else
                    TextButton(onPressed: openEditor, child: const Text('调整')),
                ],
              ],
            ),
            const SizedBox(height: 18),
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width:
                        (constraints.maxWidth * .28).clamp(320, 360).toDouble(),
                    child: allocation,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: CompassCard(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      radius: 14,
                      child: Column(children: details),
                    ),
                  ),
                ],
              )
            else ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: allocation,
                ),
              ),
              const SizedBox(height: 28),
              ...details,
            ],
          ],
        );
      },
    );
  }

  void _changeMonth(int offset) => setState(() {
        selectedMonth =
            DateTime(selectedMonth.year, selectedMonth.month + offset);
      });

  Future<void> _openEditor(
    BuildContext context,
    FinanceRepository repository,
  ) async {
    await _showBudgetEditor(
        context, repository, monthKeyFromDate(selectedMonth));
  }
}

class BudgetCategoryDetailPage extends ConsumerStatefulWidget {
  const BudgetCategoryDetailPage({
    super.key,
    required this.repository,
    required this.categoryId,
    required this.monthKey,
  });

  final FinanceRepository repository;
  final String categoryId;
  final String monthKey;

  @override
  ConsumerState<BudgetCategoryDetailPage> createState() =>
      _BudgetCategoryDetailPageState();
}

class _BudgetCategoryDetailPageState
    extends ConsumerState<BudgetCategoryDetailPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final liveRepository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final palette = financePaletteOf(context);
    final liveRows = _budgetRows(liveRepository, widget.monthKey);
    final row = liveRows
        .where((item) => item.source.categoryId == widget.categoryId)
        .firstOrNull;
    if (row == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('当前月份没有此类别的预算')));
    }
    final effective = row.budget + row.rollover;
    final remaining = effective - row.actual - row.planned;
    final threshold = row.source.alertThreshold;
    final actualRatio =
        effective > 0 ? row.actual / effective : (row.actual > 0 ? 1.0 : 0.0);
    final plannedRatio = effective > 0 ? row.planned / effective : 0.0;
    final statusColor = remaining < 0
        ? palette.expense
        : (actualRatio + plannedRatio) >= threshold
            ? palette.warning
            : palette.income;
    final transactions = liveRepository
        .budgetUsageFor(widget.categoryId, widget.monthKey)
        .transactions
        .where((item) {
      if (selected == 1) return item.status != TransactionStatus.planned;
      if (selected == 2) return item.status == TransactionStatus.planned;
      return true;
    });
    final sidePadding =
        math.max(20.0, (MediaQuery.sizeOf(context).width - 760) / 2);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: compassScrollPadding(
              context,
              EdgeInsets.fromLTRB(sidePadding, 12, sidePadding, 32),
            ),
            children: [
              Row(
                children: [
                  const CompassBackButton(),
                  const Spacer(),
                  Icon(row.icon, color: palette.seed),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      row.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _edit(liveRepository, row),
                    child: const Text('编辑预算'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!row.isValued)
                Text(
                    '基础预算 ${compassMoney(row.source.amount, currency: row.source.currency)} · 未估值')
              else ...[
                CompassCard(
                  child: Column(
                    children: [
                      Text(
                        _monthLabel(widget.monthKey),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        remaining < 0 ? '本月超支' : '本月剩余',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        compassMoney(
                          remaining.abs(),
                          currency: liveRepository.baseCurrency,
                          decimals: _budgetDecimals(remaining),
                        ),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          fontFeatures: compassTabularFigures,
                        ),
                      ),
                      const SizedBox(height: 4),
                      CompassHelpHeading(
                        title: Text(
                          '有效预算  ${compassMoney(effective, currency: liveRepository.baseCurrency, decimals: _budgetDecimals(effective))}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFeatures: compassTabularFigures,
                                  ),
                        ),
                        label: '预算使用进度',
                        message:
                            '有效预算等于基础预算加上结转金额。父预算包含未单设预算的子类别；单设预算的子类别独立计算。实色和斜纹分别表示实际与预计支出。',
                      ),
                      const SizedBox(height: 4),
                      CompassDualProgressBar(
                        actualRatio: actualRatio,
                        plannedRatio: plannedRatio,
                        alertThreshold: threshold,
                        height: 10,
                        semanticsLabel: '${row.name} 预算使用进度',
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            '实际 ${compassMoney(row.actual, currency: liveRepository.baseCurrency, decimals: _budgetDecimals(row.actual))}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontFeatures: compassTabularFigures,
                                    ),
                          ),
                          Text(
                            '预计 ${compassMoney(row.planned, currency: liveRepository.baseCurrency, decimals: _budgetDecimals(row.planned))}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontFeatures: compassTabularFigures,
                                    ),
                          ),
                          Text(
                            '警戒线 ${(threshold * 100).round()}%',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontFeatures: compassTabularFigures,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CompassCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text('预算构成',
                              style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          CompassStatusBadge(
                            label:
                                row.source.rolloverEnabled ? '结转已开启' : '结转未开启',
                            color: row.source.rolloverEnabled
                                ? palette.income
                                : palette.textMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _AmountLine(
                        label: '基础预算',
                        amount: row.budget,
                        currency: liveRepository.baseCurrency,
                      ),
                      _AmountLine(
                        label: '上月结转',
                        amount: row.rollover,
                        currency: liveRepository.baseCurrency,
                        positive: row.rollover >= 0,
                      ),
                      compassHairline,
                      _AmountLine(
                        label: '有效预算',
                        amount: effective,
                        currency: liveRepository.baseCurrency,
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text('占用预算的交易', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              CompassSegmentedControl(
                labels: const ['全部', '实际', '预计'],
                selectedIndex: selected,
                onChanged: (value) => setState(() => selected = value),
              ),
              const SizedBox(height: 14),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text(
                      '没有符合条件的交易',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ...transactions.expand(
                (item) => [
                  _BudgetExpenseRow(
                    date:
                        '${item.transactionDate.month}月${item.transactionDate.day}日',
                    title: item.merchant ?? item.description ?? '支出',
                    account: liveRepository.accountName(item.accountId),
                    amount: item.amount,
                    currency: item.currency,
                    isPlanned: item.status == TransactionStatus.planned,
                    onTap: () => _editTransaction(liveRepository, item),
                  ),
                  compassHairline,
                ],
              ),
              const SizedBox(height: 14),
              CompassPrimaryButton(
                label: '删除预算',
                icon: Icons.delete_outline_rounded,
                outlined: true,
                color: palette.expense,
                onPressed: () => _delete(liveRepository, row.source),
              ),
            ],
          ),
        ),
      ),
    );
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
      return;
    }
    if (result.transactions.length == 1) {
      await mutations.updateTransaction(result.transactions.single);
    }
  }

  Future<void> _edit(
    FinanceRepository repository,
    _BudgetPresentation row,
  ) async {
    final result = await _showBudgetEditor(context, repository, widget.monthKey,
        source: row.source);
    if (result != null && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(FinanceRepository repository, Budget budget) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除源预算规则？'),
            content: Text(
                budgetRuleDeletionMessage(repository, budget, widget.monthKey)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除源规则'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await ref.read(budgetMutationsProvider.notifier).deleteBudget(budget.id);
    if (mounted) Navigator.of(context).pop();
  }
}

Future<Budget?> _showBudgetEditor(
        BuildContext context, FinanceRepository repository, String monthKey,
        {Budget? source}) =>
    Navigator.push<Budget>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => liveBudgetEditor(
              repository,
              source,
              (live, persist) => BudgetEditorPage(
                  repository: live,
                  initialBudget: source,
                  monthKey: monthKey,
                  persist: persist)),
        ));

class BudgetEditorPage extends StatefulWidget {
  const BudgetEditorPage({
    super.key,
    required this.repository,
    this.initialBudget,
    this.persist,
    required this.monthKey,
  });

  final FinanceRepository repository;
  final Budget? initialBudget;
  final Future<void> Function(Budget)? persist;
  final String monthKey;

  @override
  State<BudgetEditorPage> createState() => _BudgetEditorPageState();
}

class _BudgetEditorPageState extends State<BudgetEditorPage> {
  late final TextEditingController amountController;
  late double threshold;
  late bool rollover;
  late String? categoryId;
  late String effectiveMonthKey;
  late final String newRuleId = buildId('budget');
  late final String currency;
  bool saving = false;
  String? get originalCategoryId =>
      effectiveMonthKey == widget.initialBudget?.monthKey
          ? widget.initialBudget?.categoryId
          : null;
  List<Category> get categoryOptions =>
      widget.repository.categoryOptions(CategoryType.expense,
          originalCategoryId: originalCategoryId);

  Budget? get draft {
    final id = categoryId;
    final amount = double.tryParse(amountController.text.trim());
    if (id == null ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        !categoryOptions.any((c) => c.id == id)) {
      return null;
    }
    final initial = widget.initialBudget;
    final sameRule = initial != null &&
        id == initial.categoryId &&
        effectiveMonthKey == initial.monthKey;
    return Budget(
        id: sameRule ? initial.id : newRuleId,
        categoryId: id,
        monthKey: effectiveMonthKey,
        amount: amount,
        currency: currency,
        alertThreshold: threshold,
        rolloverEnabled: rollover);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialBudget;
    currency = initial?.currency ?? widget.repository.baseCurrency;
    amountController =
        TextEditingController(text: initial?.amount.toString() ?? '');
    threshold = initial?.alertThreshold ?? .8;
    rollover = initial?.rolloverEnabled ?? true;
    effectiveMonthKey = widget.monthKey;
    categoryId = initial == null
        ? categoryOptions.firstOrNull?.id
        : categoryOptions
            .where((c) => c.id == initial.categoryId)
            .firstOrNull
            ?.id;
  }

  @override
  void didUpdateWidget(BudgetEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository &&
        !categoryOptions.any((c) => c.id == categoryId)) {
      categoryId = null;
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final budget = draft;
    final repository = widget.repository;
    final priced = repository.hasExchangeRate(currency);
    final preview = budget == null ? null : repository.previewBudget(budget);
    double inCurrency(double value) =>
        repository.convertFromBase(value, currency);
    final entered = double.tryParse(amountController.text.trim());
    final base = entered != null && entered.isFinite ? entered : 0.0;
    String displayAmount(double value, bool valued) => priced && valued
        ? compassMoney(inCurrency(value), currency: currency)
        : '未估值';
    final categoryName = categoryId == null
        ? '请选择'
        : budgetCategoryLabel(repository, categoryId!);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  const CompassBackButton(),
                  Expanded(
                    child: Text(
                      '${widget.initialBudget == null ? '新增' : '编辑'}$categoryName预算',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: Column(
                  children: [
                    Text(
                      '${compassMoney(base, currency: currency)}  +  结转 ${preview == null ? '—' : displayAmount(preview.carried, preview.carriedValued)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    Text('有效预算', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(
                      preview == null
                          ? '—'
                          : displayAmount(
                              preview.effective, preview.effectiveValued),
                      key: const Key('budget-editor-effective'),
                      style: TextStyle(
                        color: financePaletteOf(context).seed,
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_monthLabel(effectiveMonthKey),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (preview != null && widget.initialBudget != null) ...[
                const SizedBox(height: 16),
                _BudgetUsageSummary(
                  actual: priced && preview.actualValued
                      ? inCurrency(preview.actual)
                      : null,
                  planned: priced && preview.plannedValued
                      ? inCurrency(preview.planned)
                      : null,
                  remaining: priced &&
                          preview.effectiveValued &&
                          preview.actualValued &&
                          preview.plannedValued
                      ? inCurrency(
                          preview.effective - preview.actual - preview.planned)
                      : null,
                  baseCurrency: currency,
                ),
              ],
              const SizedBox(height: 26),
              _BudgetEditorRow(
                icon: Icons.shield_outlined,
                title: '支出类别',
                value: categoryName,
                onTap: _pickCategory,
              ),
              _BudgetEditorInputRow(
                icon: Icons.account_balance_wallet_outlined,
                title: '基础预算',
                currency: currency,
                controller: amountController,
                onChanged: (_) => setState(() {}),
              ),
              _BudgetEditorRow(
                icon: Icons.calendar_month_outlined,
                title: '生效月份',
                value: _monthLabel(effectiveMonthKey),
                onTap: _pickMonth,
                help: '从该月起持续生效，直到同一类别设置新的月份预算。',
              ),
              _BudgetEditorRow(
                icon: Icons.notifications_none_rounded,
                title: '提醒阈值',
                value: '${(threshold * 100).round()}%',
                onTap: _pickThreshold,
              ),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.refresh_rounded,
                        color: financePaletteOf(context).seed,
                      ),
                      title: const Text('结转规则'),
                      value: rollover,
                      onChanged: (value) => setState(() => rollover = value),
                    ),
                  ),
                  const CompassHelpButton(
                    title: '结转规则',
                    message: '未用完的预算会加到下个月。超支的金额会扣减下个月的预算。',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: preview == null
                    ? null
                    : () => _showNextMonthPreview(
                          displayAmount(
                              preview.nextBaseAmount, preview.nextBaseValued),
                          displayAmount(
                              preview.nextCarried, preview.nextCarriedValued),
                          displayAmount(preview.nextEffective,
                              preview.nextEffectiveValued),
                        ),
                icon: const Icon(Icons.trending_up_rounded),
                label: const Text('预览下月预算'),
              ),
              const SizedBox(height: 28),
              CompassPrimaryButton(
                label: '保存更改',
                onPressed: saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (saving) return;
    final budget = draft;
    if (budget == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择支出类别并输入大于 0 的有效预算。')),
      );
      return;
    }
    setState(() => saving = true);
    await saveBudgetDraft(context, budget, widget.persist);
    if (mounted) setState(() => saving = false);
  }

  Future<void> _pickCategory() async {
    final categories = categoryOptions;
    final selected = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择支出类别', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ...categories.map(
              (category) => ListTile(
                title:
                    Text(budgetCategoryLabel(widget.repository, category.id)),
                subtitle: category.isArchived ? const Text('已归档') : null,
                trailing: category.id == categoryId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, category),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => categoryId =
          categoryOptions.any((c) => c.id == selected.id) ? selected.id : null);
    }
  }

  Future<void> _pickMonth() async {
    final current = _monthDateFromKey(effectiveMonthKey);
    final months = List.generate(
      25,
      (index) => DateTime(current.year, current.month + index - 12),
    );
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            CompassHelpHeading(
              title: Text('选择生效月份',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              label: '预算沿用',
              message: '新金额会从所选月份开始沿用。更早月份的预算记录会保留。',
            ),
            for (final month in months)
              ListTile(
                title: Text('${month.year}年${month.month}月'),
                trailing: monthKeyFromDate(month) == effectiveMonthKey
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, month),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        effectiveMonthKey = monthKeyFromDate(selected);
        if (!categoryOptions.any((c) => c.id == categoryId)) categoryId = null;
      });
    }
  }

  Future<void> _pickThreshold() async {
    const options = [0.7, 0.8, 0.9, 1.0];
    final selected = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择提醒阈值', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...options.map(
              (value) => ListTile(
                title: Text('达到 ${(value * 100).round()}% 时提醒'),
                trailing: (threshold - value).abs() < 0.01
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, value),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => threshold = selected);
    }
  }

  Future<void> _showNextMonthPreview(
      String base, String projectedCarry, String nextEffective) async {
    final month = _monthDateFromKey(effectiveMonthKey);
    final nextMonth = DateTime(month.year, month.month + 1);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: CompassHelpHeading(
          title: Text('${nextMonth.year}年${nextMonth.month}月预算预览'),
          label: '下月预算预览',
          message: '按当前实际与预计支出计算，月底前仍会随交易变化。',
        ),
        content: Text(
          '基础预算：$base\n预计结转：$projectedCarry\n预计可用：$nextEffective',
          style: const TextStyle(fontFeatures: compassTabularFigures),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _BudgetPresentation {
  const _BudgetPresentation({
    required this.name,
    required this.icon,
    required this.budget,
    required this.actual,
    required this.planned,
    required this.rollover,
    required this.source,
    required this.limitValued,
    required this.actualValued,
    required this.plannedValued,
  });

  final String name;
  final IconData icon;
  final double budget;
  final double actual;
  final double planned;
  final double rollover;
  final Budget source;
  final bool limitValued;
  final bool actualValued;
  final bool plannedValued;
  bool get isValued => limitValued && actualValued && plannedValued;

  bool get hasAllocation => budget.isFinite && budget > 0;
}

List<_BudgetPresentation> _budgetRows(
  FinanceRepository repository,
  String month,
) {
  final budgets = repository.activeBudgetsForMonth(month);
  return budgets.map((budget) {
    final name = budgetCategoryLabel(repository, budget.categoryId);
    final usage = repository.budgetUsageFor(budget.categoryId, month);
    final base = repository.budgetAmountInBase(budget);
    final effective = repository.effectiveBudgetForMonth(budget, month);
    return _BudgetPresentation(
      name: name,
      limitValued: repository.budgetLimitIsValued(budget.categoryId, month),
      actualValued: usage.actualValued,
      plannedValued: usage.plannedValued,
      icon: categoryIcon(repository.categoryHierarchy.byId[budget.categoryId]),
      budget: base,
      actual: usage.actual,
      planned: usage.planned,
      rollover: effective - base,
      source: budget,
    );
  }).toList();
}

List<FinanceDonutSlice> _budgetAllocationSlices(
  BuildContext context,
  List<_BudgetPresentation> rows,
) {
  final colors = financeDonutSeries(context);
  final allocations = rows.where((row) => row.hasAllocation).toList()
    ..sort((a, b) {
      final byAmount = b.budget.compareTo(a.budget);
      return byAmount == 0 ? a.name.compareTo(b.name) : byAmount;
    });
  final top = allocations.take(3);
  final other = allocations.skip(3).fold(0.0, (sum, row) => sum + row.budget);
  final otherLabel = top.any((row) => row.name == '其他') ? '其余分类' : '其他';
  return [
    for (final (index, row) in top.indexed)
      FinanceDonutSlice(
          label: row.name, value: row.budget, color: colors[index]),
    if (other > 0)
      FinanceDonutSlice(label: otherLabel, value: other, color: colors[3]),
  ];
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.row,
    required this.allocationTotal,
    required this.desktop,
    required this.onTap,
  });
  final _BudgetPresentation row;
  final double allocationTotal;
  final bool desktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    if (!row.isValued) {
      return ListTile(
        onTap: onTap,
        title: Text(row.name),
        subtitle: Text(
            compassMoney(row.source.amount, currency: row.source.currency)),
        trailing: const Text('未估值'),
      );
    }
    final effective = row.budget + row.rollover;
    final remaining = effective - row.actual - row.planned;
    final remainingAmount =
        remaining.abs().toStringAsFixed(_budgetDecimals(remaining));
    final share = row.hasAllocation && allocationTotal.isFinite
        ? row.budget / allocationTotal * 100
        : 0;
    final threshold = row.source.alertThreshold;
    final actualRatio =
        effective > 0 ? row.actual / effective : (row.actual > 0 ? 1.0 : 0.0);
    final plannedRatio = effective > 0 ? row.planned / effective : 0.0;
    final statusColor = remaining < 0
        ? palette.expense
        : (actualRatio + plannedRatio) >= threshold
            ? palette.warning
            : palette.income;
    final remainingColor = remaining < 0
        ? palette.expense
        : (actualRatio + plannedRatio) >= threshold
            ? palette.warning
            : (row.actual > 0 || row.planned > 0
                ? palette.income
                : palette.textPrimary);
    if (!desktop) {
      final textTheme = Theme.of(context).textTheme;
      final amount = compassMoney(remaining.abs(),
          decimals: _budgetDecimals(remaining), showCurrency: false);
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    CompassIconBadge(icon: row.icon, size: 36),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${share.toStringAsFixed(1)}%',
                    style: const TextStyle(fontFeatures: compassTabularFigures),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    remaining < 0 ? '超出 $amount' : amount,
                    semanticsLabel: remaining >= 0 ? '剩余 $amount' : null,
                    style: textTheme.titleSmall?.copyWith(
                      color: remainingColor,
                      fontFeatures: compassTabularFigures,
                    ),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CompassIconBadge(icon: row.icon, size: 40),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: _BudgetCategorySummary(
                name: row.name,
                budget: row.budget,
                actualRatio: actualRatio,
                plannedRatio: plannedRatio,
                alertThreshold: threshold,
                statusColor: statusColor,
              ),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${share.toStringAsFixed(1)}%',
                  style: const TextStyle(fontFeatures: compassTabularFigures),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: _BudgetSpendColumns(
                actual: _BudgetSpendValue(value: row.actual),
                planned: _BudgetSpendValue(
                  value: row.planned,
                  planned: true,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${row.rollover > 0 ? '+' : ''}${row.rollover.toStringAsFixed(_budgetDecimals(row.rollover))}',
                  style: TextStyle(
                    color: row.rollover > 0
                        ? palette.income
                        : row.rollover < 0
                            ? palette.expense
                            : palette.textMuted,
                    fontFeatures: compassTabularFigures,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: _BudgetRemainingCell(
                remaining: remaining,
                remainingAmount: remainingAmount,
                remainingColor: remainingColor,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _BudgetCategorySummary extends StatelessWidget {
  const _BudgetCategorySummary({
    required this.name,
    required this.budget,
    required this.actualRatio,
    required this.plannedRatio,
    required this.alertThreshold,
    required this.statusColor,
  });

  final String name;
  final double budget;
  final double actualRatio;
  final double plannedRatio;
  final double alertThreshold;
  final Color statusColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '预算 ${budget.toStringAsFixed(_budgetDecimals(budget))}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFeatures: compassTabularFigures,
                ),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CompassDualProgressBar(
              actualRatio: actualRatio,
              plannedRatio: plannedRatio,
              alertThreshold: alertThreshold,
              height: 5,
              actualColor: statusColor,
            ),
          ),
        ],
      );
}

class _BudgetRemainingCell extends StatelessWidget {
  const _BudgetRemainingCell({
    required this.remaining,
    required this.remainingAmount,
    required this.remainingColor,
  });

  final double remaining;
  final String remainingAmount;
  final Color remainingColor;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            remainingAmount,
            semanticsLabel: remaining >= 0 ? '剩余 $remainingAmount' : null,
            style: TextStyle(
              color: remainingColor,
              fontSize: 16,
              fontWeight: remaining < 0 ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: compassTabularFigures,
            ),
          ),
        ),
        if (remaining < 0)
          Text(
            '超出',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.expense,
                  fontWeight: FontWeight.w600,
                ),
          ),
      ],
    );
  }
}

class _BudgetSpendColumns extends StatelessWidget {
  const _BudgetSpendColumns({
    required this.actual,
    required this.planned,
  });

  final Widget actual;
  final Widget planned;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: actual),
          const SizedBox(width: 8),
          Expanded(child: planned),
        ],
      );
}

class _BudgetSpendValue extends StatelessWidget {
  const _BudgetSpendValue({
    required this.value,
    this.planned = false,
  });

  final double value;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final amount = value.toStringAsFixed(_budgetDecimals(value));
    return Semantics(
      label: '${planned ? '预计' : '实际'} $amount',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          amount,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontFeatures: compassTabularFigures),
        ),
      ),
    );
  }
}

class _BudgetColumnLabel extends StatelessWidget {
  const _BudgetColumnLabel(this.label, {this.alignment = Alignment.center});

  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _BudgetUsageSummary extends StatelessWidget {
  const _BudgetUsageSummary({
    required this.actual,
    required this.planned,
    this.remaining,
    this.totalAvailable,
    required this.baseCurrency,
    this.daysRemaining,
  });

  final double? actual;
  final double? planned;
  final double? remaining;
  final double? totalAvailable;
  final String baseCurrency;
  final int? daysRemaining;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    String amount(double? value) => value == null
        ? '未估值'
        : compassMoney(value,
            decimals: _budgetDecimals(value), showCurrency: false);

    final labels = [
      '已用 ${amount(actual)}',
      '预计 ${amount(planned)}',
      '剩余 ${amount(remaining)}',
    ];
    final available = totalAvailable ?? 0;
    final usedTotal =
        actual == null || planned == null ? null : actual! + planned!;
    final progressPct = available > 0 && usedTotal != null
        ? (usedTotal / available * 100).round()
        : null;
    final rem = remaining;
    String? guidance;
    Color guidanceColor = palette.textMuted;
    if (progressPct != null && rem != null) {
      if (rem < 0) {
        guidance =
            '总进度 $progressPct% · 已超支 ${compassMoney(rem.abs(), currency: baseCurrency, decimals: 0)}';
        guidanceColor = palette.expense;
      } else if (daysRemaining != null && daysRemaining! > 0) {
        final daily = rem / daysRemaining!;
        guidance =
            '总进度 $progressPct% · 剩 $daysRemaining 天 · 日均可用 ${compassMoney(daily, currency: baseCurrency, decimals: 0)}';
      } else {
        guidance = '总进度 $progressPct%';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labels.join(' · '),
          style: const TextStyle(
            fontSize: 12,
            fontFeatures: compassTabularFigures,
          ),
        ),
        if (guidance != null) ...[
          CompassHelpHeading(
            title: Text(
              guidance,
              style: TextStyle(
                fontSize: 11.5,
                color: guidanceColor,
                fontWeight:
                    rem != null && rem < 0 ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: compassTabularFigures,
              ),
            ),
            label: '预算进度',
            message: '总进度按实际和预计支出合计占有效预算的比例计算。日均可用金额等于剩余预算除以当月剩余天数，含今天。',
          ),
        ],
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amount,
    required this.currency,
    this.positive = false,
    this.emphasized = false,
  });
  final String label;
  final double amount;
  final String currency;
  final bool positive;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text(
              '${positive ? '+ ' : emphasized ? '= ' : ''}${compassMoney(amount, currency: currency, decimals: _budgetDecimals(amount))}',
              style: TextStyle(
                color: positive || emphasized
                    ? financePaletteOf(context).seed
                    : financePaletteOf(context).textMuted,
                fontFeatures: compassTabularFigures,
              ),
            ),
          ],
        ),
      );
}

class _BudgetExpenseRow extends StatelessWidget {
  const _BudgetExpenseRow({
    required this.date,
    required this.title,
    required this.account,
    required this.amount,
    required this.currency,
    this.isPlanned = false,
    this.onTap,
  });
  final String date;
  final String title;
  final String account;
  final double amount;
  final String currency;
  final bool isPlanned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const CompassIconBadge(icon: Icons.shield_outlined, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: Theme.of(context).textTheme.bodySmall),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(account, style: Theme.of(context).textTheme.bodySmall),
                    if (isPlanned)
                      CompassStatusBadge(label: '预计', color: palette.warning),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            compassMoney(-amount, currency: currency),
            style: TextStyle(
              color: amount < 0 ? palette.income : palette.expense,
              fontWeight: FontWeight.w600,
              fontFeatures: compassTabularFigures,
            ),
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

class _BudgetEditorRow extends StatelessWidget {
  const _BudgetEditorRow({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
    this.help,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final row = CompassSettingsRow(
      icon: icon,
      title: title,
      value: value,
      onTap: onTap,
    );
    final information = help;
    if (information == null) return row;
    return Row(
      children: [
        Expanded(child: row),
        CompassHelpButton(title: title, message: information),
      ],
    );
  }
}

class _BudgetEditorInputRow extends StatelessWidget {
  const _BudgetEditorInputRow({
    required this.icon,
    required this.title,
    required this.currency,
    required this.controller,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String currency;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: financePaletteOf(context).border),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Icon(icon, color: financePaletteOf(context).seed),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
            SizedBox(
              width: 140,
              child: FinanceAmountField(
                controller: controller,
                textAlign: TextAlign.right,
                onChanged: onChanged,
                decoration: InputDecoration(
                  prefixText: '$currency ',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      );
}

int _budgetDecimals(double amount) =>
    (amount - amount.roundToDouble()).abs() < 1e-9 ? 0 : 2;

String _monthLabel(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;
  return '${parts[0]}年${int.tryParse(parts[1]) ?? parts[1]}月';
}

DateTime _monthDateFromKey(String monthKey) {
  final parts = monthKey.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}
