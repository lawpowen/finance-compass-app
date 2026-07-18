import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/budget.dart';
import '../../core/models/category.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/budget_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';

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
    final palette = financePaletteOf(context);
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final month = monthKeyFromDate(selectedMonth);
    final rows = _budgetRows(repository, month);
    final total = rows.fold<double>(0, (sum, row) => sum + row.budget);
    final used = rows.fold<double>(0, (sum, row) => sum + row.actual);
    final planned = rows.fold<double>(0, (sum, row) => sum + row.planned);
    final rollover = rows.fold<double>(0, (sum, row) => sum + row.rollover);

    return Stack(
      children: [
        ListView(
          padding: compassPagePadding.copyWith(bottom: 104),
          children: [
            Row(
              children: [
                Text('预算', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() {
                    selectedMonth = DateTime(
                      selectedMonth.year,
                      selectedMonth.month - 1,
                    );
                  }),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text(
                  '${selectedMonth.year}年${selectedMonth.month}月',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  onPressed: () => setState(() {
                    selectedMonth = DateTime(
                      selectedMonth.year,
                      selectedMonth.month + 1,
                    );
                  }),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _openEditor(context, repository, null),
                  child: const Text('调整'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('本月已分配',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 5),
                      Text(
                        compassMoney(total, decimals: 0),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('剩余预算池', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(
                      compassMoney(
                        total - used + rollover < 0
                            ? 0
                            : total - used + rollover,
                        decimals: 0,
                      ),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ).copyWith(color: palette.seed),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _BudgetComposition(rows: rows),
            const SizedBox(height: 14),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _BudgetLegend(
                  color: palette.expense,
                  label: '实际 ${compassMoney(used, decimals: 0)}',
                ),
                _BudgetLegend(
                  color: palette.expense,
                  label: '预计 ${compassMoney(planned, decimals: 0)}',
                  striped: true,
                ),
                _BudgetLegend(
                  color: palette.seed,
                  label: '结转净额 +${compassMoney(rollover, decimals: 0)}',
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Text('预算分配',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const Expanded(
                  flex: 2,
                  child: _BudgetColumnLabel('分配比例'),
                ),
                const Expanded(
                  flex: 3,
                  child: _BudgetColumnLabel('实际 / 预计'),
                ),
                const Expanded(
                  flex: 2,
                  child: _BudgetColumnLabel('结转'),
                ),
                const Expanded(
                  flex: 3,
                  child: _BudgetColumnLabel('剩余 / 状态'),
                ),
                const SizedBox(width: 20),
              ],
            ),
            const SizedBox(height: 8),
            compassHairline,
            if (rows.isEmpty)
              const CompassCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('这个月份还没有预算，点右下角加号建立。')),
                ),
              ),
            ...rows.map(
              (row) => Column(
                children: [
                  _BudgetRow(
                    row: row,
                    total: total,
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
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => _openEditor(context, repository, null),
              style: OutlinedButton.styleFrom(
                foregroundColor: FinanceColors.compassTeal,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('重新分配预算'),
            ),
          ],
        ),
        Positioned(
          right: 18,
          bottom: 16,
          child: CompassActionBubble(
            heroTag: 'budget_add',
            icon: Icons.add_rounded,
            color: FinanceColors.compassOrange,
            onPressed: () => _openEditor(context, repository, null),
          ),
        ),
      ],
    );
  }

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
    final row = widget.row;
    final effective = row.budget + row.rollover;
    final remaining = effective - row.actual - row.planned;
    final transactions = widget.repository.transactions.where((item) {
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
                  const Spacer(),
                  Icon(row.icon, color: FinanceColors.compassTeal),
                  const SizedBox(width: 8),
                  Text(row.name, style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _edit,
                    child: const Text('编辑预算'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_monthLabel(widget.monthKey),
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 22),
              Center(
                child: Column(
                  children: [
                    Text('本月剩余', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      compassMoney(remaining, decimals: 0),
                      style: const TextStyle(
                        color: FinanceColors.compassTeal,
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '有效预算  ${compassMoney(effective, decimals: 0)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: effective <= 0
                    ? 0
                    : ((row.actual + row.planned) / effective).clamp(0, 1),
                minHeight: 26,
                borderRadius: BorderRadius.circular(8),
                color: FinanceColors.compassOrange,
                backgroundColor: Colors.transparent,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _BudgetLegend(
                    color: FinanceColors.compassOrange,
                    label: '实际 ${row.actual.toStringAsFixed(0)}',
                  ),
                  _BudgetLegend(
                    color: FinanceColors.compassOrange,
                    label: '预计 ${row.planned.toStringAsFixed(0)}',
                    striped: true,
                  ),
                  _BudgetLegend(
                    color: FinanceColors.compassTeal,
                    label: '剩余 ${remaining.toStringAsFixed(0)}',
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('预算构成', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: FinanceColors.compassTeal,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    row.source?.rolloverEnabled == true ? '结转已开启' : '结转未开启',
                    style: const TextStyle(color: FinanceColors.compassTeal),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AmountLine(label: '基础预算', amount: row.budget),
              _AmountLine(
                label: '上月结转',
                amount: row.rollover,
                positive: true,
              ),
              compassHairline,
              _AmountLine(label: '有效预算', amount: effective, emphasized: true),
              const SizedBox(height: 26),
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
                    account: _accountName(widget.repository, item.accountId),
                    amount: item.amount,
                  ),
                  compassHairline,
                ],
              ),
              const SizedBox(height: 12),
              CompassPrimaryButton(
                label: '删除预算',
                icon: Icons.delete_outline_rounded,
                outlined: true,
                onPressed: _delete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final result = await Navigator.push<Budget>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BudgetEditorPage(
          repository: widget.repository,
          initialBudget: widget.row.source,
          presentation: widget.row,
          monthKey: widget.monthKey,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await ref.read(budgetMutationsProvider.notifier).addBudget(result);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final budget = widget.row.source;
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
    final usage = effective <= 0
        ? 0.0
        : ((widget.presentation?.actual ?? 0) +
                (widget.presentation?.planned ?? 0)) /
            effective;
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
                  const Spacer(),
                  Text(
                      '${widget.initialBudget == null ? '新增' : '编辑'}$categoryName预算',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  const Icon(Icons.more_vert_rounded),
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
                      style: const TextStyle(
                        color: FinanceColors.compassTeal,
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_monthLabel(widget.monthKey),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              LinearProgressIndicator(
                value: usage.clamp(0, 1),
                minHeight: 10,
                borderRadius: BorderRadius.circular(8),
                color: FinanceColors.compassOrange,
                backgroundColor: Colors.transparent,
              ),
              const SizedBox(height: 20),
              _BudgetEditorRow(
                icon: Icons.shield_outlined,
                title: '支出类别',
                value: categoryName,
                onTap: _pickCategory,
              ),
              _BudgetEditorInputRow(
                icon: Icons.account_balance_wallet_outlined,
                title: '基础预算',
                controller: amountController,
                onChanged: (_) => setState(() {}),
              ),
              _BudgetEditorRow(
                icon: Icons.calendar_month_outlined,
                title: '生效月份',
                value: _monthLabel(widget.monthKey),
              ),
              _BudgetEditorRow(
                icon: Icons.notifications_none_rounded,
                title: '提醒阈值',
                value: '${(threshold * 100).round()}%',
                onTap: () =>
                    setState(() => threshold = threshold == .8 ? 1 : .8),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(
                  Icons.refresh_rounded,
                  color: FinanceColors.compassTeal,
                ),
                title: const Text('结转规则'),
                subtitle: const Text('未用与超支都结转'),
                value: rollover,
                onChanged: (value) => setState(() => rollover = value),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'ⓘ  实际与预计交易都会占用预算',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('下月结转会在月末按本月实际支出计算。')),
                ),
                icon: const Icon(Icons.trending_up_rounded),
                label: const Text('预览下月预算  ›'),
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
    Navigator.pop(
      context,
      Budget(
        id: widget.initialBudget?.id ?? buildId('budget'),
        categoryId: categoryId!,
        monthKey: widget.monthKey,
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

class _BudgetComposition extends StatelessWidget {
  const _BudgetComposition({required this.rows});
  final List<_BudgetPresentation> rows;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final total = rows.fold<double>(0, (sum, row) => sum + row.budget);
    if (rows.isEmpty || total <= 0) return const SizedBox.shrink();
    final displayRows = [...rows]..sort((a, b) => b.budget.compareTo(a.budget));
    final visibleRows = displayRows.take(5).toList();
    final visibleTotal = visibleRows.fold<double>(
      0,
      (sum, row) => sum + row.budget,
    );
    final remainingBudget = (total - visibleTotal).clamp(0, total);
    final actual = rows.fold<double>(0, (sum, row) => sum + row.actual);
    final planned = rows.fold<double>(0, (sum, row) => sum + row.planned);
    return Column(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              border: Border.all(color: palette.border),
              color: palette.surface.withValues(alpha: .5),
            ),
            child: Row(
              children: [
                ...visibleRows.indexed.map(
                  (entry) => Expanded(
                    flex:
                        (entry.$2.budget / total * 1000).round().clamp(1, 1000),
                    child: _BudgetAllocationCell(
                      row: entry.$2,
                      share: entry.$2.budget / total,
                      color: palette.seed.withValues(
                        alpha: (.24 - entry.$1 * .028).clamp(.1, .24),
                      ),
                      borderColor: palette.border,
                    ),
                  ),
                ),
                if (remainingBudget > 0.01)
                  Expanded(
                    flex:
                        (remainingBudget / total * 1000).round().clamp(1, 1000),
                    child: Container(
                      decoration: BoxDecoration(
                        color: palette.surfaceAlt.withValues(alpha: .35),
                        border: Border(
                          right: BorderSide(color: palette.border),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _BudgetUsageBar(
          actualRatio: actual / total,
          plannedRatio: planned / total,
          actualColor: palette.expense,
          borderColor: palette.border,
          backgroundColor: palette.surfaceAlt.withValues(alpha: .35),
        ),
      ],
    );
  }
}

class _BudgetAllocationCell extends StatelessWidget {
  const _BudgetAllocationCell({
    required this.row,
    required this.share,
    required this.color,
    required this.borderColor,
  });

  final _BudgetPresentation row;
  final double share;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          border: Border(right: BorderSide(color: borderColor)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${(share * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      );
}

class _BudgetUsageBar extends StatelessWidget {
  const _BudgetUsageBar({
    required this.actualRatio,
    required this.plannedRatio,
    required this.actualColor,
    required this.borderColor,
    required this.backgroundColor,
  });

  final double actualRatio;
  final double plannedRatio;
  final Color actualColor;
  final Color borderColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final actualWidth =
              constraints.maxWidth * actualRatio.clamp(0.0, 1.0);
          final plannedWidth = constraints.maxWidth *
              plannedRatio.clamp(
                0.0,
                (1 - actualRatio.clamp(0.0, 1.0)).clamp(0.0, 1.0),
              );
          return ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(9)),
            child: SizedBox(
              height: 22,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: backgroundColor)),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: actualWidth,
                    child: ColoredBox(color: actualColor),
                  ),
                  if (plannedWidth > 0)
                    Positioned(
                      left: actualWidth,
                      top: 0,
                      bottom: 0,
                      width: plannedWidth,
                      child: CustomPaint(
                        painter: _BudgetStripePainter(color: actualColor),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _BudgetStripePainter extends CustomPainter {
  const _BudgetStripePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: .14),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width + size.height; x += 7) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BudgetStripePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.row,
    required this.total,
    required this.onTap,
  });
  final _BudgetPresentation row;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final remaining = row.budget + row.rollover - row.actual - row.planned;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            CompassIconBadge(icon: row.icon, size: 40),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text('预算 ${row.budget.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child:
                    Text('${(row.budget / total * 100).toStringAsFixed(1)}%'),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('● ${row.actual.toStringAsFixed(0)}'),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('◉ ${row.planned.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  row.rollover == 0
                      ? '+ 0'
                      : '+ ${row.rollover.toStringAsFixed(0)}',
                  style: TextStyle(color: palette.seed),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      remaining.abs().toStringAsFixed(0),
                      style: TextStyle(
                        color: remaining < 0 ? palette.expense : palette.seed,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(remaining < 0 ? '超出' : '剩余',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _BudgetColumnLabel extends StatelessWidget {
  const _BudgetColumnLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _BudgetLegend extends StatelessWidget {
  const _BudgetLegend({
    required this.color,
    required this.label,
    this.striped = false,
  });
  final Color color;
  final String label;
  final bool striped;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            striped ? '◉' : '●',
            style: TextStyle(color: color, fontSize: 12),
          ),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
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
                    ? FinanceColors.compassTeal
                    : FinanceColors.compassMuted,
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
  });
  final String date;
  final String title;
  final String account;
  final double amount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            const CompassIconBadge(icon: Icons.shield_outlined, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: Theme.of(context).textTheme.bodySmall),
                  Text(title),
                  Text(account, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              '- ${compassMoney(amount, decimals: 0)}',
              style: const TextStyle(color: FinanceColors.compassOrange),
            ),
          ],
        ),
      );
}

class _BudgetEditorRow extends StatelessWidget {
  const _BudgetEditorRow({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CompassSettingsRow(
        icon: icon,
        title: title,
        value: value,
        onTap: onTap ?? _noop,
      );
}

class _BudgetEditorInputRow extends StatelessWidget {
  const _BudgetEditorInputRow({
    required this.icon,
    required this.title,
    required this.controller,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: FinanceColors.compassBorder),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Icon(icon, color: FinanceColors.compassTeal),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
            SizedBox(
              width: 128,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: onChanged,
                decoration: const InputDecoration(
                  prefixText: 'MYR ',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
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

String _accountName(FinanceRepository repository, String accountId) {
  for (final account in repository.accounts) {
    if (account.id == accountId) return account.name;
  }
  return '已删除账户';
}

void _noop() {}
