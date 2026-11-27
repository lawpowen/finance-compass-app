import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/category.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/anchored_month.dart';
import '../../core/utils/id_generator.dart';
import '../shared/card_posting_date_field.dart';
import '../shared/finance_form_fields.dart';

/// Retain the editing session's database when a standalone form is supplied.
FinanceRepository currentEntryLedger(
    BuildContext context, FinanceRepository ledger) {
  final scope =
      context.getInheritedWidgetOfExactType<UncontrolledProviderScope>();
  if (scope != null && scope.container.exists(financeRepositoryProvider)) {
    final latest = scope.container.read(financeRepositoryProvider).valueOrNull;
    if (latest != null && identical(latest.database, ledger.database)) {
      return latest;
    }
  }
  return ledger;
}

Widget watchEntryLedger(
    BuildContext context, FinanceRepository ledger, WidgetBuilder build) {
  final scope =
      context.getInheritedWidgetOfExactType<UncontrolledProviderScope>();
  if (scope == null || !scope.container.exists(financeRepositoryProvider)) {
    return build(context);
  }
  final current = scope.container.read(financeRepositoryProvider).valueOrNull;
  if (current != null && !identical(current.database, ledger.database)) {
    return build(context);
  }
  return Consumer(builder: (context, ref, _) {
    ref.watch(financeRepositoryProvider);
    return build(context);
  });
}

List<Category> entryCategoryOptions(
        BuildContext context, FinanceRepository ledger, TransactionType type,
        {String? originalCategoryId}) =>
    currentEntryLedger(context, ledger).transactionCategoryOptions(type,
        originalCategoryId: originalCategoryId);

/// Older loan transfers can contain a real principal leg without enough
/// evidence to allocate it to a particular contractual installment.
bool hasUnallocatedLoanSplit(
    LoanInstallmentFields? entry, FinanceRepository repository) {
  if (entry == null ||
      entry.loanInstallmentNumber != null ||
      (entry is FinanceTransaction && entry.legacyLoanPartNumber != null) ||
      entry.type != TransactionType.transfer ||
      entry.toAmount == null) {
    return false;
  }
  final target =
      repository.accounts.where((a) => a.id == entry.toAccountId).firstOrNull;
  if (target == null || target.accountType != AccountType.loan) return false;
  return entry.toAmount != entry.amount || entry.currency != target.currency;
}

/// A future actual is already booked but cannot settle an installment today.
/// Keep the selected day unless the user confirms an early payment.
Future<DateTime?> dateForLoanStatusChange(
  BuildContext context, {
  required FinanceTransaction? original,
  required TransactionType type,
  required String? toAccountId,
  required TransactionStatus before,
  required TransactionStatus after,
  required DateTime date,
}) async {
  final today = DateUtils.dateOnly(DateTime.now());
  if (original == null ||
      original.status != TransactionStatus.planned ||
      before != TransactionStatus.planned ||
      after != TransactionStatus.actual ||
      original.type != type ||
      original.toAccountId != toAccountId ||
      (original.loanInstallmentNumber == null &&
          original.legacyLoanPartNumber == null) ||
      !DateUtils.dateOnly(date).isAfter(today)) {
    return date;
  }
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认还款日期'),
      content: Text('原交易日期为 ${date.year}年${date.month}月${date.day}日。'
          '保留原日期，这笔还款会在当天计入对应期次。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, date),
          child: const Text('保留原日期'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, today),
          child: const Text('今天已还'),
        ),
      ],
    ),
  );
}

/// Legacy layout retained for compatibility; the active UI uses TransactionComposerPage.
class TransactionFormDialog extends StatefulWidget {
  const TransactionFormDialog({
    super.key,
    required this.repository,
    this.initialTransaction,
    this.draftTransaction,
  });

  final FinanceRepository repository;
  final FinanceTransaction? initialTransaction;
  final FinanceTransaction? draftTransaction;

