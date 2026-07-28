import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';
import 'transaction_composer_page.dart';
import 'transaction_form_dialog.dart';

class QuickTemplateManagerPage extends ConsumerWidget {
  const QuickTemplateManagerPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(financeRepositoryProvider).valueOrNull ?? repository;
    final rows = _templateRows(current);
    return _AutomationShell(
      title: '快速模板',
      trailing: const SizedBox.shrink(),
      children: [
        Text(
          '拖动右侧手柄调整顺序，前 5 个模板显示在闪电快捷面板',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const _AutomationEmptyState(
            icon: Icons.bolt_outlined,
            title: '还没有快速模板',
            subtitle: '点右下角加号，填写一笔交易内容并保存为模板。',
          ),
        if (rows.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: rows.length,
            onReorder: (oldIndex, newIndex) {
              unawaited(_reorder(ref, rows, oldIndex, newIndex));
            },
            itemBuilder: (context, index) {
              final row = rows[index];
              return Column(
                key: ValueKey(row.template!.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index == 5) ...[
                    const SizedBox(height: 16),
                    Text(
                      '其他模板',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                  ],
                  _TemplateRow(
                    index: index < 5 ? index + 1 : null,
                    dragIndex: index,
                    row: row,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TemplateEditorPage(
                          repository: current,
                          row: row,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 50),
        Align(
          alignment: Alignment.centerRight,
          child: CompassActionBubble(
            heroTag: 'quick_template_add',
            icon: Icons.add,
            color: FinanceColors.compassOrange,
            onPressed: () => _createTemplate(context, ref, current),
          ),
        ),
      ],
    );
  }

  Future<void> _reorder(
    WidgetRef ref,
    List<_TemplatePresentation> rows,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final reordered = [...rows];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await ref
        .read(transactionMutationsProvider.notifier)
        .reorderTransactionTemplates(
          reordered.map((row) => row.template!.id).toList(),
        );
  }

  Future<void> _createTemplate(
    BuildContext context,
    WidgetRef ref,
    FinanceRepository current,
  ) async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(repository: current),
      ),
    );
    if (result == null || result.transactions.isEmpty || !context.mounted) {
      return;
    }
    final transaction = result.transactions.first;
    final name = await _askForName(
      context,
      initialValue: transaction.merchant ?? '快速模板',
      title: '模板名称',
    );
    if (name == null || !context.mounted) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .addTransactionTemplate(
          name: name,
          transaction: transaction,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模板已保存。')),
      );
    }
  }
}

class TemplateEditorPage extends ConsumerStatefulWidget {
  const TemplateEditorPage({
    super.key,
    required this.repository,
    required this.row,
  });
  final FinanceRepository repository;
  final _TemplatePresentation row;

