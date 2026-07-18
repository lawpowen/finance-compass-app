import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_action_menu_button.dart';
import 'transaction_automation_pages.dart';
import 'transaction_composer_page.dart';
import 'transaction_form_dialog.dart';
import 'transactions_screen.dart';

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
  TransactionType? typeFilter;
  final Set<String> selectedTransactionIds = {};
  bool isDeleting = false;

  FinanceRepository get repository =>
      ref.read(financeRepositoryProvider).valueOrNull ?? widget.repository;

  bool get isSelecting => selectedTransactionIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRepositoryProvider);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month + monthOffset);
    final realForMonth = repository.transactions
        .where((item) =>
            item.transactionDate.year == month.year &&
            item.transactionDate.month == month.month)
        .toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    final allForMonth = realForMonth;
    final visible = allForMonth.where((item) {
      final matchesStatus =
          includePlanned || item.status != TransactionStatus.planned;
      return matchesStatus && (typeFilter == null || item.type == typeFilter);
    }).toList();
    final income = _totalForType(
      allForMonth,
      TransactionType.income,
      includePlanned: includePlanned,
    );
    final expense = _totalForType(
      allForMonth,
      TransactionType.expense,
      includePlanned: includePlanned,
    );

    return Stack(
      children: [
        ListView(
          padding: compassPagePadding.copyWith(bottom: 108),
          children: [
            CompassPageHeader(
              title:
                  isSelecting ? '已选择 ${selectedTransactionIds.length} 笔' : '交易',
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
                        onPressed: isDeleting
                            ? null
                            : () => _selectAllVisible(visible),
                      ),
                      const SizedBox(width: 8),
                      _HeaderAction(
                        icon: Icons.delete_outline_rounded,
                        tooltip: '删除所选交易',
                        color: FinanceColors.compassOrange,
                        onPressed: isDeleting ? null : _deleteSelected,
                      ),
                    ]
                  : [
                      _HeaderAction(
                        icon: Icons.search_rounded,
                        tooltip: '搜索交易',
                        onPressed: () => showSearch<void>(
                          context: context,
                          delegate: _TransactionSearchDelegate(
                            repository: repository,
                            onEdit: (item) => _showTransactionEditor(
                              context,
                              draft: item,
                              editExisting: true,
                            ),
                            onAction: (value, item) => _handleTransactionAction(
                              context,
                              value,
                              item,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _HeaderAction(
                        icon: Icons.filter_alt_outlined,
                        tooltip: '高级筛选',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('高级筛选')),
                              body: TransactionsScreen(repository: repository),
                            ),
                          ),
                        ),
                      ),
                    ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
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
                  onPressed: monthOffset >= 120 ? null : () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded, size: 19),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide.none,
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${month.month}月净现金流',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 12),
                Text(
                  compassMoney(income - expense, decimals: 0),
                  style: TextStyle(
                    color: income >= expense
                        ? FinanceColors.compassTeal
                        : FinanceColors.compassOrange,
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _FlowLegend(
                  color: FinanceColors.compassTeal,
                  label: '收入 ${compassMoney(income, decimals: 0)}',
                ),
                const SizedBox(width: 18),
                _FlowLegend(
                  color: FinanceColors.compassOrange,
                  label: '支出 ${compassMoney(expense, decimals: 0)}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _StatusSwitch(
              includePlanned: includePlanned,
              onChanged: (value) => setState(() {
                selectedTransactionIds.clear();
                includePlanned = value;
              }),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: '全部',
                    selected: typeFilter == null,
                    onTap: () => _setTypeFilter(null),
                  ),
                  _FilterChip(
                    label: '支出',
                    selected: typeFilter == TransactionType.expense,
                    onTap: () => _setTypeFilter(TransactionType.expense),
                  ),
                  _FilterChip(
                    label: '收入',
                    selected: typeFilter == TransactionType.income,
                    onTap: () => _setTypeFilter(TransactionType.income),
                  ),
                  _FilterChip(
                    label: '转账',
                    selected: typeFilter == TransactionType.transfer,
                    onTap: () => _setTypeFilter(TransactionType.transfer),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const CompassCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: Text('这个月份没有符合条件的交易')),
                ),
              )
            else
              ..._transactionWidgets(context, visible),
          ],
        ),
        if (!isSelecting)
          Positioned(
            right: 18,
            bottom: 16,
            child: Column(
              children: [
                CompassActionBubble(
                  heroTag: 'transactions_v2_quick',
                  icon: Icons.bolt_rounded,
                  onPressed: () => _showQuickTemplates(context),
                ),
                const SizedBox(height: 9),
                CompassActionBubble(
                  heroTag: 'transactions_v2_add',
                  icon: Icons.add_rounded,
                  color: FinanceColors.compassOrange,
                  onPressed: () => _showTransactionEditor(context),
                ),
              ],
            ),
          ),
      ],
    );
  }

  double _totalForType(
    List<FinanceTransaction> transactions,
    TransactionType type, {
    required bool includePlanned,
  }) {
    return transactions
        .where((item) =>
            item.type == type &&
            (includePlanned || item.status != TransactionStatus.planned))
        .fold<double>(
          0,
          (sum, item) =>
              sum + repository.convertToBase(item.amount, item.currency),
        );
  }

  List<Widget> _transactionWidgets(
      BuildContext context, List<FinanceTransaction> transactions) {
    final widgets = <Widget>[];
    DateTime? activeDate;
    for (final item in transactions) {
      final date = DateTime(
        item.transactionDate.year,
        item.transactionDate.month,
        item.transactionDate.day,
      );
      if (activeDate != date) {
        activeDate = date;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 5),
          child: Text(
            '${date.month}月${date.day}日',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ));
      }
      widgets.add(
        _TransactionRow(
          item: item,
          repository: repository,
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
        ),
      );
      widgets.add(const Divider());
    }
    return widgets;
  }

  Future<void> _showTransactionEditor(
    BuildContext context, {
    FinanceTransaction? draft,
    bool editExisting = false,
    String? title,
  }) async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: repository,
          draft: draft,
          editExisting: editExisting,
          title: title,
        ),
      ),
    );
    if (result == null) return;
    final mutations = ref.read(transactionMutationsProvider.notifier);
    if (result.deletedTransactionId case final transactionId?) {
      await mutations.deleteTransaction(transactionId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('交易已删除')),
        );
      }
      return;
    }
    if (editExisting && result.transactions.length == 1) {
      await mutations.updateTransaction(result.transactions.first);
    } else if (result.transactions.length == 1) {
      await mutations.addTransaction(result.transactions.first);
    } else {
      await mutations.addTransactions(result.transactions);
    }
    if (!editExisting && result.transactions.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成 ${result.transactions.length} 笔周期交易')),
      );
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
      await _confirmAndDelete([transaction.id]);
    }
  }

  Future<void> _saveTransactionTemplate(
    BuildContext context,
    FinanceTransaction transaction,
  ) async {
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
    await ref
        .read(transactionMutationsProvider.notifier)
        .addTransactionTemplate(name: name, transaction: transaction);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('模板「$name」已保存')),
    );
  }

  Future<void> _saveRecurringRule(
    BuildContext context,
    FinanceTransaction transaction,
  ) async {
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
    if (!mounted || result == null || result.name.isEmpty) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .addRecurringTransactionRule(
          name: result.name,
          transaction: transaction,
          intervalMonths: result.intervalMonths,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('周期规则「${result.name}」已保存')),
    );
  }

  String _transactionActionName(FinanceTransaction transaction) {
    final direct = transaction.description?.trim().isNotEmpty == true
        ? transaction.description!.trim()
        : transaction.merchant?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (transaction.categoryId != null) {
      return repository.categoryName(transaction.categoryId!);
    }
    return _typeName(transaction.type);
  }

  void _changeMonth(int delta) {
    setState(() {
      selectedTransactionIds.clear();
      monthOffset = (monthOffset + delta).clamp(-120, 120);
      if (monthOffset > 0) includePlanned = true;
    });
  }

  void _setTypeFilter(TransactionType? type) {
    setState(() {
      selectedTransactionIds.clear();
      typeFilter = type;
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
    setState(selectedTransactionIds.clear);
  }

  Future<void> _deleteSelected() async {
    final ids = selectedTransactionIds.toList(growable: false);
    if (ids.isEmpty) return;
    await _confirmAndDelete(ids);
  }

  Future<void> _confirmAndDelete(List<String> ids) async {
    final confirmed = await showDialog<bool>(
          context: context,
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
                  backgroundColor: FinanceColors.compassOrange,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => isDeleting = true);
    try {
      await ref
          .read(transactionMutationsProvider.notifier)
          .deleteTransactions(ids);
      if (!mounted) return;
      setState(selectedTransactionIds.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${ids.length} 笔交易')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    } finally {
      if (mounted) setState(() => isDeleting = false);
    }
  }

  Future<void> _showQuickTemplates(BuildContext context) async {
    final drafts = _quickDrafts(repository);
    final draft = await showGeneralDialog<FinanceTransaction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭快速模板',
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Align(
          alignment: const Alignment(.9, .45),
          child: Material(
            color: FinanceColors.compassSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: FinanceColors.compassBorder),
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
                        const Icon(Icons.search_rounded),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: () => Navigator.pop(dialogContext),
                          child: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (drafts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          '还没有快速模板，请先到“管理”建立模板。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ...drafts.take(5).map(
                          (item) => InkWell(
                            onTap: () => Navigator.pop(dialogContext, item),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: FinanceColors.compassBorder,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CompassIconBadge(
                                    icon: _typeIcon(item.type),
                                    size: 34,
                                    color: item.type == TransactionType.income
                                        ? FinanceColors.compassTeal
                                        : FinanceColors.compassOrange,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(item.merchant ?? '快速交易'),
                                  ),
                                  Text(
                                    compassMoney(item.amount),
                                    style: TextStyle(
                                      color: item.type == TransactionType.income
                                          ? FinanceColors.compassTeal
                                          : FinanceColors.compassOrange,
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
                          icon: const Icon(Icons.grid_view_rounded),
                          label: const Text('全部模板'),
                        ),
                        const Spacer(),
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
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('管理'),
                        ),
                      ],
                    ),
                    Text('ⓘ  选择后确认保存',
                        style: Theme.of(context).textTheme.bodySmall),
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

class _FlowLegend extends StatelessWidget {
  const _FlowLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _StatusSwitch extends StatelessWidget {
  const _StatusSwitch({
    required this.includePlanned,
    required this.onChanged,
  });

  final bool includePlanned;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? FinanceColors.compassTeal.withValues(alpha: .18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? FinanceColors.compassTeal : null,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: ActionChip(
          onPressed: onTap,
          label: Text(label),
          labelStyle: TextStyle(
            color: selected ? FinanceColors.compassTeal : null,
            fontSize: 10.5,
          ),
          visualDensity: VisualDensity.compact,
          backgroundColor: selected
              ? FinanceColors.compassTeal.withValues(alpha: .12)
              : Colors.transparent,
          side: BorderSide(
            color: selected ? FinanceColors.compassTeal : Colors.white12,
          ),
        ),
      );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.item,
    required this.repository,
    this.onTap,
    this.onLongPress,
    this.onAction,
    this.selected = false,
  });

  final FinanceTransaction item;
  final FinanceRepository repository;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onAction;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isExpense = item.type == TransactionType.expense;
    final isIncome = item.type == TransactionType.income;
    final signedAmount = isExpense ? -item.amount : item.amount;
    final showsDirectionalSign =
        isExpense || isIncome || item.type == TransactionType.adjustment;
    final color = signedAmount < 0
        ? FinanceColors.compassOrange
        : FinanceColors.compassTeal;
    final category = item.categoryId == null
        ? _typeName(item.type)
        : _translatedCategory(repository.categoryName(item.categoryId!));
    final title = item.merchant ??
        item.description ??
        (item.type == TransactionType.transfer ? '账户转账' : category);
    final accountName = _translatedAccount(
      repository.accountName(item.accountId),
      item.accountId,
    );
    final subtitle =
        title == category ? accountName : '$accountName · $category';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? FinanceColors.compassTeal.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(
                  color: FinanceColors.compassTeal.withValues(alpha: .55),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              CompassIconBadge(icon: _typeIcon(item.type), color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${showsDirectionalSign && signedAmount > 0 ? '+ ' : ''}'
                    '${compassMoney(signedAmount, currency: item.currency)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.status == TransactionStatus.planned)
                    const Text(
                      '预计',
                      style: TextStyle(
                        color: FinanceColors.compassOrange,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: 7),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: FinanceColors.compassTeal,
                ),
              ] else if (onAction != null) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: FinanceActionMenuButton<String>(
                    tooltip: '交易操作',
                    iconSize: 19,
                    onSelected: onAction!,
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
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionSearchDelegate extends SearchDelegate<void> {
  _TransactionSearchDelegate({
    required this.repository,
    required this.onEdit,
    required this.onAction,
  });

  final FinanceRepository repository;
  final Future<void> Function(FinanceTransaction item) onEdit;
  final Future<void> Function(String value, FinanceTransaction item) onAction;

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          onPressed: () => query = '',
          icon: const Icon(Icons.clear_rounded),
        ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(Icons.arrow_back_rounded),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final matches = repository.transactions.where((item) {
      if (needle.isEmpty) return true;
      return [
        item.merchant,
        item.description,
        repository.accountName(item.accountId),
        if (item.categoryId != null) repository.categoryName(item.categoryId!),
      ]
          .whereType<String>()
          .any((value) => value.toLowerCase().contains(needle));
    }).take(50);
    return ListView(
      padding: compassPagePadding,
      children: matches
          .map(
            (item) => _TransactionRow(
              item: item,
              repository: repository,
              onTap: () async {
                close(context, null);
                await onEdit(item);
              },
              onAction: (value) async {
                close(context, null);
                await onAction(value, item);
              },
            ),
          )
          .toList(),
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

List<FinanceTransaction> _referenceTransactions(
  DateTime month,
  FinanceRepository repository,
) {
  String accountId(AccountType type, String fallback) {
    for (final account in repository.accounts) {
      if (account.accountType == type) return account.id;
    }
    return repository.accounts.isEmpty
        ? fallback
        : repository.accounts.first.id;
  }

  String? categoryId(CategoryType type, String fallback) {
    final categories = repository.categoriesByType(type);
    return categories.isEmpty ? fallback : categories.first.id;
  }

  final cash = accountId(AccountType.cash, 'acc_cash_wallet');
  final saving = accountId(AccountType.bankSaving, 'acc_maybank');
  final card = accountId(AccountType.creditCard, 'acc_card');
  final investment = accountId(AccountType.trading, 'acc_trading');
  final food = categoryId(CategoryType.expense, 'cat_food');
  final income = categoryId(CategoryType.income, 'cat_salary');
  final transfer = categoryId(CategoryType.transfer, 'cat_transfer');
  final expense = categoryId(CategoryType.expense, 'cat_shopping');
  DateTime day(int value) => DateTime(month.year, month.month, value);

  return [
    FinanceTransaction(
      id: 'reference_salary_1',
      type: TransactionType.income,
      accountId: cash,
      categoryId: income,
      amount: 8800,
      currency: 'MYR',
      transactionDate: day(16),
      merchant: '薪资收入',
    ),
    FinanceTransaction(
      id: 'reference_grocery',
      type: TransactionType.expense,
      accountId: card,
      categoryId: expense,
      amount: 156.80,
      currency: 'MYR',
      transactionDate: day(16),
      merchant: '超市购物',
    ),
    FinanceTransaction(
      id: 'reference_lunch',
      type: TransactionType.expense,
      accountId: cash,
      categoryId: food,
      amount: 18,
      currency: 'MYR',
      transactionDate: day(16),
      merchant: '午餐',
    ),
    FinanceTransaction(
      id: 'reference_fuel',
      type: TransactionType.expense,
      accountId: card,
      categoryId: expense,
      amount: 120,
      currency: 'MYR',
      transactionDate: day(16),
      merchant: '加油',
    ),
    FinanceTransaction(
      id: 'reference_transfer',
      type: TransactionType.transfer,
      accountId: saving,
      toAccountId: investment,
      categoryId: transfer,
      amount: 1000,
      currency: 'MYR',
      transactionDate: day(16),
      merchant: '储蓄账户 → 投资账户',
    ),
    FinanceTransaction(
      id: 'reference_lazada',
      type: TransactionType.expense,
      accountId: card,
      categoryId: expense,
      amount: 268,
      currency: 'MYR',
      transactionDate: day(14),
      merchant: 'Lazada',
    ),
    FinanceTransaction(
      id: 'reference_mcd',
      type: TransactionType.expense,
      accountId: cash,
      categoryId: food,
      amount: 18.50,
      currency: 'MYR',
      transactionDate: day(14),
      merchant: '麦当劳',
    ),
    FinanceTransaction(
      id: 'reference_rapid',
      type: TransactionType.expense,
      accountId: cash,
      categoryId: expense,
      amount: 6.20,
      currency: 'MYR',
      transactionDate: day(13),
      merchant: 'Rapid KL',
    ),
    FinanceTransaction(
      id: 'reference_salary_2',
      type: TransactionType.income,
      accountId: saving,
      categoryId: income,
      amount: 3660,
      currency: 'MYR',
      transactionDate: day(13),
      merchant: '薪资收入',
    ),
    FinanceTransaction(
      id: 'reference_online',
      type: TransactionType.expense,
      accountId: card,
      categoryId: expense,
      amount: 289.90,
      currency: 'MYR',
      transactionDate: day(12),
      merchant: '线上购物',
    ),
    FinanceTransaction(
      id: 'reference_fund',
      type: TransactionType.expense,
      accountId: investment,
      categoryId: expense,
      amount: 500,
      currency: 'MYR',
      transactionDate: day(12),
      merchant: '基金定投',
    ),
    FinanceTransaction(
      id: 'reference_installment',
      type: TransactionType.expense,
      accountId: card,
      categoryId: expense,
      amount: 120,
      currency: 'MYR',
      transactionDate: day(12),
      merchant: '手机分期（第2期）',
    ),
    FinanceTransaction(
      id: 'reference_housing',
      type: TransactionType.expense,
      accountId: saving,
      categoryId: expense,
      amount: 4582.60,
      currency: 'MYR',
      transactionDate: day(10),
      merchant: '房租与固定支出',
    ),
  ];
}

String _translatedAccount(String name, String id) {
  final lower = '$name $id'.toLowerCase();
  if (lower.contains('card') || lower.contains('credit')) return '主力信用卡 · 1234';
  if (lower.contains('saving') || lower.contains('maybank')) return '储蓄账户';
  if (lower.contains('trading') || lower.contains('invest')) return '投资账户';
  if (lower.contains('wallet') || lower.contains('cash')) return '现金账户';
  return name;
}

String _translatedCategory(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('food')) return '餐饮';
  if (lower.contains('transport')) return '交通';
  if (lower.contains('shopping')) return '购物';
  if (lower.contains('salary')) return '工资';
  if (lower.contains('transfer')) return '转账';
  if (lower.contains('invest')) return '投资';
  if (lower.contains('housing')) return '住房';
  return name;
}

List<FinanceTransaction> _quickDrafts(FinanceRepository repository) {
  if (repository.transactionTemplates.isNotEmpty) {
    final now = DateTime.now();
    return repository.transactionTemplates
        .map(
          (item) => FinanceTransaction(
            id: 'draft_${item.id}',
            type: item.type,
            accountId: item.accountId,
            toAccountId: item.toAccountId,
            categoryId: item.categoryId,
            amount: item.amount,
            currency: item.currency,
            toAmount: item.toAmount,
            toCurrency: item.toCurrency,
            transactionDate: now,
            status: item.status,
            merchant: item.name,
            description: item.description,
          ),
        )
        .toList();
  }
  return const [];
}
