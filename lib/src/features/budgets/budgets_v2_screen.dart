import 'dart:math' as math;

import 'package:flutter/material.dart';
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
    final allocation = FinanceDonutPanel(
      title: '预算分配',
      totalLabel: '已分配',
      totalValue: compassMoney(
        total,
        currency: repository.baseCurrency,
        decimals: 0,
      ),
      slices: _budgetAllocationSlices(context, rows),
      formatLegendAmount: mono
          ? (value) => compassMoney(value, decimals: 0, showCurrency: false)
          : null,
      footer: _BudgetUsageSummary(
        actual: used,
        planned: planned,
        remaining: total + rollover - used - planned,
        totalAvailable: total + rollover,
        baseCurrency: repository.baseCurrency,
        daysRemaining: daysRemaining,
      ),
    );
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
    void openEditor() => _openEditor(context, repository, null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= compassDesktopMinWidth;
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
              const SizedBox(width: 48),
              if (!mono || desktop) ...[
                const Expanded(
                  flex: 2,
                  child: _BudgetColumnLabel('占比'),
                ),
                Expanded(
                  flex: desktop ? 5 : 3,
                  child: _BudgetSpendColumns(
                    desktop: desktop,
                    actual: _BudgetColumnLabel(
                      desktop ? '实际支出' : '实际',
                      alignment: desktop
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                    ),
                    planned: _BudgetColumnLabel(
                      desktop ? '预计支出' : '预计',
                      alignment: desktop
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: _BudgetColumnLabel('结转'),
                ),
                const Expanded(
                  flex: 3,
                  child: _BudgetColumnLabel(
                    '剩余',
                    alignment: Alignment.centerRight,
                  ),
                ),
                const SizedBox(width: 20),
              ],
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
                        row: row,
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
    _BudgetPresentation? row,
  ) async {
    final result = await Navigator.push<Budget>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BudgetEditorPage(
          repository: repository,
          initialBudget: row?.source,
          presentation: row,
          monthKey: monthKeyFromDate(selectedMonth),
        ),
      ),
    );
    if (result != null) {
      await ref.read(budgetMutationsProvider.notifier).addBudget(result);
    }
  }
}

class BudgetCategoryDetailPage extends ConsumerStatefulWidget {
  const BudgetCategoryDetailPage({
    super.key,
    required this.repository,
    required this.row,
    required this.monthKey,
  });