  @override
  ConsumerState<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends ConsumerState<TemplateEditorPage> {
  late bool pinned;
  late final TextEditingController nameController;
  late FinanceTransaction draft;

  @override
  void initState() {
    super.initState();
    pinned = widget.row.template!.sortOrder < 5;
    nameController = TextEditingController(text: widget.row.name);
    draft = widget.row.draft!;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = _templateFromDraft(
      draft,
      name: nameController.text.trim().isEmpty
          ? widget.row.name
          : nameController.text.trim(),
      model: widget.row.template,
      repository: widget.repository,
    );
    return _AutomationShell(
      title: '编辑模板',
      trailing: const SizedBox(width: 24),
      children: [
        Row(
          children: [
            CompassIconBadge(icon: row.icon, color: row.color, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${row.sign}${compassMoney(row.amount)}',
                      style: TextStyle(color: row.color, fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${row.account} · ${row.category}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '模板名称',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Text('使用时会打开交易草稿，并预填以下内容',
            style: Theme.of(context).textTheme.bodySmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary:
              const Icon(Icons.bolt_rounded, color: FinanceColors.compassTeal),
          title: const Text('显示在闪电快捷面板'),
          subtitle: const Text('前 5 个位置'),
          value: pinned,
          onChanged: (value) => setState(() => pinned = value),
        ),
        _AutomationRow(
          icon: Icons.swap_vert_rounded,
          title: '交易类型',
          value: _transactionTypeLabel(draft.type),
        ),
        _AutomationRow(
          icon: Icons.monetization_on_outlined,
          title: '默认金额',
          value: compassMoney(row.amount),
        ),
        _AutomationRow(
          icon: Icons.account_balance_wallet_outlined,
          title: '付款账户',
          value: row.account,
        ),
        _AutomationRow(
            icon: Icons.sell_outlined, title: '类别', value: row.category),
        const _AutomationRow(
          icon: Icons.storefront_outlined,
          title: '商户',
          value: '未设置',
        ),
        _AutomationRow(
            icon: Icons.chat_bubble_outline, title: '说明', value: row.name),
        const SizedBox(height: 12),
        CompassPrimaryButton(
          label: '编辑预填内容',
          icon: Icons.edit_note_rounded,
          outlined: true,
          onPressed: _editDraft,
        ),
        const SizedBox(height: 22),
        TextButton.icon(
          onPressed: _tryTemplate,
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('试用模板'),
        ),
        Center(
          child: Text('打开预填的支出草稿（不会保存任何交易）',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 22),
        CompassPrimaryButton(
          label: '删除模板',
          icon: Icons.delete_outline_rounded,
          outlined: true,
          onPressed: _delete,
        ),
        const SizedBox(height: 10),
        CompassPrimaryButton(
          label: '保存更改',
          icon: Icons.check_circle_outline_rounded,
          onPressed: _save,
        ),
      ],
    );
  }

  Future<void> _editDraft() async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: widget.repository,
          draft: draft,
        ),
      ),
    );
    if (result != null && result.transactions.isNotEmpty && mounted) {
      setState(() => draft = result.transactions.first);
    }
  }

  Future<void> _tryTemplate() async {
    await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: widget.repository,
          draft: draft,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await _confirmDelete(context, '删除这个快速模板？');
    if (!confirmed || !mounted) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .deleteTransactionTemplate(widget.row.template!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入模板名称。')),
      );
      return;
    }
    final existing = widget.row.template!;
    final updated = TransactionTemplate(
      id: existing.id,
      name: name,
      type: draft.type,
      accountId: draft.accountId,
      toAccountId: draft.toAccountId,
      categoryId: draft.categoryId,
      amount: draft.amount,
      currency: draft.currency,
      toAmount: draft.toAmount,
      toCurrency: draft.toCurrency,
      status: draft.status,
      description: draft.description,
      merchant: draft.merchant,
      sortOrder: pinned ? 0 : 999,
    );
    await ref
        .read(transactionMutationsProvider.notifier)
        .saveTransactionTemplate(updated);
    if (mounted) Navigator.of(context).pop();
  }
}

class RecurringPlanPage extends ConsumerStatefulWidget {
  const RecurringPlanPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  ConsumerState<RecurringPlanPage> createState() => _RecurringPlanPageState();
}

class _RecurringPlanPageState extends ConsumerState<RecurringPlanPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final allRows = _recurringRows(repository);
    final rows = allRows.where((row) {
      if (selected == 1) return row.rule!.isActive;
      if (selected == 2) return !row.rule!.isActive;
      return true;
    }).toList();
    final month = DateTime.now();
    return _AutomationShell(
      title: '周期计划',
      trailing: TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuickTemplateManagerPage(repository: repository),
          ),
        ),
        child: const Text('模板'),
      ),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${month.year}年${month.month}月',
                style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 24),
        CompassSegmentedControl(
          labels: const ['全部', '运行中', '已暂停'],
          selectedIndex: selected,
          onChanged: (value) => setState(() => selected = value),
        ),
        const SizedBox(height: 18),
        if (rows.isEmpty)
          const _AutomationEmptyState(
            icon: Icons.event_repeat_outlined,
            title: '没有符合条件的周期规则',
            subtitle: '点右下角加号建立真实周期交易。',
          ),
        ...rows.indexed.map(
          (entry) => _RecurringRow(
            row: entry.$2,
            enabled: entry.$2.rule!.isActive,
            onToggle: (value) => _toggle(entry.$2.rule!, value),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecurringRuleEditorPage(
                  repository: repository,
                  row: entry.$2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        CompassSettingsRow(
          icon: Icons.calendar_month_outlined,
          title: '选择生成周期',
          subtitle: '可直接选择未来 1–12 个月，已生成月份不会重复',
          onTap: allRows.isEmpty ? null : () => _generateAll(allRows),
        ),
        const SizedBox(height: 18),
        Text('ⓘ  规则生成的是预计交易；发生后可转为实际',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            children: [
              CompassActionBubble(
                heroTag: 'recurring_add',
                icon: Icons.add,
                color: FinanceColors.compassOrange,
                onPressed: () => _createRule(repository),
              ),
              const SizedBox(height: 6),
              const Text('新增周期规则', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(RecurringTransactionRule rule, bool value) async {
    await ref
        .read(transactionMutationsProvider.notifier)
        .saveRecurringTransactionRule(rule.copyWith(isActive: value));
  }

  Future<void> _generateAll(List<_RecurringPresentation> rows) async {
    final months = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('生成周期交易', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '选择要生成预计交易的未来月份范围。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(12, (index) {
                  final value = index + 1;
                  return ChoiceChip(
                    label: Text('$value 个月'),
                    selected: false,
                    onSelected: (_) => Navigator.pop(sheetContext, value),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
    if (months == null || !mounted) return;
    final mutations = ref.read(transactionMutationsProvider.notifier);
    for (final row in rows.where((item) => item.rule!.isActive)) {
      await mutations.generateRecurringTransactions(
        row.rule!.id,
        monthsAhead: months,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('未来 $months 个月的周期交易已生成为预计记录。')),
      );
    }
  }

  Future<void> _createRule(FinanceRepository repository) async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: repository,
          allowRecurringGeneration: false,
        ),
      ),
    );
    if (result == null || result.transactions.isEmpty || !mounted) return;
    final transaction = result.transactions.first;
    final name = await _askForName(
      context,
      initialValue: transaction.merchant ?? '周期交易',
      title: '周期规则名称',
    );
    if (name == null || !mounted) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .addRecurringTransactionRule(
          name: name,
          transaction: transaction,
          intervalMonths: 1,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每月周期规则已建立，并生成未来 3 个完整月份的预计交易。')),
      );
    }
  }
}

class RecurringRuleEditorPage extends ConsumerStatefulWidget {
  const RecurringRuleEditorPage({
    super.key,
    required this.repository,
    required this.row,
  });
  final FinanceRepository repository;
  final _RecurringPresentation row;

  @override
  ConsumerState<RecurringRuleEditorPage> createState() =>
      _RecurringRuleEditorPageState();
}

class _RecurringRuleEditorPageState
    extends ConsumerState<RecurringRuleEditorPage> {
  late bool active;
  late int intervalMonths;
  late DateTime? endDate;
  late final TextEditingController nameController;
  late FinanceTransaction draft;

  @override
  void initState() {
    super.initState();
    final model = widget.row.rule!;
    active = model.isActive;
    intervalMonths = model.intervalMonths;
    endDate = model.endDate;
    nameController = TextEditingController(text: model.name);
    draft = widget.row.draft!;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = _recurringFromDraft(
      draft,
      model: widget.row.rule!,
      name: nameController.text.trim().isEmpty
          ? widget.row.name
          : nameController.text.trim(),
      repository: widget.repository,
    );
    final start = draft.transactionDate;
    return _AutomationShell(
      title: '编辑周期规则',
      trailing: PopupMenuButton<String>(
        tooltip: '规则操作',
        onSelected: (value) {
          if (value == 'toggle') setState(() => active = !active);
          if (value == 'delete') _delete();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'toggle',
            child: Text(active ? '暂停规则' : '启用规则'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('删除规则')),
        ],
      ),
      children: [
        Row(
          children: [
            CompassIconBadge(icon: row.icon, color: row.color, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name,
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(
                    '${row.sign}${compassMoney(row.amount)}',
                    style: TextStyle(color: row.color, fontSize: 23),
                  ),
                  Text('${row.account} · ${row.category}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Column(
              children: [
                const Text('运行中',
                    style: TextStyle(color: FinanceColors.compassTeal)),
                Switch(
                    value: active,
                    onChanged: (value) => setState(() => active = value)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '规则名称',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text.rich(
            TextSpan(
              text: '每 $intervalMonths 个月 · ${start.day} 日发生，生成',
              style: const TextStyle(fontSize: 22),
              children: const [
                TextSpan(
                  text: '未来 3 个月',
                  style: TextStyle(color: FinanceColors.compassTeal),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _RuleDate(date: _futureRuleDate(start, intervalMonths, 1)),
            const Expanded(child: Divider(color: FinanceColors.compassTeal)),
            _RuleDate(date: _futureRuleDate(start, intervalMonths, 2)),
            const Expanded(child: Divider(color: FinanceColors.compassTeal)),
            _RuleDate(date: _futureRuleDate(start, intervalMonths, 3)),
          ],
        ),
        const SizedBox(height: 24),
        _AutomationRow(
          icon: Icons.description_outlined,
          title: '交易内容',
          value: row.name,
          onTap: _editDraft,
        ),
        _AutomationRow(
          icon: Icons.account_balance_wallet_outlined,
          title: '金额与账户',
          value: '${compassMoney(row.amount)} · ${row.account}',
          onTap: _editDraft,
        ),
        _AutomationRow(
          icon: Icons.sell_outlined,
          title: '类别',
          value: row.category,
          onTap: _editDraft,
        ),
        _AutomationRow(
          icon: Icons.repeat_rounded,
          title: '重复频率',
          value: intervalMonths == 1 ? '每月' : '每 $intervalMonths 个月',
          onTap: _pickInterval,
        ),
        _AutomationRow(
          icon: Icons.calendar_month_outlined,
          title: '发生日期',
          value: '每月 ${start.day} 日',
          onTap: _pickStartDate,
        ),
        _AutomationRow(
          icon: Icons.flag_outlined,
          title: '结束条件',
          value: endDate == null
              ? '从不结束'
              : '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
          onTap: _pickEndCondition,
        ),
        _AutomationRow(
          icon: Icons.event_repeat_outlined,
          title: '补生成预计交易',
          value: '选择未来 1–12 个月',
          onTap: _generateForRule,
        ),
        const SizedBox(height: 12),
        CompassPrimaryButton(
          label: '编辑交易内容',
          icon: Icons.edit_note_rounded,
          outlined: true,
          onPressed: _editDraft,
        ),
        const SizedBox(height: 12),
        Text('ⓘ  将创建预计交易；发生后可转为实际',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: CompassPrimaryButton(
                label: '删除规则',
                outlined: true,
                onPressed: _delete,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CompassPrimaryButton(
                label: '保存更改',
                onPressed: _save,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editDraft() async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: widget.repository,
          draft: draft,
        ),
      ),
    );
    if (result != null && result.transactions.isNotEmpty && mounted) {
      setState(() => draft = result.transactions.first);
    }
  }

  Future<void> _pickInterval() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('重复频率', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final months in const [1, 2, 3, 6, 12])
              ListTile(
                title: Text(months == 1 ? '每月' : '每 $months 个月'),
                trailing: intervalMonths == months
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, months),
              ),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => intervalMonths = value);
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: draft.transactionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
      helpText: '选择周期开始日期',
    );
    if (selected == null || !mounted) return;
    setState(() {
      draft = FinanceTransaction(
        id: draft.id,
        type: draft.type,
        accountId: draft.accountId,
        toAccountId: draft.toAccountId,
        categoryId: draft.categoryId,
        amount: draft.amount,
        currency: draft.currency,
        toAmount: draft.toAmount,
        toCurrency: draft.toCurrency,
        recordDate: draft.recordDate,
        transactionDate: selected,
        status: draft.status,
        recurringRuleId: draft.recurringRuleId,
        description: draft.description,
        merchant: draft.merchant,
      );
    });
  }

  Future<void> _pickEndCondition() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('从不结束'),
              onTap: () => Navigator.pop(sheetContext, 'never'),
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('选择结束日期'),
              onTap: () => Navigator.pop(sheetContext, 'date'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (action == 'never' && mounted) {
      setState(() => endDate = null);
      return;
    }
    if (action != 'date' || !mounted) return;
    final selected = await showDatePicker(
      context: context,
      initialDate:
          endDate ?? draft.transactionDate.add(const Duration(days: 365)),
      firstDate: draft.transactionDate,
      lastDate: DateTime(2200),
      helpText: '选择周期结束日期',
    );
    if (selected != null && mounted) setState(() => endDate = selected);
  }

  Future<void> _generateForRule() async {
    final months = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(12, (index) {
              final value = index + 1;
              return ActionChip(
                label: Text('$value 个月'),
                onPressed: () => Navigator.pop(sheetContext, value),
              );
            }),
          ),
        ),
      ),
    );
    if (months == null || !mounted) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .generateRecurringTransactions(widget.row.rule!.id,
            monthsAhead: months);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已补生成未来 $months 个月的预计交易。')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirmDelete(context, '删除这个周期规则？');
    if (!confirmed || !mounted) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .deleteRecurringTransactionRule(widget.row.rule!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入规则名称。')),
      );
      return;
    }
    final existing = widget.row.rule!;
    final updated = RecurringTransactionRule(
      id: existing.id,
      name: name,
      type: draft.type,
      accountId: draft.accountId,
      toAccountId: draft.toAccountId,
      categoryId: draft.categoryId,
      amount: draft.amount,
      currency: draft.currency,
      toAmount: draft.toAmount,
      toCurrency: draft.toCurrency,
      startDate: draft.transactionDate,
      intervalMonths: intervalMonths,
      status: draft.status,
      description: draft.description,
      merchant: draft.merchant,
      endDate: endDate,
      generatedMonthKeys: existing.generatedMonthKeys,
      isActive: active,
    );
    await ref
        .read(transactionMutationsProvider.notifier)
        .saveRecurringTransactionRule(updated);
    if (mounted) Navigator.of(context).pop();
  }
}

class _AutomationShell extends StatelessWidget {
  const _AutomationShell({
    required this.title,
    required this.children,
    required this.trailing,
  });
  final String title;
  final List<Widget> children;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: CompassBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    const CompassBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(title,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    trailing,
                  ],
                ),
                const SizedBox(height: 22),
                ...children,
              ],
            ),
          ),
        ),
      );
}

