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
import '../shared/card_posting_date_field.dart';
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
    this.isPresetDefinition = false,
  });

  final FinanceRepository repository;
  final FinanceTransaction? draft;
  final bool editExisting;
  final String? title;
  final bool allowRecurringGeneration;
  final bool isPresetDefinition;

  @override
  State<TransactionComposerPage> createState() =>
      _TransactionComposerPageState();
}

class _TransactionComposerPageState extends State<TransactionComposerPage> {
  late TransactionType type;
  late TransactionStatus status;
  late DateTime date;
  DateTime? cardPostingDate;
  late String? accountId;
  late String? toAccountId;
  int? loanInstallmentNumber;
  LoanInstallmentFields? _unallocatedSplit;
  bool _editingUnallocatedAmounts = false;
  late String? categoryId;
  late final TextEditingController amountController;
  late final TextEditingController toAmountController;
  late final TextEditingController loanPaymentController;
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

  FinanceRepository get repository =>
      currentEntryLedger(context, widget.repository);
  List<Account> _entryAccounts({bool target = false}) {
    final original = widget.editExisting ? widget.draft : null;
    return repository.entryAccounts(
        originalAccountId:
            target ? original?.toAccountId : original?.accountId);
  }

  String get _sourceCurrency =>
      _account(accountId)?.currency ?? repository.baseCurrency;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    type = draft?.type ?? TransactionType.expense;
    status = draft?.status ?? TransactionStatus.actual;
    date = draft?.transactionDate ?? DateTime.now();
    cardPostingDate = widget.editExisting ? draft?.cardPostingDate : null;
    accountId = draft == null
        ? _entryAccounts().firstOrNull?.id
        : _entryAccounts()
            .where((a) => a.id == draft.accountId)
            .firstOrNull
            ?.id;
    toAccountId = type == TransactionType.transfer
        ? _entryAccounts(target: true)
            .where((a) => a.id == draft?.toAccountId)
            .firstOrNull
            ?.id
        : null;
    loanInstallmentNumber = draft?.loanInstallmentNumber;
    _unallocatedSplit =
        hasUnallocatedLoanSplit(draft, repository) ? draft : null;
    categoryId = _draftCategory(type, draft?.categoryId,
        keepOriginal: widget.editExisting, newEntry: draft == null);
    final amount = draft?.amount ?? 0;
    amountController = TextEditingController(
      text: draft == null ? '' : amount.toStringAsFixed(2),
    );
    toAmountController = TextEditingController(
      text: draft?.toAmount?.toStringAsFixed(2) ?? '',
    );
    _toAmountEditedByUser = draft?.toAmount != null;
    loanPaymentController = TextEditingController(
      text: draft?.loanPaymentAmount?.toStringAsFixed(2) ?? '',
    );
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
    loanPaymentController.dispose();
    merchantController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      watchEntryLedger(context, widget.repository, _buildForm);