  final FinanceRepository repository;
  final _BudgetPresentation row;
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
    final row = liveRows.cast<_BudgetPresentation?>().firstWhere(
          (item) =>
              item != null &&
              item.source?.categoryId == widget.row.source?.categoryId,
          orElse: () => widget.row,
        )!;
    final effective = row.budget + row.rollover;
    final remaining = effective - row.actual - row.planned;
    final threshold = row.source?.alertThreshold ?? .8;
    final actualRatio =
        effective > 0 ? row.actual / effective : (row.actual > 0 ? 1.0 : 0.0);
    final plannedRatio = effective > 0 ? row.planned / effective : 0.0;
    final statusColor = remaining < 0
        ? palette.expense
        : (actualRatio + plannedRatio) >= threshold
            ? palette.warning
            : palette.income;
    final transactions = liveRepository.transactions.where((item) {
      if (item.type != TransactionType.expense ||
          item.categoryId != row.source?.categoryId ||
          monthKeyFromDate(item.transactionDate) != widget.monthKey) {
        return false;
      }
      if (selected == 1) return item.status != TransactionStatus.planned;
      if (selected == 2) return item.status == TransactionStatus.planned;
      return true;
    }).toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
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
                        decimals: 0,
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
                        '有效预算  ${compassMoney(effective, currency: liveRepository.baseCurrency, decimals: 0)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFeatures: compassTabularFigures,
                            ),
                      ),
                      label: '预算使用进度',
                      message:
                          '有效预算等于基础预算加上结转金额。进度条以实色显示实际支出，以斜纹显示预计支出。标线表示提醒阈值。',
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
                          '实际 ${compassMoney(row.actual, currency: liveRepository.baseCurrency, decimals: 0)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFeatures: compassTabularFigures,
                                  ),
                        ),
                        Text(
                          '预计 ${compassMoney(row.planned, currency: liveRepository.baseCurrency, decimals: 0)}',
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
                          label: row.source?.rolloverEnabled == true
                              ? '结转已开启'
                              : '结转未开启',
                          color: row.source?.rolloverEnabled == true
                              ? palette.income
                              : palette.textMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _AmountLine(label: '基础预算', amount: row.budget),
                    _AmountLine(
                      label: '上月结转',
                      amount: row.rollover,
                      positive: row.rollover >= 0,
                    ),
                    compassHairline,
                    _AmountLine(
                      label: '有效预算',
                      amount: effective,
                      emphasized: true,
                    ),
                  ],
                ),
              ),
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
                    account: _accountName(liveRepository, item.accountId),
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
                onPressed: () => _delete(row),
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
    final result = await Navigator.push<Budget>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BudgetEditorPage(
          repository: repository,
          initialBudget: row.source,
          presentation: row,
          monthKey: widget.monthKey,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await ref.read(budgetMutationsProvider.notifier).addBudget(result);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(_BudgetPresentation row) async {
    final budget = row.source;
    if (budget == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除预算？'),
            content: const Text('交易不会被删除，只会移除此预算设置。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
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

class BudgetEditorPage extends StatefulWidget {
  const BudgetEditorPage({
    super.key,
    required this.repository,
    this.initialBudget,
    this.presentation,
    required this.monthKey,
  });

  final FinanceRepository repository;
  final Budget? initialBudget;
  final _BudgetPresentation? presentation;
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

  @override
  void initState() {
    super.initState();
    final initialAmount =
        widget.initialBudget?.amount ?? widget.presentation?.budget ?? 0;
    amountController = TextEditingController(
      text: initialAmount > 0 ? initialAmount.toStringAsFixed(0) : '',
    );
    threshold = widget.initialBudget?.alertThreshold ?? .8;
    rollover = widget.initialBudget?.rolloverEnabled ?? true;
    effectiveMonthKey = widget.monthKey;
    categoryId = widget.initialBudget?.categoryId ??
        widget.repository
            .categoriesByType(CategoryType.expense)
            .firstOrNull
            ?.id;
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = double.tryParse(amountController.text) ?? 0;
    final carried =
        (rollover ? widget.presentation?.rollover ?? 0 : 0).toDouble();
    final effective = base + carried;
    final categoryName = categoryId == null
        ? '请选择'
        : _translatedBudgetName(widget.repository.categoryName(categoryId!));
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
                      '${compassMoney(base, decimals: 0)}  +  结转 ${compassMoney(carried, decimals: 0)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    Text('有效预算', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(
                      compassMoney(effective, decimals: 0),
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
              if (widget.presentation case final row?) ...[
                const SizedBox(height: 16),
                _BudgetUsageSummary(
                  actual: row.actual,
                  planned: row.planned,
                  remaining: effective - row.actual - row.planned,
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
                currency: widget.repository.baseCurrency,
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
                onPressed: () => _showNextMonthPreview(
                  base: base,
                  carried: carried,
                ),
                icon: const Icon(Icons.trending_up_rounded),
                label: const Text('预览下月预算'),
              ),
              const SizedBox(height: 28),
              CompassPrimaryButton(
                label: '保存更改',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final amount = double.tryParse(amountController.text.trim());
    if (categoryId == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择支出类别并输入大于 0 的预算。')),
      );
      return;
    }
    final initial = widget.initialBudget;
    final updatesSameRule = initial != null &&
        initial.categoryId == categoryId &&
        initial.monthKey == effectiveMonthKey;
    Navigator.pop(
      context,
      Budget(
        id: updatesSameRule ? initial.id : buildId('budget'),
        categoryId: categoryId!,
        monthKey: effectiveMonthKey,
        amount: amount,
        alertThreshold: threshold,
        rolloverEnabled: rollover,
      ),
    );
  }

  Future<void> _pickCategory() async {
    final categories = widget.repository.categoriesByType(CategoryType.expense);
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
                title: Text(category.name),
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
      setState(() => categoryId = selected.id);
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
      setState(() => effectiveMonthKey = monthKeyFromDate(selected));
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

  Future<void> _showNextMonthPreview({
    required double base,
    required double carried,
  }) async {
    final actual = widget.presentation?.actual ?? 0;
    final planned = widget.presentation?.planned ?? 0;
    final projectedCarry = rollover ? base + carried - actual - planned : 0.0;
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
          '基础预算：${compassMoney(base)}\n'
          '预计结转：${compassMoney(projectedCarry)}\n'
          '预计可用：${compassMoney(base + projectedCarry)}',
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
    this.source,
  });

  final String name;
  final IconData icon;
  final double budget;
  final double actual;
  final double planned;
  final double rollover;
  final Budget? source;

  bool get hasAllocation => budget.isFinite && budget > 0;
}

List<_BudgetPresentation> _budgetRows(
  FinanceRepository repository,
  String month,
) {
  final budgets = repository.activeBudgetsForMonth(month);
  return budgets.map((budget) {
    final name = repository.categoryName(budget.categoryId);
    final base = repository.budgetAmountInBase(budget);
    final effective = repository.effectiveBudgetForMonth(budget, month);
    return _BudgetPresentation(
      name: _translatedBudgetName(name),
      icon: _budgetIcon(name),
      budget: base,
      actual: repository.expenseTotalForCategory(budget.categoryId, month),
      planned:
          repository.plannedExpenseTotalForCategory(budget.categoryId, month),
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
    final effective = row.budget + row.rollover;
    final remaining = effective - row.actual - row.planned;
    final remainingAmount = remaining.abs().toStringAsFixed(0);
    final share = row.hasAllocation && allocationTotal.isFinite
        ? row.budget / allocationTotal * 100
        : 0;
    final threshold = row.source?.alertThreshold ?? .8;
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
    if (palette.monochrome && !desktop) {
      String amount(double value) =>
          compassMoney(value, decimals: 0, showCurrency: false);
      final textTheme = Theme.of(context).textTheme;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CompassIconBadge(icon: row.icon, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.name, style: textTheme.titleMedium),
                        Text(
                            '预算 ${amount(row.budget)} · ${share.toStringAsFixed(1)}%',
                            style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: Text(
                      '${remaining < 0 ? '超出' : '剩余'} ${amount(remaining.abs())}',
                      textAlign: TextAlign.end,
                      style: textTheme.titleSmall?.copyWith(
                        color: remaining < 0
                            ? palette.expense
                            : (actualRatio + plannedRatio) >= threshold
                                ? palette.warning
                                : palette.textPrimary,
                        fontFeatures: compassTabularFigures,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 46, top: 8, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompassDualProgressBar(
                      actualRatio: actualRatio,
                      plannedRatio: plannedRatio,
                      alertThreshold: threshold,
                      height: 6,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          '实际 ${amount(row.actual)}',
                          style: textTheme.bodySmall?.copyWith(
                            fontFeatures: compassTabularFigures,
                          ),
                        ),
                        Text(
                          '预计 ${amount(row.planned)}',
                          style: textTheme.bodySmall?.copyWith(
                            fontFeatures: compassTabularFigures,
                          ),
                        ),
                        if (row.rollover != 0)
                          Text(
                            '结转 ${amount(row.rollover)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: row.rollover > 0
                                  ? palette.income
                                  : palette.expense,
                              fontFeatures: compassTabularFigures,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: desktop ? 12 : 18),
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
              flex: desktop ? 5 : 3,
              child: _BudgetSpendColumns(
                desktop: desktop,
                actual: _BudgetSpendValue(
                  value: row.actual,
                  showMarker: !desktop,
                ),
                planned: _BudgetSpendValue(
                  value: row.planned,
                  showMarker: !desktop,
                  planned: true,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${row.rollover > 0 ? '+' : ''}${row.rollover.toStringAsFixed(0)}',
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
                desktop: desktop,
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
            '预算 ${budget.toStringAsFixed(0)}',
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
    required this.desktop,
    required this.remaining,
    required this.remainingAmount,
    required this.remainingColor,
  });

  final bool desktop;
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
            semanticsLabel:
                desktop && remaining >= 0 ? '剩余 $remainingAmount' : null,
            style: TextStyle(
              color: remainingColor,
              fontSize: 16,
              fontWeight: remaining < 0 ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: compassTabularFigures,
            ),
          ),
        ),
        if (!desktop || remaining < 0)
          Text(
            remaining < 0 ? '超出' : '剩余',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: remaining < 0 ? palette.expense : null,
                  fontWeight: remaining < 0 ? FontWeight.w600 : null,
                ),
          ),
      ],
    );
  }
}

class _BudgetSpendColumns extends StatelessWidget {
  const _BudgetSpendColumns({
    required this.desktop,
    required this.actual,
    required this.planned,
  });

  final bool desktop;
  final Widget actual;
  final Widget planned;

  @override
  Widget build(BuildContext context) => desktop
      ? Row(
          children: [
            Expanded(child: actual),
            const SizedBox(width: 8),
            Expanded(child: planned),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [actual, planned],
        );
}

class _BudgetSpendValue extends StatelessWidget {
  const _BudgetSpendValue({
    required this.value,
    required this.showMarker,
    this.planned = false,
  });

  final double value;
  final bool showMarker;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final amount = value.toStringAsFixed(0);
    return Semantics(
      label: '${planned ? '预计' : '实际'} $amount',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: showMarker ? Alignment.centerLeft : Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMarker) ...[
              _BudgetMarker(
                color: financePaletteOf(context).expense,
                outlined: planned,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              amount,
              style: (planned && showMarker
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(fontFeatures: compassTabularFigures),
            ),
          ],
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
    this.baseCurrency,
    this.daysRemaining,
  });

  final double actual;
  final double planned;
  final double? remaining;
  final double? totalAvailable;
  final String? baseCurrency;
  final int? daysRemaining;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    String amount(double value) =>
        compassMoney(value, decimals: 0, showCurrency: false);

    final labels = [
      '已用 ${amount(actual)}',
      '预计 ${amount(planned)}',
      if (remaining case final value?) '剩余 ${amount(value)}',
    ];
    final available = totalAvailable ?? 0;
    final currency = baseCurrency ?? 'MYR';
    final usedTotal = actual + planned;
    final progressPct =
        available > 0 ? (usedTotal / available * 100).round() : null;
    final rem = remaining;
    String? guidance;
    Color guidanceColor = palette.textMuted;
    if (progressPct != null && rem != null) {
      if (rem < 0) {
        guidance =
            '总进度 $progressPct% · 已超支 ${compassMoney(rem.abs(), currency: currency, decimals: 0)}';
        guidanceColor = palette.expense;
      } else if (daysRemaining != null && daysRemaining! > 0) {
        final daily = rem / daysRemaining!;
        guidance =
            '总进度 $progressPct% · 剩 $daysRemaining 天 · 日均可用 ${compassMoney(daily, currency: currency, decimals: 0)}';
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

class _BudgetMarker extends StatelessWidget {
  const _BudgetMarker({required this.color, required this.outlined});

  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: outlined ? null : color,
          border: outlined ? Border.all(color: color) : null,
        ),
      );
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amount,
    this.positive = false,
    this.emphasized = false,
  });
  final String label;
  final double amount;
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
              '${positive ? '+ ' : emphasized ? '= ' : ''}${compassMoney(amount, decimals: 0)}',
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
            '- ${compassMoney(amount, currency: currency, decimals: 0)}',
            style: TextStyle(
              color: palette.expense,
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

String _translatedBudgetName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('food')) return '餐饮';
  if (lower.contains('shopping')) return '购物';
  if (lower.contains('transport')) return '交通';
  if (lower.contains('housing')) return '住房';
  return name;
}

IconData _budgetIcon(String name) {
  final translated = _translatedBudgetName(name);
  return switch (translated) {
    '餐饮' => Icons.restaurant_outlined,
    '购物' => Icons.shopping_bag_outlined,
    '交通' => Icons.directions_bus_outlined,
    '住房' => Icons.home_outlined,
    _ => Icons.shield_outlined,
  };
}

String _monthLabel(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;
  return '${parts[0]}年${int.tryParse(parts[1]) ?? parts[1]}月';
}

DateTime _monthDateFromKey(String monthKey) {
  final parts = monthKey.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}

String _accountName(FinanceRepository repository, String accountId) {
  for (final account in repository.accounts) {
    if (account.id == accountId) return account.name;
  }
  return '已删除账户';
}
