import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/models/transaction.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_amount_field.dart';
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
  bool _showValidation = false;
  final _scrollController = ScrollController();
  final _primaryErrorKey = GlobalKey();
  final _transferErrorKey = GlobalKey();
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
      force: draft?.toAmount == null ||
          (_isSameCurrencyTransfer && !_isStructuredLoanPayment),
    );
    FocusManager.instance.addEarlyKeyEventHandler(_handleSaveShortcut);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleSaveShortcut);
    _scrollController.dispose();
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
    final issue = _showValidation ? _validationIssue() : null;
    final sidePadding =
        math.max(20.0, (MediaQuery.sizeOf(context).width - 840) / 2);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 20),
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
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FinanceAmountField(
                      controller: amountController,
                      onChanged: _refreshValidation,
                      title: type == TransactionType.transfer ? '转出金额' : '金额',
                      showTitle: true,
                      style: TextStyle(
                        color: financePaletteOf(context).seed,
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                        fontFeatures: compassTabularFigures,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '${account?.currency ?? 'MYR'} ',
                        prefixStyle: TextStyle(
                          color: financePaletteOf(context).seed,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          fontFeatures: compassTabularFigures,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickAccount,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    label: Text(account?.currency ?? 'MYR'),
                  ),
                ],
              ),
              if (issue != null && !issue.transferIn)
                _ComposerError(key: _primaryErrorKey, message: issue.message),
              if (type == TransactionType.transfer) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FinanceAmountField(
                        controller: toAmountController,
                        onChanged: _refreshValidation,
                        title: '转入金额',
                        showTitle: true,
                        enabled: toAccountId != null,
                        readOnly: _isSameCurrencyTransfer,
                        style: TextStyle(
                          color: financePaletteOf(context).seed,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          fontFeatures: compassTabularFigures,
                        ),
                        decoration: InputDecoration(
                          prefixText:
                              '${_account(toAccountId)?.currency ?? '---'} ',
                          prefixStyle: TextStyle(
                            color: financePaletteOf(context).seed,
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                            fontFeatures: compassTabularFigures,
                          ),
                          hintText: toAccountId == null ? '先选择账户' : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickToAccount,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      label: Text(_account(toAccountId)?.currency ?? '选择'),
                    ),
                  ],
                ),
                if (issue != null && issue.transferIn)
                  _ComposerError(
                      key: _transferErrorKey, message: issue.message),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CompassHelpHeading(
                          title: Text(
                            _isStructuredLoanPayment ? '本息 → 本金' : '转入金额规则',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          label: '转入金额',
                          message: _transferConversionHint(),
                        ),
                      ),
                    ),
                    if (toAccountId != null &&
                        !_isSameCurrencyTransfer &&
                        !_isStructuredLoanPayment)
                      TextButton(
                        onPressed: () {
                          _toAmountEditedByUser = false;
                          _updateTransferEstimate(force: true);
                        },
                        child: const Text('重新换算'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              CompassSegmentedControl(
                labels: const ['已发生', '预计'],
                selectedIndex: status == TransactionStatus.planned ? 1 : 0,
                onChanged: (index) => setState(() {
                  status = index == 0
                      ? TransactionStatus.actual
                      : TransactionStatus.planned;
                }),
              ),
              if (status == TransactionStatus.planned) ...[
                const SizedBox(height: 6),
                Text('不计入账户余额', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 14),
              const CompassSectionLabel('基本信息'),
              _ComposerRow(
                icon: Icons.account_balance_wallet_outlined,
                title: switch (type) {
                  TransactionType.transfer => '转出账户',
                  TransactionType.income => '收款账户',
                  TransactionType.adjustment => '调整账户',
                  TransactionType.expense => '付款账户',
                },
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
              if (type != TransactionType.transfer) ...[
                _ComposerRow(
                  icon: Icons.sell_outlined,
                  title: '类别',
                  value: category?.name ?? '未分类',
                  onTap: _pickCategory,
                ),
                if (_categoriesForType(type).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final item in _categoriesForType(type).take(6))
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                key: Key('composer-quick-category-${item.id}'),
                                label: Text(item.name),
                                selected: categoryId == item.id,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 0,
                                ),
                                onSelected: (_) =>
                                    setState(() => categoryId = item.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
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
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in _quickDateOptions())
                      ChoiceChip(
                        key: Key('composer-quick-date-${entry.key}'),
                        label: Text(entry.label),
                        selected: DateUtils.isSameDay(date, entry.date),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                        onSelected: (_) => setState(() {
                          date = DateTime(
                            entry.date.year,
                            entry.date.month,
                            entry.date.day,
                            date.hour,
                            date.minute,
                          );
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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
                    value: '请在规则中心修改',
                  ),
              ],
              const SizedBox(height: 14),
              if (widget.editExisting) ...[
                OutlinedButton.icon(
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除交易'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: financePaletteOf(context).expense,
                    side: BorderSide(
                      color: financePaletteOf(context).expense,
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

  bool get _isStructuredLoanPayment {
    final draft = widget.draft;
    return draft != null &&
        type == TransactionType.transfer &&
        draft.type == TransactionType.transfer &&
        // Keep the principal from the installment when its payer changes.
        draft.toAccountId == toAccountId &&
        _account(toAccountId)?.accountType == AccountType.loan &&
        draft.toAmount != null &&
        RegExp(r'^贷款月供 #\d+$').hasMatch(draft.description ?? '');
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
    if (_isStructuredLoanPayment) return;
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
    if (_isStructuredLoanPayment) {
      return '贷款月供 · 转出为本息合计，转入仅偿还本金';
    }
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

  List<({String key, String label, DateTime date})> _quickDateOptions() {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    return [
      if (status == TransactionStatus.planned)
        (
          key: 'tomorrow',
          label: '明天',
          date: today.add(const Duration(days: 1))
        ),
      (key: 'today', label: '今天', date: today),
      (
        key: 'yesterday',
        label: '昨天',
        date: today.subtract(const Duration(days: 1)),
      ),
      (
        key: 'two-days-ago',
        label: '前天',
        date: today.subtract(const Duration(days: 2)),
      ),
    ];
  }

  Future<void> _pickAccount() async {
    final value = await _pickFromSheet<Account>(
      title: '选择账户',
      items: repository.accounts,
      selected: _account(accountId),
      label: (item) => '${item.name} · ${item.currency}',
      subtitle: (item) =>
          '当前余额 ${compassMoney(item.currentBalance, currency: item.currency)}',
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
      selected: _account(toAccountId),
      label: (item) => '${item.name} · ${item.currency}',
      subtitle: (item) =>
          '当前余额 ${compassMoney(item.currentBalance, currency: item.currency)}',
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
      selected: _category(categoryId),
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

  Future<T?> _pickFromSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T item) label,
    String Function(T item)? subtitle,
    T? selected,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final palette = financePaletteOf(context);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...items.map((item) {
                  final isSelected = selected != null && selected == item;
                  return ListTile(
                    title: Text(label(item)),
                    subtitle: subtitle == null
                        ? null
                        : Text(
                            subtitle(item),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFeatures: compassTabularFigures),
                          ),
                    trailing: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.chevron_right_rounded,
                      color: isSelected ? palette.seed : palette.textMuted,
                    ),
                    onTap: () => Navigator.pop(context, item),
                  );
                }),
              ],
            ),
          );
        },
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
              CompassHelpHeading(
                title: Text(
                  '选择生成周期',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                label: '生成周期',
                message: '所有月份都会保持当前选择的「已发生」或「预计」状态。',
              ),
              Text(
                status == TransactionStatus.planned ? '生成状态 预计' : '生成状态 已发生',
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

  KeyEventResult _handleSaveShortcut(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        (!keyboard.isControlPressed && !keyboard.isMetaPressed) ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        !mounted ||
        !TickerMode.of(context) ||
        ModalRoute.of(context)?.isCurrent != true ||
        _isComposing(merchantController) ||
        _isComposing(noteController)) {
      return KeyEventResult.ignored;
    }
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator != navigator && rootNavigator.canPop()) {
      return KeyEventResult.ignored;
    }
    _submit();
    return KeyEventResult.handled;
  }

  bool _isComposing(TextEditingController controller) {
    final value = controller.value;
    return value.isComposingRangeValid && !value.composing.isCollapsed;
  }

  void _refreshValidation(String _) {
    if (_showValidation) setState(() {});
  }

  ({bool transferIn, String message})? _validationIssue() {
    final transfer = type == TransactionType.transfer;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || !amount.isFinite) {
      return (
        transferIn: false,
        message: transfer ? '请输入有效的转出金额' : '请输入有效的金额',
      );
    }
    if (_account(accountId) == null) {
      return (
        transferIn: false,
        message: transfer ? '请选择转出账户' : '请选择账户',
      );
    }
    if (!transfer) return null;
    if (_account(toAccountId) == null) {
      return (transferIn: true, message: '请选择转入账户');
    }
    if (!_isSameCurrencyTransfer || _isStructuredLoanPayment) {
      final transferAmount = double.tryParse(toAmountController.text.trim());
      if (transferAmount == null || !transferAmount.isFinite) {
        return (transferIn: true, message: '请输入有效的转入金额');
      }
    }
    return null;
  }

  void _revealValidationError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final issue = _validationIssue();
      if (issue == null) return;
      final key = issue.transferIn ? _transferErrorKey : _primaryErrorKey;
      if (key.currentContext case final errorContext?) {
        unawaited(Scrollable.ensureVisible(
          errorContext,
          alignment: .25,
          duration: const Duration(milliseconds: 180),
        ));
      } else if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ));
      }
    });
  }

  void _submit() {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (_validationIssue() != null) {
      setState(() => _showValidation = true);
      _revealValidationError();
      return;
    }
    final amount = double.parse(amountController.text.trim());
    final draft = widget.draft;
    final sourceCurrency = _account(accountId)?.currency ?? 'MYR';
    final targetCurrency = _account(toAccountId)?.currency ?? draft?.toCurrency;
    final isSameCurrencyTransfer = type == TransactionType.transfer &&
        sourceCurrency.trim().toUpperCase() ==
            (targetCurrency ?? sourceCurrency).trim().toUpperCase();
    final transferInAmount = type == TransactionType.transfer &&
            (!isSameCurrencyTransfer || _isStructuredLoanPayment)
        ? double.parse(toAmountController.text.trim())
        : null;
    final transaction = FinanceTransaction(
      id: widget.editExisting && draft != null ? draft.id : buildId('txn'),
      type: type,
      accountId: accountId!,
      toAccountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      currency: sourceCurrency,
      // Normal same-currency transfers have one canonical amount. Loan
      // payments are the deliberate exception: amount is the full cash
      // payment while toAmount is only the principal reduction.
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
                  backgroundColor: financePaletteOf(dialogContext).expense,
                  foregroundColor: financeForegroundOn(
                      financePaletteOf(dialogContext).expense),
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

class _ComposerError extends StatelessWidget {
  const _ComposerError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
}

class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.selected, required this.onChanged});

  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    const values = [
      TransactionType.income,
      TransactionType.expense,
      TransactionType.transfer,
      TransactionType.adjustment,
    ];
    const labels = ['收入', '支出', '转账', '调整'];
    Color activeColorFor(TransactionType value) => switch (value) {
          TransactionType.income => palette.income,
          TransactionType.expense => palette.expense,
          TransactionType.transfer ||
          TransactionType.adjustment =>
            palette.seed,
        };
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final active = values[index] == selected;
          final fillColor = activeColorFor(values[index]);
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(values[index]),
              borderRadius: BorderRadius.circular(21),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? fillColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: active
                        ? financeForegroundOn(fillColor)
                        : palette.textMuted,
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: 50),
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
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
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
          ],
        ),
      );
}

String? _emptyToNull(String value) =>
    value.trim().isEmpty ? null : value.trim();

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