  @override
  State<TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<TransactionFormDialog> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final toAmountController = TextEditingController();
  final loanPaymentController = TextEditingController();
  final descriptionController = TextEditingController();
  final merchantController = TextEditingController();

  TransactionType transactionType = TransactionType.expense;
  TransactionStatus transactionStatus = TransactionStatus.actual;
  late String currency;
  late String toCurrency;
  DateTime recordDate = DateTime.now();
  DateTime? cardPostingDate;
  DateTime? settlementDate;
  String? accountId;
  String? toAccountId;
  String? categoryId;
  int recurrenceMonths = 1;
  bool _isAutoSettingToAmount = false;
  bool _toAmountEditedByUser = false;

  FinanceRepository get _ledger =>
      currentEntryLedger(context, widget.repository);

  bool get _isEditing => widget.initialTransaction != null;

  Account? get _source =>
      _ledger.accounts.where((a) => a.id == accountId).firstOrNull;

  FinanceTransaction? get _seed =>
      widget.initialTransaction ?? widget.draftTransaction;
  bool get _isInstallment => _seed?.loanInstallmentNumber != null;
  bool get _keepUnallocatedSplit => hasUnallocatedLoanSplit(_seed, _ledger);
  double? get _loanPayment => double.tryParse(
      (currency == toCurrency ? amountController : loanPaymentController)
          .text
          .trim());

  bool get _usesCreditCardAccount {
    final creditCardIds = _ledger.accounts
        .where((item) => item.accountType == AccountType.creditCard)
        .map((item) => item.id)
        .toSet();
    return creditCardIds.contains(accountId) ||
        (toAccountId != null && creditCardIds.contains(toAccountId));
  }

  @override
  void initState() {
    super.initState();
    currency = widget.repository.baseCurrency;
    toCurrency = currency;
    final initialTransaction = widget.initialTransaction;
    final draftTransaction = widget.draftTransaction;
    final seedTransaction = initialTransaction ?? draftTransaction;
    if (seedTransaction != null) {
      transactionType = seedTransaction.type;
      transactionStatus = seedTransaction.status == TransactionStatus.settled
          ? TransactionStatus.actual
          : seedTransaction.status;
      recordDate = initialTransaction == null
          ? DateTime.now()
          : seedTransaction.recordDate;
      settlementDate =
          initialTransaction == null ? null : seedTransaction.transactionDate;
      accountId = seedTransaction.accountId;
      toAccountId = transactionType == TransactionType.transfer
          ? seedTransaction.toAccountId
          : null;
      if (_usesCreditCardAccount) {
        if (initialTransaction != null) {
          recordDate = seedTransaction.transactionDate;
        }
        settlementDate = null;
      }
      cardPostingDate = initialTransaction?.cardPostingDate;
      categoryId = seedTransaction.categoryId;
      amountController.text = seedTransaction.amount.toString();
      currency = normalizeCurrency(seedTransaction.currency);
      toAmountController.text = seedTransaction.toAmount?.toString() ?? '';
      loanPaymentController.text =
          seedTransaction.loanPaymentAmount?.toString() ?? '';
      toCurrency = normalizeCurrency(
        seedTransaction.toCurrency ?? seedTransaction.transferInCurrency,
      );
      _toAmountEditedByUser = seedTransaction.toAmount != null;
      descriptionController.text = seedTransaction.description ?? '';
      merchantController.text = seedTransaction.merchant ?? '';
    }

    final accountOptions = _sortedAccounts();
    if (seedTransaction != null && !_isEditing) {
      if (!accountOptions.any((a) => a.id == accountId)) accountId = null;
      if (!_sortedAccounts(target: true).any((a) => a.id == toAccountId)) {
        toAccountId = null;
      }
    }
    if (seedTransaction == null && accountOptions.isNotEmpty) {
      accountId = _preferredAccountId(accountOptions);
      currency = _currencyForAccount(accountId!) ?? currency;
    }
    if (accountId != null) {
      currency = _currencyForAccount(accountId!) ?? currency;
    }
    if (toAccountId != null) {
      toCurrency = _currencyForAccount(toAccountId!) ?? toCurrency;
    }
    _syncCategoryDefault(newEntry: seedTransaction == null);
    amountController.addListener(_updateTransferEstimateIfAllowed);
    toAmountController.addListener(_markToAmountEdited);
    _updateTransferEstimate(force: toAmountController.text.trim().isEmpty);
  }