  Widget _buildForm(BuildContext context) {
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
                onChanged: _isStructuredLoanPayment || _unallocatedSplit != null
                    ? null
                    : (value) {
                        if (value == type) return;
                        setState(() {
                          type = value;
                          categoryId =
                              _draftCategory(value, null, newEntry: true);
                          if (value != TransactionType.transfer) {
                            toAccountId = null;
                            toAmountController.clear();
                            loanPaymentController.clear();
                          }
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
                      readOnly: _unallocatedSplit != null &&
                          !_editingUnallocatedAmounts,
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
                        prefixText: '$_sourceCurrency ',
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
                    onPressed: _unallocatedSplit == null ? _pickAccount : null,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    label: Text(_sourceCurrency),
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
                        title: _isStructuredLoanPayment ? '偿还本金' : '转入金额',
                        showTitle: true,
                        enabled: toAccountId != null,
                        readOnly: _unallocatedSplit != null
                            ? !_editingUnallocatedAmounts
                            : _isSameCurrencyTransfer &&
                                !_isStructuredLoanPayment,
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
                      onPressed:
                          _isStructuredLoanPayment || _unallocatedSplit != null
                              ? null
                              : _pickToAccount,
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
                if (_unallocatedSplit != null)
                  Row(children: [
                    const Expanded(child: Text('未关联贷款期号，保留原始付款与到账金额。')),
                    if (!_editingUnallocatedAmounts)
                      TextButton(
                          onPressed: () =>
                              setState(() => _editingUnallocatedAmounts = true),
                          child: const Text('核对并修改金额')),
                  ]),
                if (_isStructuredLoanPayment && !_isSameCurrencyTransfer)
                  FinanceAmountField(
                    key:
                        const Key('composer-loan-payment-in-contract-currency'),
                    controller: loanPaymentController,
                    title: '贷款原币还款总额',
                    showTitle: true,
                    onChanged: _refreshValidation,
                    decoration: InputDecoration(
                      prefixText: '${_account(toAccountId)?.currency ?? ''} ',
                    ),
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
                        !_missingTransferRate &&
                        !_isStructuredLoanPayment &&
                        _unallocatedSplit == null)
                      TextButton(
                        onPressed: () {
                          _toAmountEditedByUser = false;
                          _updateTransferEstimate(force: true);
                        },
                        child: const Text('重新换算'),
                      ),
                  ],
                ),
                if (_missingTransferRate && _unallocatedSplit == null)
                  Text(_isStructuredLoanPayment
                      ? '缺少汇率，请输入付款账户的实际扣款'
                      : '缺少汇率，请输入实际到账金额'),
              ],
              const SizedBox(height: 10),
              CompassSegmentedControl(
                labels: const ['已发生', '预计'],
                selectedIndex: status == TransactionStatus.planned ? 1 : 0,
                onChanged: (index) => _changeStatus(
                  index == 0
                      ? TransactionStatus.actual
                      : TransactionStatus.planned,
                ),
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
                onTap: _unallocatedSplit == null ? _pickAccount : null,
              ),
              if (type == TransactionType.transfer)
                _ComposerRow(
                  icon: Icons.call_received_rounded,
                  title: '转入账户',
                  value: _isStructuredLoanPayment
                      ? '${_account(toAccountId)?.name ?? ''} · 第 $loanInstallmentNumber 期'
                      : _account(toAccountId)?.name ?? '请选择账户',
                  onTap: _isStructuredLoanPayment || _unallocatedSplit != null
                      ? null
                      : _pickToAccount,
                ),
              if (type != TransactionType.transfer || categoryId != null) ...[
                _ComposerRow(
                  icon: Icons.sell_outlined,
                  title: '类别',
                  value: category == null ? '未分类' : _categoryLabel(category),
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
                                label: Text(_categoryLabel(item)),
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
                        onSelected: (_) => _setDate(DateTime(
                          entry.date.year,
                          entry.date.month,
                          entry.date.day,
                          date.hour,
                          date.minute,
                        )),
                      ),
                  ],
                ),
              ),
              if (!widget.isPresetDefinition &&
                  account != null &&
                  account.accountType == AccountType.creditCard)
                CardPostingDateField(
                  source: account,
                  transactionDate: date,
                  value: cardPostingDate,
                  onChanged: (value) => setState(() => cardPostingDate = value),
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
                if (_isStructuredLoanPayment &&
                    !widget.editExisting &&
                    widget.allowRecurringGeneration &&
                    recurrenceMonths > 1)
                  Text(
                      '这 $recurrenceMonths 笔还款均计入第 $loanInstallmentNumber 期。跨期月供可在贷款详情按合同生成。'),
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

  List<Category> _categoriesForType(TransactionType value) =>
      entryCategoryOptions(context, repository, value,
          originalCategoryId: widget.editExisting && widget.draft?.type == value
              ? widget.draft?.categoryId
              : null);

  String? _draftCategory(TransactionType value, String? id,
      {bool keepOriginal = false, bool newEntry = false}) {
    final options = entryCategoryOptions(context, repository, value,
        originalCategoryId: keepOriginal ? id : null);
    if (id != null && options.any((item) => item.id == id)) return id;
    if (value == TransactionType.transfer || (!newEntry && id == null)) {
      return null;
    }
    return options.firstOrNull?.id;
  }

  Account? _account(String? id) {
    for (final item in repository.accounts) {
      if (item.id == id) return item;
    }
    return null;
  }

  Category? _category(String? id) {
    for (final item in _categoriesForType(type)) {
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

  bool get _isStructuredLoanPayment => loanInstallmentNumber != null;

  String _categoryLabel(Category value) =>
      value.isArchived ? '${value.name}（已归档）' : value.name;

  bool get _missingTransferRate {
    final target = _account(toAccountId);
    return target != null &&
        !_isSameCurrencyTransfer &&
        repository.tryConvertAmount(
                amount: 1,
                fromCurrency: _sourceCurrency,
                toCurrency: target.currency) ==
            null;
  }

  double? get _loanPayment => double.tryParse(
      (_isSameCurrencyTransfer ? amountController : loanPaymentController)
          .text
          .trim());

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
    if (_isStructuredLoanPayment || _unallocatedSplit != null) return;
    if (!force && _toAmountEditedByUser && !_isSameCurrencyTransfer) return;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || !amount.isFinite) return;
    final sourceCurrency = _sourceCurrency;
    final targetCurrency = _account(toAccountId)?.currency ?? sourceCurrency;
    final converted = _isSameCurrencyTransfer
        ? amount
        : repository.tryConvertAmount(
            amount: amount,
            fromCurrency: sourceCurrency,
            toCurrency: targetCurrency,
          );
    _isAutoSettingToAmount = true;
    toAmountController.text = converted?.toStringAsFixed(2) ?? '';
    _isAutoSettingToAmount = false;
    if (mounted) setState(() {});
  }

  String _transferConversionHint() {
    if (_unallocatedSplit != null) return '这笔转账保留两端原币金额，尚未分配到合同期次。';
    if (_isStructuredLoanPayment) {
      return '贷款月供 · 转出为本息合计，转入仅偿还本金';
    }
    final sourceCurrency = _sourceCurrency;
    final targetCurrency = _account(toAccountId)?.currency;
    if (targetCurrency == null) {
      return '选择转入账户后会自动计算到账金额';
    }
    if (_isSameCurrencyTransfer) {
      return '同币种转账 · 转入金额自动与转出金额相同';
    }
    final rate = repository.tryConvertAmount(
      amount: 1,
      fromCurrency: sourceCurrency,
      toCurrency: targetCurrency,
    );
    if (rate == null) return '缺少汇率，请输入实际到账金额';
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

  String _accountBalanceLabel(Account account) {
    final cutoff = repository.currentMonthCutoffDate();
    final balance = repository.accountBalanceAt(account.id, cutoff);
    final isDebtAccount = account.accountType == AccountType.creditCard ||
        account.accountType == AccountType.loan;
    final debt = isDebtAccount && balance < 0;
    final monthEnd = '${debt ? '本月末欠款' : '本月末余额'} '
        '${compassMoney(debt ? -balance : balance, currency: account.currency)}';
    if (account.accountType != AccountType.creditCard ||
        (account.currentBalance - balance).abs() < .005) {
      return monthEnd;
    }
    final committed = account.currentBalance;
    return '$monthEnd\n${committed < 0 ? '含未来承诺欠款' : '含未来承诺余额'} '
        '${compassMoney(committed.abs(), currency: account.currency)}';
  }

  List<Account> _sourceChoices() => _entryAccounts()
      .where((a) => !_isStructuredLoanPayment || a.id != toAccountId)
      .toList();

  List<Account> _targetChoices() =>
      _entryAccounts(target: true).where((a) => a.id != accountId).toList();

  Future<void> _pickAccount() async {
    final value = await _pickFromSheet<Account>(
      title: '选择账户',
      items: _sourceChoices,
      selected: _account(accountId),
      label: (item) => '${item.name} · ${item.currency}',
      subtitle: _accountBalanceLabel,
    );
    if (mounted && value != null) {
      final oldCurrency = _sourceCurrency;
      final loanPayment = _isStructuredLoanPayment ? _loanPayment : null;
      setState(() {
        accountId = value.id;
        if (value.accountType != AccountType.creditCard) cardPostingDate = null;
        if (toAccountId == value.id) toAccountId = null;
        final loanCurrency = _account(toAccountId)?.currency;
        if (loanPayment != null &&
            loanCurrency != null &&
            oldCurrency != value.currency) {
          loanPaymentController.text = loanPayment.toStringAsFixed(2);
          amountController.text = repository
                  .tryConvertAmount(
                    amount: loanPayment,
                    fromCurrency: loanCurrency,
                    toCurrency: value.currency,
                  )
                  ?.toStringAsFixed(2) ??
              '';
        }
        _toAmountEditedByUser = false;
      });
      _updateTransferEstimate(force: true);
    }
  }

  Future<void> _pickToAccount() async {
    final value = await _pickFromSheet<Account>(
      title: '选择转入账户',
      items: _targetChoices,
      selected: _account(toAccountId),
      label: (item) => '${item.name} · ${item.currency}',
      subtitle: _accountBalanceLabel,
    );
    if (mounted && value != null) {
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
      items: () => _categoriesForType(type),
      selected: _category(categoryId),
      label: _categoryLabel,
    );
    if (value != null) setState(() => categoryId = value.id);
  }

  Future<void> _applyTemplate() async {
    final lockedInstallment = widget.editExisting && _isStructuredLoanPayment;
    final matchLoan = widget.editExisting && _unallocatedSplit != null;
    List<TransactionTemplate> availableTemplates() =>
        repository.transactionTemplates.where((template) {
          if (!lockedInstallment && !matchLoan) return true;
          return template.toAccountId == toAccountId &&
              template.loanInstallmentNumber != null &&
              (!lockedInstallment ||
                  template.loanInstallmentNumber == loanInstallmentNumber);
        }).toList();
    if (availableTemplates().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(lockedInstallment || matchLoan
                ? '没有与这笔还款匹配的贷款分期模板。'
                : '还没有快速模板，请先在规则中心建立。')),
      );
      return;
    }
    final selected = await _pickFromSheet<TransactionTemplate>(
      title: '套用模板',
      items: availableTemplates,
      label: (item) =>
          '${item.name} · ${item.currency} ${item.amount.toStringAsFixed(2)}',
    );
    if (selected == null || !mounted) return;
    setState(() {
      type = selected.type;
      status = selected.status;
      cardPostingDate = null;
      accountId = _entryAccounts()
          .where((a) => a.id == selected.accountId)
          .firstOrNull
          ?.id;
      toAccountId = selected.type == TransactionType.transfer
          ? _entryAccounts(target: true)
              .where((a) => a.id == selected.toAccountId)
              .firstOrNull
              ?.id
          : null;
      loanInstallmentNumber = selected.loanInstallmentNumber;
      _unallocatedSplit =
          hasUnallocatedLoanSplit(selected, repository) ? selected : null;
      _editingUnallocatedAmounts = false;
      loanPaymentController.text =
          selected.loanPaymentAmount?.toStringAsFixed(2) ?? '';
      categoryId = _draftCategory(type, selected.categoryId);
      amountController.text = selected.amount.toStringAsFixed(2);
      merchantController.text = selected.merchant ?? '';
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
    required List<T> Function() items,
    required String Function(T item) label,
    String Function(T item)? subtitle,
    T? selected,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        builder: (context) =>
            watchEntryLedger(context, widget.repository, (context) {
          final palette = financePaletteOf(context);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...items().map((item) {
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
        }),
      );

  Future<void> _changeStatus(TransactionStatus next) async {
    final chosen = await dateForLoanStatusChange(
      context,
      original: widget.editExisting && !widget.isPresetDefinition
          ? widget.draft
          : null,
      type: type,
      toAccountId: toAccountId,
      before: status,
      after: next,
      date: date,
    );
    if (!mounted || chosen == null) return;
    setState(() {
      status = next;
      date = chosen;
    });
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) _setDate(value);
  }

  void _setDate(DateTime value) {
    setState(() {
      date = value;
      if (cardPostingDate?.isBefore(DateUtils.dateOnly(value)) == true) {
        cardPostingDate = null;
      }
    });
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
    if (!_entryAccounts().any((a) => a.id == accountId)) {
      return (
        transferIn: false,
        message: accountId != null
            ? '所选账户已停用或移除，请重新选择启用的账户'
            : (transfer ? '请选择转出账户' : '请选择账户'),
      );
    }
    if (!transfer) return null;
    if (!_entryAccounts(target: true).any((a) => a.id == toAccountId)) {
      return (
        transferIn: true,
        message: _isStructuredLoanPayment
            ? '贷款账户已停用或移除，请启用后再记账'
            : (toAccountId != null ? '转入账户已停用或移除，请重新选择启用的账户' : '请选择转入账户')
      );
    }
    if (_isStructuredLoanPayment) {
      if (accountId == toAccountId ||
          _account(toAccountId)!.accountType != AccountType.loan) {
        return (transferIn: true, message: '贷款月供需要转入对应的贷款账户');
      }
      final principal = double.tryParse(toAmountController.text.trim());
      if (!validLoanInstallmentAmounts(amount, principal,
          loanPaymentAmount: _loanPayment,
          sameCurrency: _isSameCurrencyTransfer)) {
        return (
          transferIn: true,
          message: '还款金额须非零，本金可为零。还款与冲正各项须同号，本金不能超过贷款原币还款总额'
        );
      }
    }
    if (!_isSameCurrencyTransfer ||
        _isStructuredLoanPayment ||
        _unallocatedSplit != null) {
      final transferAmount = double.tryParse(toAmountController.text.trim());
      if (transferAmount == null || !transferAmount.isFinite) {
        return (transferIn: true, message: '请输入有效的转入金额');
      }
      if (_unallocatedSplit != null &&
          _editingUnallocatedAmounts &&
          (amount == 0 ||
              transferAmount == 0 ||
              amount.isNegative != transferAmount.isNegative ||
              (_isSameCurrencyTransfer &&
                  transferAmount.abs() > amount.abs()))) {
        return (transferIn: true, message: '请核对未分期转账的两端金额及符号');
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
    if (categoryId != null && _category(categoryId) == null) {
      setState(() => categoryId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选类别已变更，请重新选择类别或确认为未分类。')),
      );
      return;
    }
    if (_validationIssue() != null) {
      setState(() => _showValidation = true);
      _revealValidationError();
      return;
    }
    final unchangedSplit =
        _editingUnallocatedAmounts ? null : _unallocatedSplit;
    final amount =
        unchangedSplit?.amount ?? double.parse(amountController.text.trim());
    final draft = widget.draft;
    final sourceCurrency = _sourceCurrency;
    final targetCurrency = type == TransactionType.transfer
        ? _account(toAccountId)?.currency
        : null;
    final keepLegacyLink = widget.editExisting &&
        draft?.type == type &&
        draft?.toAccountId == toAccountId &&
        !_isStructuredLoanPayment;
    final isSameCurrencyTransfer = type == TransactionType.transfer &&
        sourceCurrency.trim().toUpperCase() ==
            (targetCurrency ?? sourceCurrency).trim().toUpperCase();
    final transferInAmount = unchangedSplit?.toAmount ??
        (type == TransactionType.transfer &&
                (!isSameCurrencyTransfer ||
                    _isStructuredLoanPayment ||
                    _unallocatedSplit != null)
            ? double.parse(toAmountController.text.trim())
            : null);
    final transaction = FinanceTransaction(
      id: widget.editExisting && draft != null ? draft.id : buildId('txn'),
      type: type,
      accountId: accountId!,
      toAccountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      currency: _unallocatedSplit?.currency ?? sourceCurrency,
      // Normal same-currency transfers have one canonical amount. Loan
      // payments are the deliberate exception: amount is the full cash
      // payment while toAmount is only the principal reduction.
      toAmount: transferInAmount,
      loanInstallmentNumber: loanInstallmentNumber,
      legacyLoanPartNumber: keepLegacyLink ? draft?.legacyLoanPartNumber : null,
      legacyLoanId: keepLegacyLink ? draft?.legacyLoanId : null,
      loanPaymentAmount: _isStructuredLoanPayment && !isSameCurrencyTransfer
          ? _loanPayment
          : null,
      toCurrency: _unallocatedSplit == null
          ? targetCurrency
          : _unallocatedSplit!.toCurrency,
      recordDate:
          widget.editExisting && draft != null ? draft.recordDate : date,
      transactionDate: date,
      cardPostingDate:
          _account(accountId)?.accountType == AccountType.creditCard
              ? cardPostingDate
              : null,
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
  final ValueChanged<TransactionType>? onChanged;

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
              onTap: onChanged == null ? null : () => onChanged!(values[index]),
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
