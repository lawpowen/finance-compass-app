import 'package:flutter/material.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/models/transaction.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';
import 'transaction_form_dialog.dart';

class TransactionComposerPage extends StatefulWidget {
  const TransactionComposerPage({
    super.key,
    required this.repository,
    this.draft,
    this.editExisting = false,
    this.title,
    this.allowRecurringGeneration = true,
  });

  final FinanceRepository repository;
  final FinanceTransaction? draft;
  final bool editExisting;
  final String? title;
  final bool allowRecurringGeneration;

  @override
  State<TransactionComposerPage> createState() =>
      _TransactionComposerPageState();
}

class _TransactionComposerPageState extends State<TransactionComposerPage> {
  late TransactionType type;
  late TransactionStatus status;
  late DateTime date;
  late String? accountId;
  late String? toAccountId;
  late String? categoryId;
  late final TextEditingController amountController;
  late final TextEditingController toAmountController;
  late final TextEditingController merchantController;
  late final TextEditingController noteController;
  bool _isAutoSettingToAmount = false;
  bool _toAmountEditedByUser = false;
  bool moreExpanded = true;
  int recurrenceMonths = 1;

  FinanceRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    type = draft?.type ?? TransactionType.expense;
    status = draft?.status ?? TransactionStatus.actual;
    date = draft?.transactionDate ?? DateTime.now();
    accountId = draft?.accountId ??
        (repository.accounts.isEmpty ? null : repository.accounts.first.id);
    toAccountId = draft?.toAccountId;
    categoryId = draft?.categoryId ?? _categoriesForType(type).firstOrNull?.id;
    final amount = draft?.amount ?? 0;
    amountController = TextEditingController(
      text: draft == null ? '' : amount.toStringAsFixed(2),
    );
    toAmountController = TextEditingController(
      text: draft?.toAmount?.toStringAsFixed(2) ?? '',
    );
    _toAmountEditedByUser = draft?.toAmount != null;
    merchantController = TextEditingController(
      text: draft?.merchant ?? '',
    );
    noteController = TextEditingController(text: draft?.description ?? '');
    amountController.addListener(_updateTransferEstimateIfAllowed);
    toAmountController.addListener(_markToAmountEdited);
    _updateTransferEstimate(
      force: draft?.toAmount == null || _isSameCurrencyTransfer,
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    toAmountController.dispose();
    merchantController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _account(accountId);
    final category = _category(categoryId);
    final statementDay = account?.statementDay ?? 12;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 28),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title ?? (widget.editExisting ? '编辑交易' : '新增交易'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: _submit,
                    child: Text(widget.editExisting ? '保存修改' : '保存'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _TypeTabs(
                selected: type,
                onChanged: (value) {
                  setState(() {
                    type = value;
                    categoryId = _categoriesForType(value).firstOrNull?.id;
                    if (value != TransactionType.transfer) toAccountId = null;
                    _toAmountEditedByUser = false;
                  });
                  _updateTransferEstimate(force: true);
                },
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _applyTemplate,
                  icon: const CompassIconBadge(
                    icon: Icons.bolt_rounded,
                    outlined: true,
                    size: 26,
                  ),
                  label: const Text('套用模板'),
                ),
              ),
              Text(
                type == TransactionType.transfer ? '转出金额' : '金额',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: const TextStyle(
                        color: FinanceColors.compassTeal,
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        prefixText: '${account?.currency ?? 'MYR'} ',
                        prefixStyle: const TextStyle(
                          color: FinanceColors.compassTeal,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _pickAccount,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    child: Text('${account?.currency ?? 'MYR'}⌄'),
                  ),
                ],
              ),
              if (type == TransactionType.transfer) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '转入金额',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (toAccountId != null && !_isSameCurrencyTransfer)
                      TextButton(
                        onPressed: () {
                          _toAmountEditedByUser = false;
                          _updateTransferEstimate(force: true);
                        },
                        child: const Text('重新换算'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: toAmountController,
                        enabled: toAccountId != null,
                        readOnly: _isSameCurrencyTransfer,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        style: const TextStyle(
                          color: FinanceColors.compassTeal,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          prefixText:
                              '${_account(toAccountId)?.currency ?? '---'} ',
                          prefixStyle: const TextStyle(
                            color: FinanceColors.compassTeal,
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                          ),
                          hintText: toAccountId == null ? '先选择账户' : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _pickToAccount,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        '${_account(toAccountId)?.currency ?? '选择'}⌄',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _transferConversionHint(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              CompassSegmentedControl(
                labels: const ['已发生', '预计'],
                selectedIndex: status == TransactionStatus.planned ? 1 : 0,
                onChanged: (index) => setState(() {
                  status = index == 0
                      ? TransactionStatus.actual
                      : TransactionStatus.planned;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'ⓘ  预计交易不会影响真实余额',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              const CompassSectionLabel('基本信息'),
              _ComposerRow(
                icon: Icons.account_balance_wallet_outlined,
                title: type == TransactionType.transfer ? '转出账户' : '付款账户',
                value: account?.name ?? '请选择账户',
                onTap: _pickAccount,
              ),
              if (type == TransactionType.transfer)
                _ComposerRow(
                  icon: Icons.call_received_rounded,
                  title: '转入账户',
                  value: _account(toAccountId)?.name ?? '请选择账户',
                  onTap: _pickToAccount,
                ),
              if (type != TransactionType.transfer)
                _ComposerRow(
                  icon: Icons.sell_outlined,
                  title: '类别',
                  value: category?.name ?? '未分类',
                  onTap: _pickCategory,
                ),
              _ComposerInputRow(
                icon: Icons.storefront_outlined,
                title: '商户',
                controller: merchantController,
                hintText: '添加商户',
              ),
              _ComposerRow(
                icon: Icons.calendar_month_outlined,
                title: '交易日期',
                value: '${date.year}年${date.month}月${date.day}日',
                onTap: _pickDate,
              ),
              if (account?.accountType == AccountType.creditCard)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 38,
                        child: Icon(
                          Icons.credit_card_rounded,
                          color: FinanceColors.compassTeal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '将自动归入下期账单 · 8月$statementDay日结算',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              InkWell(
                onTap: () => setState(() => moreExpanded = !moreExpanded),
                child: Row(
                  children: [
                    const CompassSectionLabel('更多信息'),
                    const Spacer(),
                    Icon(
                      moreExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                    ),
                  ],
                ),
              ),
              if (moreExpanded) ...[
                _ComposerInputRow(
                  icon: Icons.edit_outlined,
                  title: '说明',
                  controller: noteController,
                  hintText: '添加备注（选填）',
                ),
                _ComposerRow(
                  icon: Icons.attach_file_rounded,
                  title: '附件',
                  value: '计划中（此版本尚未提供）',
                  onTap: () => _showPlannedFeature('附件'),
                ),
                if (!widget.editExisting && widget.allowRecurringGeneration)
                  _ComposerRow(
                    icon: Icons.repeat_rounded,
                    title: '生成周期',
                    value: recurrenceMonths == 1
                        ? '仅当前 1 个月'
                        : '当前起 $recurrenceMonths 个月',
                    onTap: _pickRecurrenceMonths,
                  )
                else if (widget.draft?.recurringRuleId != null)
                  _ComposerRow(
                    icon: Icons.repeat_rounded,
                    title: '周期规则',
                    value: '由周期计划管理',
                    onTap: () => _showPlannedFeature('请在“周期计划”中修改这条规则'),
                  ),
              ],
              const SizedBox(height: 24),
              if (widget.editExisting) ...[
                OutlinedButton.icon(
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除交易'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FinanceColors.compassOrange,
                    side: const BorderSide(
                      color: FinanceColors.compassOrange,
                    ),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              CompassPrimaryButton(
                label: widget.editExisting ? '保存修改' : '保存交易',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Category> _categoriesForType(TransactionType value) => switch (value) {
        TransactionType.income =>
          repository.categoriesByType(CategoryType.income),
        TransactionType.expense =>
          repository.categoriesByType(CategoryType.expense),
        TransactionType.transfer || TransactionType.adjustment => [
            ...repository.categoriesByType(CategoryType.transfer),
            ...repository.categoriesByType(CategoryType.investment),
          ],
      };

  Account? _account(String? id) {
    for (final item in repository.accounts) {
      if (item.id == id) return item;
    }
    return null;
  }

  Category? _category(String? id) {
    for (final item in repository.categories) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool get _isSameCurrencyTransfer {
    final sourceCurrency = _account(accountId)?.currency;
    final targetCurrency = _account(toAccountId)?.currency;
    if (sourceCurrency == null || targetCurrency == null) return false;
    return sourceCurrency.trim().toUpperCase() ==
        targetCurrency.trim().toUpperCase();
  }

  void _markToAmountEdited() {
    if (!_isAutoSettingToAmount) {
      _toAmountEditedByUser = true;
    }
  }

  void _updateTransferEstimateIfAllowed() {
    _updateTransferEstimate();
  }

  void _updateTransferEstimate({bool force = false}) {
    if (type != TransactionType.transfer || toAccountId == null) return;
    if (!force && _toAmountEditedByUser && !_isSameCurrencyTransfer) return;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || !amount.isFinite) return;
    final sourceCurrency = _account(accountId)?.currency ?? 'MYR';
    final targetCurrency = _account(toAccountId)?.currency ?? sourceCurrency;
    final converted = _isSameCurrencyTransfer
        ? amount
        : repository.convertAmount(
            amount: amount,
            fromCurrency: sourceCurrency,
            toCurrency: targetCurrency,
          );
    _isAutoSettingToAmount = true;
    toAmountController.text = converted.toStringAsFixed(2);
    _isAutoSettingToAmount = false;
    if (mounted) setState(() {});
  }

  String _transferConversionHint() {
    final sourceCurrency = _account(accountId)?.currency ?? 'MYR';
    final targetCurrency = _account(toAccountId)?.currency;
    if (targetCurrency == null) {
      return '选择转入账户后会自动计算到账金额';
    }
    if (_isSameCurrencyTransfer) {
      return '同币种转账 · 转入金额自动与转出金额相同';
    }
    final rate = repository.convertAmount(
      amount: 1,
      fromCurrency: sourceCurrency,
      toCurrency: targetCurrency,
    );
    return '参考汇率 1 $sourceCurrency = ${rate.toStringAsFixed(4)} '
        '$targetCurrency · 可按实际到账金额修改';
  }

  Future<void> _pickAccount() async {
    final value = await _pickFromSheet<Account>(
      title: '选择账户',
      items: repository.accounts,
      label: (item) => '${item.name} · ${item.currency}',
    );
    if (value != null) {
      setState(() {
        accountId = value.id;
        if (toAccountId == value.id) toAccountId = null;
        _toAmountEditedByUser = false;
      });
      _updateTransferEstimate(force: true);
    }
  }

  Future<void> _pickToAccount() async {
    final value = await _pickFromSheet<Account>(
      title: '选择转入账户',
      items: repository.accounts.where((item) => item.id != accountId).toList(),
      label: (item) => '${item.name} · ${item.currency}',
    );
    if (value != null) {
      setState(() {
        toAccountId = value.id;
        _toAmountEditedByUser = false;
      });
      _updateTransferEstimate(force: true);
    }
  }

  Future<void> _pickCategory() async {
    final value = await _pickFromSheet<Category>(
      title: '选择类别',
      items: _categoriesForType(type),
      label: (item) => item.name,
    );
    if (value != null) setState(() => categoryId = value.id);
  }

  Future<void> _applyTemplate() async {
    final templates = repository.transactionTemplates;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有快速模板，请先在规则中心建立。')),
      );
      return;
    }
    final selected = await _pickFromSheet<TransactionTemplate>(
      title: '套用模板',
      items: templates,
      label: (item) =>
          '${item.name} · ${item.currency} ${item.amount.toStringAsFixed(2)}',
    );
    if (selected == null || !mounted) return;
    setState(() {
      type = selected.type;
      status = selected.status;
      accountId = selected.accountId;
      toAccountId = selected.toAccountId;
      categoryId = selected.categoryId;
      amountController.text = selected.amount.toStringAsFixed(2);
      merchantController.text = selected.merchant ?? selected.name;
      noteController.text = selected.description ?? '';
      _toAmountEditedByUser = selected.toAmount != null;
      toAmountController.text = selected.toAmount?.toStringAsFixed(2) ?? '';
    });
    _updateTransferEstimate(
      force: selected.toAmount == null || _isSameCurrencyTransfer,
    );
  }

  void _showPlannedFeature(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<T?> _pickFromSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T item) label,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              ...items.map(
                (item) => ListTile(
                  title: Text(label(item)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, item),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => date = value);
  }

  Future<void> _pickRecurrenceMonths() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择生成周期', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '所有月份都会保持当前选择的“已发生”或“预计”状态。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(12, (index) {
                  final months = index + 1;
                  return ChoiceChip(
                    label: Text('$months 个月'),
                    selected: recurrenceMonths == months,
                    onSelected: (_) => Navigator.pop(sheetContext, months),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      setState(() => recurrenceMonths = value);
    }
  }

  void _submit() {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || !amount.isFinite || accountId == null) return;
    if (type == TransactionType.transfer && toAccountId == null) return;
    final draft = widget.draft;
    final sourceCurrency = _account(accountId)?.currency ?? 'MYR';
    final targetCurrency = _account(toAccountId)?.currency ?? draft?.toCurrency;
    final isSameCurrencyTransfer = type == TransactionType.transfer &&
        sourceCurrency.trim().toUpperCase() ==
            (targetCurrency ?? sourceCurrency).trim().toUpperCase();
    final transferInAmount =
        type == TransactionType.transfer && !isSameCurrencyTransfer
            ? double.tryParse(toAmountController.text.trim())
            : null;
    if (type == TransactionType.transfer &&
        !isSameCurrencyTransfer &&
        (transferInAmount == null || !transferInAmount.isFinite)) {
      return;
    }
    final transaction = FinanceTransaction(
      id: widget.editExisting && draft != null ? draft.id : buildId('txn'),
      type: type,
      accountId: accountId!,
      toAccountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      currency: sourceCurrency,
      // A same-currency transfer has one canonical amount. Keeping a stale
      // quick-template toAmount (especially zero) would make the receiving
      // account diverge from the source account.
      toAmount: transferInAmount,
      toCurrency: targetCurrency,
      recordDate:
          widget.editExisting && draft != null ? draft.recordDate : date,
      transactionDate: date,
      status: status,
      recurringRuleId: widget.editExisting ? draft?.recurringRuleId : null,
      merchant: _emptyToNull(merchantController.text),
      description: _emptyToNull(noteController.text),
    );
    final transactions = widget.editExisting || !widget.allowRecurringGeneration
        ? [transaction]
        : buildRecurringTransactions(
            baseTransaction: transaction,
            months: recurrenceMonths,
          );
    Navigator.of(context)
        .pop(TransactionFormResult(transactions: transactions));
  }

  Future<void> _confirmDelete() async {
    final transactionId = widget.draft?.id;
    if (!widget.editExisting || transactionId == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除交易？'),
            content: const Text('删除后会同步恢复相关账户余额，且无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: FinanceColors.compassOrange,
                ),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(TransactionFormResult.deleted(transactionId));
  }
}

class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.selected, required this.onChanged});

  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = [
      TransactionType.income,
      TransactionType.expense,
      TransactionType.transfer,
      TransactionType.adjustment,
    ];
    const labels = ['收入', '支出', '转账', '调整'];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: FinanceColors.compassBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final active = values[index] == selected;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(values[index]),
              borderRadius: BorderRadius.circular(21),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      active ? FinanceColors.compassOrange : Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: active ? Colors.white : FinanceColors.compassMuted,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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

class _ComposerRow extends StatelessWidget {
  const _ComposerRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
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
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      );
}

class _ComposerInputRow extends StatelessWidget {
  const _ComposerInputRow({
    required this.icon,
    required this.title,
    required this.controller,
    required this.hintText,
  });

  final IconData icon;
  final String title;
  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 50),
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
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
            SizedBox(
              width: 180,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: hintText,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      );
}

String? _emptyToNull(String value) =>
    value.trim().isEmpty ? null : value.trim();

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