  @override
  void dispose() {
    amountController.dispose();
    toAmountController.dispose();
    loanPaymentController.dispose();
    descriptionController.dispose();
    merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      watchEntryLedger(context, widget.repository, _buildForm);

  Widget _buildForm(BuildContext context) {
    final source = _source;
    final accountOptions = _sortedAccounts()
        .where((a) => !_isInstallment || a.id != toAccountId)
        .toList();
    final targetOptions = _sortedAccounts(target: true)
        .where((a) =>
            a.id != accountId ||
            (_isEditing &&
                _seed!.accountId == _seed!.toAccountId &&
                a.id == _seed!.toAccountId))
        .toList();
    final categoryOptions = _categoryOptions();

    return AlertDialog(
      title: Text(_isEditing ? '编辑交易' : '新增交易'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TransactionType>(
                  value: transactionType,
                  decoration: const InputDecoration(
                    labelText: '交易类型',
                    border: OutlineInputBorder(),
                  ),
                  items: TransactionType.values
                      .map((type) => DropdownMenuItem(
                          value: type, child: Text(_typeLabel(type))))
                      .toList(),
                  onChanged: _isInstallment || _keepUnallocatedSplit
                      ? null
                      : (value) {
                          if (value == null || value == transactionType) {
                            return;
                          }
                          setState(() {
                            final wasCard = _usesCreditCardAccount;
                            transactionType = value;
                            toAccountId = null;
                            _syncDateFields(wasCard);
                            toAmountController.clear();
                            loanPaymentController.clear();
                            toCurrency = currency;
                            categoryId = null;
                            _toAmountEditedByUser = false;
                            _syncCategoryDefault(newEntry: true);
                          });
                          _updateTransferEstimate(force: true);
                        },
                ),
                const SizedBox(height: 12),
                _StatusSwitch(
                  value: transactionStatus,
                  plannedLabel: _statusLabel(TransactionStatus.planned),
                  actualLabel: _statusLabel(TransactionStatus.actual),
                  onChanged: _changeStatus,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '预计不会影响账户真实余额；已发生会计入账户。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (transactionType == TransactionType.adjustment) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '用于记录投资或退休账户的新增投入，会同步影响余额、成本和现金余额。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('entry-source-account'),
                  value: accountOptions.any((a) => a.id == accountId)
                      ? accountId
                      : null,
                  decoration: const InputDecoration(
                    labelText: '转出账户',
                    border: OutlineInputBorder(),
                  ),
                  items: accountOptions
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.id,
                          child: Text('${account.name} (${account.currency})'),
                        ),
                      )
                      .toList(),
                  onChanged: _keepUnallocatedSplit
                      ? null
                      : (value) => setState(() {
                            final loanPayment =
                                _isInstallment ? _loanPayment : null;
                            final oldCurrency = currency;
                            final wasCard = _usesCreditCardAccount;
                            accountId = value;
                            if (accountId == toAccountId) toAccountId = null;
                            _syncDateFields(wasCard);
                            if (_source?.accountType !=
                                AccountType.creditCard) {
                              cardPostingDate = null;
                            }
                            if (value != null) {
                              currency = _currencyForAccount(value) ?? currency;
                            }
                            if (loanPayment != null &&
                                oldCurrency != currency) {
                              loanPaymentController.text =
                                  loanPayment.toMoneyDecimal();
                              amountController.text = _ledger
                                      .tryConvertAmount(
                                          amount: loanPayment,
                                          fromCurrency: toCurrency,
                                          toCurrency: currency)
                                      ?.toMoneyDecimal() ??
                                  '';
                            }
                            _toAmountEditedByUser = false;
                            _updateTransferEstimate(force: true);
                          }),
                ),
                if (transactionType == TransactionType.transfer) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('entry-target-account'),
                    value: targetOptions.any((a) => a.id == toAccountId)
                        ? toAccountId
                        : null,
                    decoration: const InputDecoration(
                      labelText: '转入账户',
                      border: OutlineInputBorder(),
                    ),
                    items: targetOptions
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child:
                                Text('${account.name} (${account.currency})'),
                          ),
                        )
                        .toList(),
                    onChanged: _isInstallment || _keepUnallocatedSplit
                        ? null
                        : (value) => setState(() {
                              final wasCard = _usesCreditCardAccount;
                              toAccountId = value;
                              _syncDateFields(wasCard);
                              if (value != null) {
                                toCurrency =
                                    _currencyForAccount(value) ?? toCurrency;
                              }
                              _toAmountEditedByUser = false;
                              _updateTransferEstimate(force: true);
                            }),
                  ),
                ],
                if (categoryOptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: categoryOptions.any((c) => c.id == categoryId)
                        ? categoryId
                        : null,
                    hint: const Text('未分类'),
                    decoration: const InputDecoration(
                      labelText: '类别',
                      border: OutlineInputBorder(),
                    ),
                    items: categoryOptions
                        .map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(
                                '${category.name} (${_categoryTypeLabel(category.type)})${category.isArchived ? ' · 已归档' : ''}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => categoryId = value),
                  ),
                ],
                const SizedBox(height: 12),
                FinanceTextField(
                  isAmount: true,
                  controller: amountController,
                  label: '金额',
                  readOnly: _keepUnallocatedSplit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: _numberRequired,
                ),
                const SizedBox(height: 12),
                _CurrencyDisplayField(
                  label: '货币',
                  currency: currency,
                  helperText: '跟随转出账户',
                ),
                if (transactionType == TransactionType.transfer) ...[
                  const SizedBox(height: 12),
                  FinanceTextField(
                    isAmount: true,
                    controller: toAmountController,
                    label: _isInstallment ? '偿还本金' : '转入金额',
                    readOnly: _keepUnallocatedSplit ||
                        (!_isInstallment && currency == toCurrency),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: _isInstallment
                        ? (value) {
                            final principal = double.tryParse(value ?? '');
                            final paid =
                                double.tryParse(amountController.text.trim());
                            return paid != null &&
                                    validLoanInstallmentAmounts(paid, principal,
                                        loanPaymentAmount: _loanPayment,
                                        sameCurrency: currency == toCurrency)
                                ? null
                                : '请核对还款金额、本金及冲正符号';
                          }
                        : _numberRequired,
                  ),
                  if (_isInstallment && currency != toCurrency)
                    FinanceTextField(
                      isAmount: true,
                      controller: loanPaymentController,
                      label: '贷款原币还款总额 ($toCurrency)',
                      validator: _numberRequired,
                    ),
                  const SizedBox(height: 12),
                  _CurrencyDisplayField(
                    label: '转入币种',
                    currency: toCurrency,
                    helperText: '跟随转入账户',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _keepUnallocatedSplit
                          ? '未关联贷款期号，保留原始付款与到账金额。'
                          : _transferPreviewText(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _DateTile(
                  title: _usesCreditCardAccount ? '交易日期' : '记录日期',
                  value: recordDate,
                  onPick: () => _pickRecordDate(),
                ),
                if (source != null &&
                    source.accountType == AccountType.creditCard)
                  CardPostingDateField(
                    source: source,
                    transactionDate: recordDate,
                    value: cardPostingDate,
                    onChanged: (value) =>
                        setState(() => cardPostingDate = value),
                  ),
                if (!_usesCreditCardAccount) ...[
                  const SizedBox(height: 8),
                  _DateTile(
                    title: '结算日期',
                    value: settlementDate,
                    emptyLabel: '未填写时使用记录日期',
                    onPick: () => _pickSettlementDate(),
                    onClear: settlementDate == null
                        ? null
                        : () => setState(() => settlementDate = null),
                  ),
                ],
                if (!_isEditing) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: recurrenceMonths,
                    decoration: const InputDecoration(
                      labelText: '生成周期',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem<int>(
                        value: index + 1,
                        child: Text('${index + 1} 个月'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => recurrenceMonths = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _isInstallment && recurrenceMonths > 1
                          ? '这 $recurrenceMonths 笔还款均计入第 ${_seed!.loanInstallmentNumber} 期。跨期月供可在贷款详情按合同生成。'
                          : '会从当前日期开始，按月生成未来 $recurrenceMonths 个月的记录，包含当前这笔。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FinanceTextField(
                    controller: descriptionController, label: '说明'),
                const SizedBox(height: 12),
                FinanceTextField(controller: merchantController, label: '商户'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton.icon(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除'),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  List<Account> _sortedAccounts({bool target = false}) {
    final original = widget.initialTransaction;
    final accounts = _ledger.entryAccounts(
        originalAccountId: target ? original?.toAccountId : original?.accountId)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return accounts;
  }

  List<Category> _categoryOptions() =>
      entryCategoryOptions(context, widget.repository, transactionType,
          originalCategoryId: widget.initialTransaction?.type == transactionType
              ? widget.initialTransaction?.categoryId
              : null);

  String _preferredAccountId(List<Account> accounts) {
    final counts = <String, int>{};
    for (final transaction in _ledger.transactions) {
      counts[transaction.accountId] = (counts[transaction.accountId] ?? 0) + 1;
    }

    accounts.sort((left, right) {
      final countCompare =
          (counts[right.id] ?? 0).compareTo(counts[left.id] ?? 0);
      if (countCompare != 0) {
        return countCompare;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    return accounts.first.id;
  }

  String? _currencyForAccount(String accountId) {
    for (final account in _ledger.accounts) {
      if (account.id == accountId) {
        return normalizeCurrency(account.currency);
      }
    }
    return null;
  }

  void _markToAmountEdited() {
    if (_isAutoSettingToAmount) {
      return;
    }
    _toAmountEditedByUser = true;
  }

  void _updateTransferEstimateIfAllowed() {
    _updateTransferEstimate();
  }

  void _updateTransferEstimate({bool force = false}) {
    if (transactionType != TransactionType.transfer ||
        _isInstallment ||
        _keepUnallocatedSplit) {
      return;
    }
    if (!force && _toAmountEditedByUser && currency != toCurrency) {
      return;
    }
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null) {
      return;
    }
    final estimate = _ledger.tryConvertAmount(
      amount: amount,
      fromCurrency: currency,
      toCurrency: toCurrency,
    );
    _isAutoSettingToAmount = true;
    toAmountController.text = estimate?.toMoneyDecimal() ?? '';
    _isAutoSettingToAmount = false;
  }

  String _transferPreviewText() {
    if (currency != toCurrency &&
        _ledger.tryConvertAmount(
                amount: 1, fromCurrency: currency, toCurrency: toCurrency) ==
            null) {
      return _isInstallment ? '缺少汇率，请核对两端实际还款金额' : '缺少汇率，请输入实际到账金额';
    }
    final amount = double.tryParse(amountController.text.trim());
    final toAmount = double.tryParse(toAmountController.text.trim());
    if (amount == null || toAmount == null) {
      return '转账会按转出账户扣款，并按转入金额写入目标账户。';
    }
    return '${formatMoney(amount, currency: currency)} → '
        '${formatMoney(toAmount, currency: toCurrency)}';
  }

  String? _preferredCategoryId(List<Category> categories) {
    if (categories.isEmpty) {
      return null;
    }

    final allowedCategoryIds = categories.map((item) => item.id).toSet();
    final counts = <String, int>{};
    for (final transaction in _ledger.transactions) {
      if (transaction.type != transactionType) {
        continue;
      }
      final transactionCategoryId = transaction.categoryId;
      if (transactionCategoryId == null ||
          !allowedCategoryIds.contains(transactionCategoryId)) {
        continue;
      }
      counts[transactionCategoryId] = (counts[transactionCategoryId] ?? 0) + 1;
    }

    categories.sort((left, right) {
      final countCompare =
          (counts[right.id] ?? 0).compareTo(counts[left.id] ?? 0);
      if (countCompare != 0) {
        return countCompare;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    return categories.first.id;
  }

  void _syncCategoryDefault({bool newEntry = false}) {
    final categories = _categoryOptions();
    if (categories.isEmpty) {
      categoryId = null;
      return;
    }
    if (categoryId != null && categories.any((item) => item.id == categoryId)) {
      return;
    }
    categoryId = transactionType == TransactionType.transfer ||
            (!newEntry && categoryId == null)
        ? null
        : _preferredCategoryId(categories.where((c) => !c.isArchived).toList());
  }

  Future<void> _changeStatus(TransactionStatus next) async {
    final date =
        _usesCreditCardAccount ? recordDate : settlementDate ?? recordDate;
    final chosen = await dateForLoanStatusChange(
      context,
      original: widget.initialTransaction,
      type: transactionType,
      toAccountId: toAccountId,
      before: transactionStatus,
      after: next,
      date: date,
    );
    if (!mounted || chosen == null) return;
    setState(() {
      transactionStatus = next;
      if (chosen != date) {
        if (_usesCreditCardAccount) {
          recordDate = chosen;
        } else {
          settlementDate = chosen;
        }
      }
    });
  }

  void _syncDateFields(bool wasCard) {
    if (wasCard == _usesCreditCardAccount) return;
    if (_usesCreditCardAccount) {
      recordDate = settlementDate ?? recordDate;
      settlementDate = null;
    } else if (_isEditing) {
      settlementDate = recordDate;
      recordDate = widget.initialTransaction!.recordDate;
    }
  }

  Future<void> _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: recordDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        recordDate = picked;
        if (cardPostingDate?.isBefore(DateUtils.dateOnly(picked)) == true) {
          cardPostingDate = null;
        }
      });
    }
  }

  Future<void> _pickSettlementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: settlementDate ?? recordDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => settlementDate = picked);
    }
  }

  void _submit() {
    if (!_sortedAccounts().any((a) => a.id == accountId) ||
        (transactionType == TransactionType.transfer &&
            !_sortedAccounts(target: true).any((a) => a.id == toAccountId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择启用的账户；已停用账户只能保留在原记录中。')),
      );
      return;
    }
    if (categoryId != null &&
        !_categoryOptions().any((c) => c.id == categoryId)) {
      setState(() => categoryId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选类别已变更，请重新选择类别或确认为未分类。')),
      );
      return;
    }
    if (!formKey.currentState!.validate() || accountId == null) {
      return;
    }
    if (transactionType == TransactionType.transfer && toAccountId == null) {
      return;
    }

    final amount = double.parse(amountController.text.trim());
    final transferInAmount = transactionType == TransactionType.transfer &&
            (currency != toCurrency || _isInstallment || _keepUnallocatedSplit)
        ? double.parse(toAmountController.text.trim())
        : null;
    final transferInCurrency = _keepUnallocatedSplit
        ? _seed!.toCurrency
        : transactionType == TransactionType.transfer
            ? normalizeCurrency(toCurrency)
            : null;
    final description = _nullIfEmpty(descriptionController.text);
    final merchant = _nullIfEmpty(merchantController.text);
    final effectiveSettlementDate =
        _usesCreditCardAccount ? recordDate : settlementDate ?? recordDate;
    final posting =
        _source?.accountType == AccountType.creditCard ? cardPostingDate : null;

    if (_isEditing) {
      final keepLegacyLink =
          widget.initialTransaction!.type == transactionType &&
              widget.initialTransaction!.toAccountId == toAccountId;
      Navigator.of(context).pop(
        TransactionFormResult(
          transactions: [
            FinanceTransaction(
              id: widget.initialTransaction!.id,
              type: transactionType,
              accountId: accountId!,
              toAccountId: toAccountId,
              categoryId: categoryId,
              amount: amount,
              currency: _keepUnallocatedSplit ? _seed!.currency : currency,
              toAmount: transferInAmount,
              loanInstallmentNumber: _seed?.loanInstallmentNumber,
              loanPaymentAmount: _isInstallment && currency != toCurrency
                  ? _loanPayment
                  : null,
              legacyLoanPartNumber: keepLegacyLink
                  ? widget.initialTransaction?.legacyLoanPartNumber
                  : null,
              legacyLoanId: keepLegacyLink
                  ? widget.initialTransaction?.legacyLoanId
                  : null,
              toCurrency: transferInCurrency,
              recordDate: _usesCreditCardAccount
                  ? widget.initialTransaction!.recordDate
                  : recordDate,
              transactionDate: effectiveSettlementDate,
              cardPostingDate: posting,
              status: transactionStatus,
              recurringRuleId: widget.initialTransaction!.recurringRuleId,
              description: description,
              merchant: merchant,
            ),
          ],
        ),
      );
      return;
    }

    final transactions = buildRecurringTransactions(
      months: recurrenceMonths,
      baseTransaction: FinanceTransaction(
        id: buildId('txn'),
        type: transactionType,
        accountId: accountId!,
        toAccountId: toAccountId,
        categoryId: categoryId,
        amount: amount,
        currency: _keepUnallocatedSplit ? _seed!.currency : currency,
        toAmount: transferInAmount,
        loanInstallmentNumber: _seed?.loanInstallmentNumber,
        loanPaymentAmount:
            _isInstallment && currency != toCurrency ? _loanPayment : null,
        toCurrency: transferInCurrency,
        recordDate: recordDate,
        transactionDate: effectiveSettlementDate,
        cardPostingDate: posting,
        status: transactionStatus,
        description: description,
        merchant: merchant,
      ),
    );

    Navigator.of(context)
        .pop(TransactionFormResult(transactions: transactions));
  }

  String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return '收入';
      case TransactionType.expense:
        return '支出';
      case TransactionType.transfer:
        return '转账';
      case TransactionType.adjustment:
        return '注资调整';
    }
  }

  String _categoryTypeLabel(CategoryType type) {
    switch (type) {
      case CategoryType.income:
        return '收入';
      case CategoryType.expense:
        return '支出';
      case CategoryType.investment:
        return '投资';
      case CategoryType.transfer:
        return '转账';
    }
  }

  String _statusLabel(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.planned:
        return '预计';
      case TransactionStatus.actual:
        return '已发生';
      case TransactionStatus.settled:
        return '已发生';
    }
  }

  String? _numberRequired(String? value) {
    final amount = double.tryParse(value ?? '');
    return amount == null || !amount.isFinite ? '请输入有限数字' : null;
  }

  Future<void> _confirmDelete() async {
    final transactionId = widget.initialTransaction?.id;
    if (transactionId == null) return;
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
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(TransactionFormResult.deleted(transactionId));
  }

  String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.title,
    required this.value,
    required this.onPick,
    this.emptyLabel,
    this.onClear,
  });

  final String title;
  final DateTime? value;
  final String? emptyLabel;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value == null ? emptyLabel ?? '未填写' : _formatDate(value!)),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.clear),
              tooltip: '清空',
            ),
          TextButton(
            onPressed: onPick,
            child: const Text('修改'),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _CurrencyDisplayField extends StatelessWidget {
  const _CurrencyDisplayField({
    required this.label,
    required this.currency,
    required this.helperText,
  });

  final String label;
  final String currency;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      child: Text(currencyOptionLabel(currency)),
    );
  }
}