class _TemplatePresentation {
  const _TemplatePresentation({
    required this.name,
    required this.account,
    required this.category,
    required this.amount,
    required this.icon,
    required this.color,
    this.template,
    this.draft,
    this.sign = '',
  });
  final String name;
  final String account;
  final String category;
  final double amount;
  final IconData icon;
  final Color color;
  final TransactionTemplate? template;
  final FinanceTransaction? draft;
  final String sign;
}

class _RecurringPresentation extends _TemplatePresentation {
  const _RecurringPresentation({
    required super.name,
    required super.account,
    required super.category,
    required super.amount,
    required super.icon,
    required super.color,
    required this.date,
    this.rule,
    super.draft,
    super.sign,
  });
  final String date;
  final RecurringTransactionRule? rule;
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.row,
    required this.onTap,
    this.index,
    this.dragIndex,
  });
  final _TemplatePresentation row;
  final VoidCallback onTap;
  final int? index;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
          ),
          child: Row(
            children: [
              if (index != null) ...[
                CircleAvatar(
                  radius: 11,
                  backgroundColor: FinanceColors.compassTeal,
                  child: Text('$index', style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 12),
              ],
              CompassIconBadge(icon: row.icon, color: row.color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('${row.account} · ${row.category}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${row.sign}${compassMoney(row.amount)}',
                    style: TextStyle(color: row.color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (dragIndex case final index?)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                )
              else
                const Icon(Icons.drag_handle_rounded),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({
    required this.row,
    required this.enabled,
    required this.onToggle,
    required this.onTap,
  });
  final _RecurringPresentation row;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
          ),
          child: Row(
            children: [
              SizedBox(width: 48, child: Text(row.date)),
              CompassIconBadge(icon: row.icon, color: row.color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('每 ${row.rule!.intervalMonths} 个月  |  ${row.account}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${row.sign}${compassMoney(row.amount)}',
                    style: TextStyle(color: row.color),
                  ),
                  Switch(value: enabled, onChanged: onToggle),
                ],
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}

class _AutomationRow extends StatelessWidget {
  const _AutomationRow({
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
        onTap: onTap,
      );
}

class _RuleDate extends StatelessWidget {
  const _RuleDate({required this.date});
  final String date;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(date),
          const SizedBox(height: 8),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: FinanceColors.compassTeal, width: 2),
            ),
          ),
        ],
      );
}

List<_TemplatePresentation> _templateRows(FinanceRepository repository) {
  final rows = repository.transactionTemplates
      .map((item) => _templateFromModel(item, repository))
      .toList();
  rows.sort((a, b) => a.template!.sortOrder.compareTo(b.template!.sortOrder));
  return rows;
}

_TemplatePresentation _templateFromModel(
  TransactionTemplate item,
  FinanceRepository repository,
) {
  final draft = FinanceTransaction(
    id: buildId('draft'),
    type: item.type,
    accountId: item.accountId,
    toAccountId: item.toAccountId,
    categoryId: item.categoryId,
    amount: item.amount,
    currency: item.currency,
    toAmount: item.toAmount,
    toCurrency: item.toCurrency,
    recordDate: DateTime.now(),
    transactionDate: DateTime.now(),
    status: item.status,
    description: item.description,
    merchant: item.merchant,
  );
  return _templateFromDraft(
    draft,
    name: item.name,
    model: item,
    repository: repository,
  );
}

_TemplatePresentation _templateFromDraft(
  FinanceTransaction draft, {
  required String name,
  required TransactionTemplate? model,
  required FinanceRepository repository,
}) {
  final income = draft.type == TransactionType.income;
  final transfer = draft.type == TransactionType.transfer;
  return _TemplatePresentation(
    name: name,
    account: transfer
        ? '${_accountName(repository, draft.accountId)} → '
            '${_accountName(repository, draft.toAccountId)}'
        : _accountName(repository, draft.accountId),
    category: transfer ? '转账' : _categoryName(repository, draft.categoryId),
    amount: draft.amount,
    icon: income
        ? Icons.badge_outlined
        : transfer
            ? Icons.swap_horiz_rounded
            : Icons.shopping_bag_outlined,
    color: income ? FinanceColors.compassTeal : FinanceColors.compassOrange,
    sign: income ? '+ ' : '',
    template: model,
    draft: draft,
  );
}

List<_RecurringPresentation> _recurringRows(FinanceRepository repository) =>
    repository.recurringTransactionRules
        .map((item) => _recurringFromModel(item, repository))
        .toList()
      ..sort((a, b) => a.rule!.startDate.compareTo(b.rule!.startDate));

_RecurringPresentation _recurringFromModel(
  RecurringTransactionRule item,
  FinanceRepository repository,
) {
  final draft = item.toTransaction(
    id: buildId('draft'),
    date: item.startDate,
    status: item.status,
  );
  return _recurringFromDraft(
    draft,
    model: item,
    name: item.name,
    repository: repository,
  );
}

_RecurringPresentation _recurringFromDraft(
  FinanceTransaction draft, {
  required RecurringTransactionRule model,
  required String name,
  required FinanceRepository repository,
}) {
  final base = _templateFromDraft(
    draft,
    name: name,
    model: null,
    repository: repository,
  );
  return _RecurringPresentation(
    date: '${model.startDate.month}月${model.startDate.day}日',
    name: base.name,
    account: base.account,
    category: base.category,
    amount: base.amount,
    icon: base.icon,
    color: base.color,
    sign: base.sign,
    draft: draft,
    rule: model,
  );
}

String _accountName(FinanceRepository repository, String? id) {
  for (final account in repository.accounts) {
    if (account.id == id) return account.name;
  }
  return id == null ? '未设置账户' : '已删除账户';
}

String _categoryName(FinanceRepository repository, String? id) {
  for (final category in repository.categories) {
    if (category.id == id) return category.name;
  }
  return id == null ? '未分类' : '已删除类别';
}

String _transactionTypeLabel(TransactionType type) => switch (type) {
      TransactionType.income => '收入',
      TransactionType.expense => '支出',
      TransactionType.transfer => '转账',
      TransactionType.adjustment => '调整',
    };

String _futureRuleDate(DateTime start, int intervalMonths, int step) {
  final date =
      DateTime(start.year, start.month + intervalMonths * step, start.day);
  return '${date.month}月${date.day}日';
}

Future<String?> _askForName(
  BuildContext context, {
  required String initialValue,
  required String title,
}) {
  var pendingName = initialValue;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        onChanged: (value) => pendingName = value,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final text = pendingName.trim();
            if (text.isNotEmpty) Navigator.pop(dialogContext, text);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(message),
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

class _AutomationEmptyState extends StatelessWidget {
  const _AutomationEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: FinanceColors.compassSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FinanceColors.compassBorder),
        ),
        child: Column(
          children: [
            Icon(icon, size: 42, color: FinanceColors.compassTeal),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