class TransactionFormResult {
  const TransactionFormResult({
    this.transactions = const [],
    this.deletedTransactionId,
  });

  const TransactionFormResult.deleted(String transactionId)
      : transactions = const [],
        deletedTransactionId = transactionId;

  final List<FinanceTransaction> transactions;
  final String? deletedTransactionId;
}

class _StatusSwitch extends StatelessWidget {
  const _StatusSwitch({
    required this.value,
    required this.plannedLabel,
    required this.actualLabel,
    required this.onChanged,
  });

  final TransactionStatus value;
  final String plannedLabel;
  final String actualLabel;
  final ValueChanged<TransactionStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withValues(alpha: 0.55);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: '状态',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.all(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatusSwitchOption(
              label: plannedLabel,
              selected: value == TransactionStatus.planned,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(7),
              ),
              borderColor: borderColor,
              onTap: () => onChanged(TransactionStatus.planned),
            ),
          ),
          Expanded(
            child: _StatusSwitchOption(
              label: actualLabel,
              selected: value != TransactionStatus.planned,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(7),
              ),
              borderColor: borderColor,
              onTap: () => onChanged(TransactionStatus.actual),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusSwitchOption extends StatelessWidget {
  const _StatusSwitchOption({
    required this.label,
    required this.selected,
    required this.borderRadius,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final BorderRadius borderRadius;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: selected ? colorScheme.primary : borderColor,
              width: selected ? 1.4 : 0.8,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

List<FinanceTransaction> buildRecurringTransactions({
  required FinanceTransaction baseTransaction,
  required int months,
}) {
  final safeMonths = months < 1 ? 1 : months;
  final idPrefix = baseTransaction.id;
  final posting = baseTransaction.cardPostingDate;
  final occurrence = baseTransaction.transactionDate;
  // UTC midnights count calendar days even across a 23- or 25-hour local day.
  final offsetDays = posting == null
      ? null
      : DateTime.utc(posting.year, posting.month, posting.day)
          .difference(
              DateTime.utc(occurrence.year, occurrence.month, occurrence.day))
          .inDays;
  if (offsetDays != null && offsetDays < 0) {
    throw const FormatException('信用卡账单入账日不能早于交易发生日。');
  }

  return List.generate(safeMonths, (index) {
    final settlementDate =
        anchoredMonthDate(baseTransaction.transactionDate, index);
    final recordDate = anchoredMonthDate(baseTransaction.recordDate, index);
    return FinanceTransaction(
      id: '$idPrefix-${index + 1}',
      type: baseTransaction.type,
      accountId: baseTransaction.accountId,
      toAccountId: baseTransaction.toAccountId,
      categoryId: baseTransaction.categoryId,
      amount: baseTransaction.amount,
      currency: baseTransaction.currency,
      toAmount: baseTransaction.toAmount,
      loanInstallmentNumber: baseTransaction.loanInstallmentNumber,
      loanPaymentAmount: baseTransaction.loanPaymentAmount,
      toCurrency: baseTransaction.toCurrency,
      recordDate: recordDate,
      transactionDate: settlementDate,
      cardPostingDate: offsetDays == null
          ? null
          : DateTime(settlementDate.year, settlementDate.month,
              settlementDate.day + offsetDays),
      status: baseTransaction.status,
      recurringRuleId: baseTransaction.recurringRuleId,
      description: baseTransaction.description,
      merchant: baseTransaction.merchant,
    );
  });
}
