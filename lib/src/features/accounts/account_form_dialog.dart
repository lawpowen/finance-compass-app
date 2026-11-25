import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/loan_amortization.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../../core/theme/finance_theme.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_amount_field.dart';

class AccountFormDialog extends StatefulWidget {
  const AccountFormDialog({
    super.key,
    this.initialAccount,
    this.defaultCurrency = baseCurrencyCode,
    this.hasEconomicHistory = false,
    this.onSetActive,
  });

  final Account? initialAccount;
  final String defaultCurrency;
  final bool hasEconomicHistory;
  final Future<void> Function(bool active)? onSetActive;

  static Widget edit(Account initial, FinanceRepository repository) =>
      Consumer(builder: (context, ref, _) {
        final live =
            ref.watch(financeRepositoryProvider).valueOrNull ?? repository;
        final account =
            live.accounts.where((a) => a.id == initial.id).firstOrNull;
        if (account == null) {
          return AlertDialog(
            content: const Text('账户已移除，请返回账户列表。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回')),
            ],
          );
        }
        return AccountFormDialog(
          initialAccount: account,
          onSetActive: (active) => ref
              .read(accountMutationsProvider.notifier)
              .setActive(account.id, active),
          hasEconomicHistory: live.transactions.any((t) =>
                  t.accountId == account.id || t.toAccountId == account.id) ||
              live.snapshots.any((s) => s.accountId == account.id),
        );
      });

  @override
  State<AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<AccountFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController institutionController;
  late final TextEditingController initialBalanceController;
  late final TextEditingController currentBalanceController;
  late final TextEditingController noteController;
  late final TextEditingController creditLimitController;
  late final TextEditingController statementDayController;
  late final TextEditingController paymentDueDayController;
  late final TextEditingController loanPrincipalController;
  late final TextEditingController loanInterestRateController;
  late final TextEditingController loanTermYearsController;
  late final TextEditingController loanPaymentDayController;
  late final TextEditingController loanQuotedPaymentController;
  late final TextEditingController loanOpeningBalanceController;

  late AccountType accountType;
  late ReportGroup reportGroup;
  late String currency;
  late DateTime loanStartDate;
  late DateTime loanTrackingStartDate;
  late LoanRepaymentMethod loanRepaymentMethod;

  bool _savingStatus = false;

  bool get isEdit => widget.initialAccount != null;

  bool get _useOpeningBalance =>
      !widget.hasEconomicHistory &&
      (!isEdit ||
          reportGroup == ReportGroup.investment ||
          reportGroup == ReportGroup.retirement ||
          widget.initialAccount!.initialBalance ==
              widget.initialAccount!.currentBalance);

  @override
  void initState() {
    super.initState();
    final account = widget.initialAccount;
    nameController = TextEditingController(text: account?.name ?? '');
    institutionController =
        TextEditingController(text: account?.institution ?? '');
    currency = normalizeCurrency(account?.currency ?? widget.defaultCurrency);
    initialBalanceController = TextEditingController(
      text: (account?.initialBalance ?? 0).toStringAsFixed(2),
    );
    currentBalanceController = TextEditingController(
      text: (account?.currentBalance ?? account?.initialBalance ?? 0)
          .toStringAsFixed(2),
    );
    noteController = TextEditingController(text: account?.note ?? '');
    creditLimitController = TextEditingController(
      text: (account?.creditLimit ?? 10000).toStringAsFixed(2),
    );
    statementDayController = TextEditingController(
      text: (account?.statementDay ?? 12).toString(),
    );
    paymentDueDayController = TextEditingController(
      text: (account?.paymentDueDay ?? 28).toString(),
    );
    loanPrincipalController = TextEditingController(
      text: (account?.loanPrincipal ??
              (account?.accountType == AccountType.loan
                  ? account!.initialBalance.abs()
                  : 0))
          .toStringAsFixed(2),
    );
    loanInterestRateController = TextEditingController(
      text: (account?.loanAnnualInterestRate ?? 0).toString(),
    );
    loanTermYearsController = TextEditingController(
      text: _termYearsText(account?.loanTermMonths ?? 60),
    );
    loanPaymentDayController = TextEditingController(
      text: (account?.loanPaymentDay ?? DateTime.now().day).toString(),
    );
    loanQuotedPaymentController = TextEditingController(
      text: account?.loanQuotedMonthlyPayment?.toStringAsFixed(2) ?? '',
    );
    loanOpeningBalanceController = TextEditingController(
      text: account?.accountType == AccountType.loan
          ? account!.initialBalance.abs().toStringAsFixed(2)
          : '',
    );
    loanStartDate = account?.loanStartDate ?? DateTime.now();
    loanTrackingStartDate = account?.loanTrackingStartDate ?? loanStartDate;
    loanRepaymentMethod =
        account?.loanRepaymentMethod ?? LoanRepaymentMethod.equalInstallment;
    accountType = account?.accountType ?? AccountType.cash;
    reportGroup = account?.effectiveReportGroup ?? ReportGroup.cash;
  }

  @override
  void didUpdateWidget(AccountFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final account = widget.initialAccount;
    if (!widget.hasEconomicHistory || account == null) return;
    currency = normalizeCurrency(account.currency);
    accountType = account.accountType;
    reportGroup = account.effectiveReportGroup;
    currentBalanceController.text = account.currentBalance.toStringAsFixed(2);
    initialBalanceController.text = account.initialBalance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    nameController.dispose();
    institutionController.dispose();
    initialBalanceController.dispose();
    currentBalanceController.dispose();
    noteController.dispose();
    creditLimitController.dispose();
    statementDayController.dispose();
    paymentDueDayController.dispose();
    loanPrincipalController.dispose();
    loanInterestRateController.dispose();
    loanTermYearsController.dispose();
    loanPaymentDayController.dispose();
    loanQuotedPaymentController.dispose();
    loanOpeningBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCreditCard = accountType == AccountType.creditCard;
    final isLoan = accountType == AccountType.loan;
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: CompassBackground(
        child: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    CompassBackButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        isCreditCard && isEdit
                            ? '信用卡账户设置'
                            : isEdit
                                ? '编辑账户'
                                : '新增账户',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const CompassIconBadge(
                      icon: Icons.credit_card_rounded,
                      size: 64,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameController.text.isEmpty
                                ? '新账户'
                                : nameController.text,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currency,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '启用中',
                            style: TextStyle(
                                color: financePaletteOf(context).seed),
                          ),
                        ],
                      ),
                    ),
                    const CompassIconBadge(
                      icon: Icons.edit_outlined,
                      outlined: true,
                      size: 32,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                compassHairline,
                const SizedBox(height: 16),
                const CompassSectionLabel('基本资料'),
                _AccountEditorRow(
                  icon: Icons.person_outline_rounded,
                  label: '账户名称',
                  child: _InlineTextEditor(
                    controller: nameController,
                    validator: _required,
                  ),
                ),
                _AccountEditorRow(
                  icon: Icons.account_balance_outlined,
                  label: isCreditCard ? '发卡机构' : '机构',
                  child: _InlineTextEditor(
                    controller: institutionController,
                    hintText: '未设置',
                  ),
                ),
                _AccountEditorRow(
                  icon: Icons.monetization_on_outlined,
                  label: '币种',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currency,
                      alignment: Alignment.centerRight,
                      items: {...supportedCurrencies, currency}
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: widget.hasEconomicHistory
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => currency = value);
                              }
                            },
                    ),
                  ),
                ),
                if (widget.hasEconomicHistory)
                  const Text('账户已有流水或快照，币种、类型和报表分组已锁定。余额由账本计算。'),
                if (!isCreditCard ||
                    widget.initialAccount?.accountType !=
                        AccountType.creditCard) ...[
                  _AccountEditorRow(
                    icon: Icons.category_outlined,
                    label: '账户类型',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AccountType>(
                        value: accountType,
                        alignment: Alignment.centerRight,
                        items: AccountType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(_accountTypeLabel(type)),
                              ),
                            )
                            .toList(),
                        onChanged: widget.hasEconomicHistory
                            ? null
                            : (value) => setState(() {
                                  if (value == null) return;
                                  accountType = value;
                                  reportGroup =
                                      allowedReportGroups(value).first;
                                }),
                      ),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.pie_chart_outline_rounded,
                    label: '报表分组',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReportGroup>(
                        value: reportGroup,
                        alignment: Alignment.centerRight,
                        items: allowedReportGroups(accountType)
                            .map(
                              (group) => DropdownMenuItem(
                                value: group,
                                child: Text(_groupLabel(group)),
                              ),
                            )
                            .toList(),
                        onChanged: widget.hasEconomicHistory ||
                                allowedReportGroups(accountType).length == 1
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => reportGroup = value);
                                }
                              },
                      ),
                    ),
                  ),
                ],
                if (isCreditCard) ...[
                  const SizedBox(height: 16),
                  const CompassHelpHeading(
                    title: CompassSectionLabel('额度与余额'),
                    label: '信用卡余额',
                    message: '欠款填负数，溢缴款填正数',
                  ),
                  _AccountEditorRow(
                    icon: Icons.credit_card_rounded,
                    label: '信用额度',
                    child: _InlineTextEditor(
                      controller: creditLimitController,
                      isAmount: true,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _positiveNumberRequired,
                    ),
                  ),
                  // Stored signed as-is: negative is debt, positive is an
                  // overpayment. Existing balances are never flipped.
                  _AccountEditorRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '信用卡余额',
                    child: _InlineTextEditor(
                      fieldKey: const Key('credit-card-balance-field'),
                      controller: currentBalanceController,
                      isAmount: true,
                      readOnly: widget.hasEconomicHistory,
                      prefixText: '$currency ',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: _finiteNumberRequired,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const CompassSectionLabel('账单周期'),
                  _AccountEditorRow(
                    icon: Icons.calendar_month_outlined,
                    label: '结算日',
                    child: _InlineTextEditor(
                      controller: statementDayController,
                      prefixText: '每月 ',
                      suffixText: ' 日',
                      keyboardType: TextInputType.number,
                      validator: _dayRequired,
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.calendar_month_outlined,
                    label: '还款日',
                    child: _InlineTextEditor(
                      controller: paymentDueDayController,
                      prefixText: '每月 ',
                      suffixText: ' 日',
                      keyboardType: TextInputType.number,
                      validator: _dayRequired,
                    ),
                  ),
                ] else if (isLoan) ...[
                  const SizedBox(height: 16),
                  const CompassHelpHeading(
                    title: CompassSectionLabel('贷款条件'),
                    label: '贷款条件',
                    message: '设置金额、利率和年限后，系统会生成还款计划。开始记账余额填开始记账日的剩余贷款，首期从下月计算。',
                  ),
                  _AccountEditorRow(
                    icon: Icons.request_quote_outlined,
                    label: '贷款金额',
                    child: _InlineTextEditor(
                      controller: loanPrincipalController,
                      isAmount: true,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _positiveNumberRequired,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.percent_rounded,
                    label: '年利率',
                    child: _InlineTextEditor(
                      controller: loanInterestRateController,
                      suffixText: ' %',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _nonNegativeNumberRequired,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.timelapse_rounded,
                    label: '贷款年限',
                    child: _InlineTextEditor(
                      controller: loanTermYearsController,
                      suffixText: ' 年',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _loanTermRequired,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.calendar_today_outlined,
                    label: '合同开始日',
                    child: TextButton(
                      key: const Key('loan-contract-date'),
                      onPressed: _pickLoanStartDate,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(_dateLabel(loanStartDate)),
                      ),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.play_circle_outline_rounded,
                    label: '开始记账日期',
                    child: TextButton(
                      key: const Key('loan-tracking-date'),
                      onPressed: _pickLoanTrackingStartDate,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(_dateLabel(loanTrackingStartDate)),
                      ),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.event_repeat_rounded,
                    label: '每月还款日',
                    child: _InlineTextEditor(
                      controller: loanPaymentDayController,
                      prefixText: '每月 ',
                      suffixText: ' 日',
                      keyboardType: TextInputType.number,
                      validator: _dayRequired,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.calculate_outlined,
                    label: '还款方式',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<LoanRepaymentMethod>(
                        value: loanRepaymentMethod,
                        isExpanded: true,
                        alignment: Alignment.centerRight,
                        items: LoanRepaymentMethod.values
                            .map(
                              (method) => DropdownMenuItem(
                                value: method,
                                child: Text(_loanMethodLabel(method)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => loanRepaymentMethod = value);
                          }
                        },
                      ),
                    ),
                  ),
                  if (loanRepaymentMethod != LoanRepaymentMethod.equalPrincipal)
                    _AccountEditorRow(
                      icon: Icons.account_balance_outlined,
                      label: '银行核定月供',
                      child: _InlineTextEditor(
                        controller: loanQuotedPaymentController,
                        isAmount: true,
                        prefixText: '$currency ',
                        hintText: '可选',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _optionalPositiveNumber,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  _AccountEditorRow(
                    icon: Icons.playlist_add_check_circle_outlined,
                    label: '开始记账余额',
                    child: _InlineTextEditor(
                      fieldKey: const Key('loan-opening-balance'),
                      controller: loanOpeningBalanceController,
                      isAmount: true,
                      prefixText: '$currency ',
                      hintText: '默认贷款金额',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: _optionalPositiveNumber,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LoanPaymentPreview(
                    schedule: _previewLoanSchedule(),
                    currency: currency,
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const CompassSectionLabel('余额'),
                  _AccountEditorRow(
                    icon: Icons.savings_outlined,
                    label: '初始余额',
                    child: _InlineTextEditor(
                      fieldKey: const Key('account-opening-balance'),
                      controller: initialBalanceController,
                      isAmount: true,
                      readOnly: widget.hasEconomicHistory,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _numberRequired,
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '当前余额',
                    child: _InlineTextEditor(
                      fieldKey: const Key('account-current-balance'),
                      controller: _useOpeningBalance
                          ? initialBalanceController
                          : currentBalanceController,
                      isAmount: true,
                      readOnly: _useOpeningBalance || widget.hasEconomicHistory,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _numberRequired,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                CompassPrimaryButton(
                    label: '保存更改', onPressed: _savingStatus ? null : _submit),
                if (isEdit && widget.onSetActive != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('toggle-account-active'),
                    onPressed: _savingStatus ? null : _setActive,
                    child: Text(
                      widget.initialAccount!.isActive ? '停用账户' : '重新启用账户',
                      style:
                          TextStyle(color: financePaletteOf(context).expense),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setActive() async {
    final update = widget.onSetActive;
    if (update == null || _savingStatus) return;
    final active = !widget.initialAccount!.isActive;
    setState(() => _savingStatus = true);
    try {
      await update(active);
      // The status was saved through the ledger session. The caller only
      // receives an Account when the separate form-save action is chosen.
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger
            .showSnackBar(SnackBar(content: Text(active ? '账户已启用' : '账户已停用')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存账户状态失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _savingStatus = false);
    }
  }

  void _submit() {
    if (!formKey.currentState!.validate()) {
      return;
    }
    if (accountType == AccountType.loan &&
        !validLoanTrackingDate(loanStartDate, loanTrackingStartDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始记账日期必须等于或晚于合同开始日。')),
      );
      return;
    }
    if (accountType == AccountType.loan && _previewLoanSchedule() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('贷款条件无法生成还款计划，请检查月供是否合理并与贷款期限一致。')),
      );
      return;
    }

    final isLoan = accountType == AccountType.loan;
    final principal =
        isLoan ? double.parse(loanPrincipalController.text.trim()) : null;
    final openingLoanBalance = isLoan
        ? (_optionalDouble(loanOpeningBalanceController.text) ?? principal!)
        : null;
    if (isLoan && openingLoanBalance! > principal!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始记账余额不能大于贷款金额。')),
      );
      return;
    }
    final previousLoanPrincipalReduction =
        widget.initialAccount?.accountType == AccountType.loan
            ? widget.initialAccount!.currentBalance -
                widget.initialAccount!.initialBalance
            : 0.0;
    final double balance;
    final double currentBalance;
    if (isLoan) {
      balance = -openingLoanBalance!;
      currentBalance = balance + previousLoanPrincipalReduction;
    } else if (widget.hasEconomicHistory) {
      balance = widget.initialAccount!.initialBalance;
      currentBalance = widget.initialAccount!.currentBalance;
    } else if (accountType == AccountType.creditCard) {
      currentBalance = double.parse(currentBalanceController.text.trim());
      balance = _useOpeningBalance
          ? currentBalance
          : widget.initialAccount!.initialBalance;
    } else {
      balance = double.parse(initialBalanceController.text.trim());
      currentBalance = _useOpeningBalance
          ? balance
          : double.parse(currentBalanceController.text.trim());
    }
    final quotedPayment = _optionalDouble(loanQuotedPaymentController.text);
    Navigator.of(context).pop(
      Account(
        id: widget.initialAccount?.id ?? buildId('acc'),
        name: nameController.text.trim(),
        accountType: accountType,
        reportGroup: reportGroup,
        currency: widget.hasEconomicHistory
            ? widget.initialAccount!.currency
            : currency,
        initialBalance: balance,
        currentBalance: currentBalance,
        institution: _nullIfEmpty(institutionController.text),
        note: _nullIfEmpty(noteController.text),
        isActive: widget.initialAccount?.isActive ?? true,
        creditLimit: accountType == AccountType.creditCard
            ? double.parse(creditLimitController.text.trim())
            : null,
        statementDay: accountType == AccountType.creditCard
            ? int.parse(statementDayController.text.trim())
            : null,
        paymentDueDay: accountType == AccountType.creditCard
            ? int.parse(paymentDueDayController.text.trim())
            : null,
        loanPrincipal: isLoan ? principal : null,
        loanAnnualInterestRate: isLoan
            ? double.parse(loanInterestRateController.text.trim())
            : null,
        loanTermMonths:
            isLoan ? _loanTermMonths(loanTermYearsController.text)! : null,
        loanStartDate: isLoan ? loanStartDate : null,
        loanTrackingStartDate: isLoan ? loanTrackingStartDate : null,
        loanPaymentDay:
            isLoan ? int.parse(loanPaymentDayController.text.trim()) : null,
        loanRepaymentMethod: isLoan ? loanRepaymentMethod : null,
        loanQuotedMonthlyPayment:
            isLoan && loanRepaymentMethod != LoanRepaymentMethod.equalPrincipal
                ? quotedPayment
                : null,
      ),
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? '必填' : null;
  String? _numberRequired(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || !parsed.isFinite ? '请输入数字' : null;
  }

  /// double.tryParse accepts "NaN" and "Infinity"; a card balance must not.
  String? _finiteNumberRequired(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || !parsed.isFinite ? '请输入有效金额' : null;
  }

  String? _positiveNumberRequired(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || !parsed.isFinite || parsed <= 0
        ? '请输入大于 0 的金额'
        : null;
  }

  String? _dayRequired(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 1 || parsed > 31 ? '请输入 1–31' : null;
  }

  String? _nonNegativeNumberRequired(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || !parsed.isFinite || parsed < 0
        ? '请输入不小于 0 的数字'
        : null;
  }

  String? _optionalPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value);
    return parsed == null || !parsed.isFinite || parsed <= 0
        ? '请输入大于 0 的金额'
        : null;
  }

  String? _loanTermRequired(String? value) {
    final months = _loanTermMonths(value);
    return months == null || months < 1 || months > 1200
        ? '请输入 1 个月至 100 年'
        : null;
  }

  int? _loanTermMonths(String? value) {
    final years = double.tryParse(value?.trim() ?? '');
    if (years == null || !years.isFinite || years <= 0) return null;
    final rawMonths = years * 12;
    if (!rawMonths.isFinite || rawMonths > 1200.001) return null;
    final months = rawMonths.round();
    return (rawMonths - months).abs() <= .001 ? months : null;
  }

  double? _optionalDouble(String value) {
    if (value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  LoanAmortizationSchedule? _previewLoanSchedule() {
    if (!validLoanTrackingDate(loanStartDate, loanTrackingStartDate)) {
      return null;
    }
    final principal = double.tryParse(loanPrincipalController.text.trim());
    final rate = double.tryParse(loanInterestRateController.text.trim());
    final months = _loanTermMonths(loanTermYearsController.text);
    final paymentDay = int.tryParse(loanPaymentDayController.text.trim());
    if (principal == null ||
        !principal.isFinite ||
        principal <= 0 ||
        rate == null ||
        !rate.isFinite ||
        rate < 0 ||
        months == null ||
        months < 1 ||
        months > 1200 ||
        paymentDay == null ||
        paymentDay < 1 ||
        paymentDay > 31) {
      return null;
    }
    final openingText = loanOpeningBalanceController.text.trim();
    final openingPrincipal =
        openingText.isEmpty ? principal : _optionalDouble(openingText);
    if (openingPrincipal == null) {
      return null;
    }
    final quotedText = loanQuotedPaymentController.text.trim();
    final quotedPayment =
        loanRepaymentMethod == LoanRepaymentMethod.equalPrincipal ||
                quotedText.isEmpty
            ? null
            : _optionalDouble(quotedText);
    if (loanRepaymentMethod != LoanRepaymentMethod.equalPrincipal &&
        quotedText.isNotEmpty &&
        quotedPayment == null) {
      return null;
    }
    try {
      return calculateLoanAmortization(
        principal: principal,
        annualInterestRatePercent: rate,
        termMonths: months,
        startDate: loanTrackingStartDate,
        paymentDay: paymentDay,
        method: loanRepaymentMethod,
        quotedMonthlyPayment: quotedPayment,
        openingPrincipal: openingPrincipal,
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _pickLoanStartDate() async {
    final lastDate = DateTime(2200, 12, 31);
    final selected = await showDatePicker(
      context: context,
      initialDate: loanStartDate,
      firstDate: loanStartDate.year < 1950 ? loanStartDate : DateTime(1950),
      lastDate: loanStartDate.isAfter(lastDate) ? loanStartDate : lastDate,
    );
    if (selected != null && mounted) {
      setState(() {
        loanStartDate = selected;
        if (!validLoanTrackingDate(selected, loanTrackingStartDate)) {
          loanTrackingStartDate = selected;
        }
      });
    }
  }

  Future<void> _pickLoanTrackingStartDate() async {
    final initial = validLoanTrackingDate(loanStartDate, loanTrackingStartDate)
        ? loanTrackingStartDate
        : loanStartDate;
    final lastDate = DateTime(2200, 12, 31);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: loanStartDate,
      lastDate: initial.isAfter(lastDate) ? initial : lastDate,
    );
    if (selected != null && mounted) {
      setState(() => loanTrackingStartDate = selected);
    }
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _loanMethodLabel(LoanRepaymentMethod method) => switch (method) {
        LoanRepaymentMethod.equalInstallment => '等额本息',
        LoanRepaymentMethod.equalPrincipal => '等额本金',
        LoanRepaymentMethod.flatRate => '平息贷款',
      };

  static String _termYearsText(int months) {
    if (months % 12 == 0) return '${months ~/ 12}';
    return (months / 12).toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  }

  String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();

  String _groupLabel(ReportGroup group) {
    switch (group) {
      case ReportGroup.cash:
        return '现金';
      case ReportGroup.credit:
        return '信用';
      case ReportGroup.investment:
        return '投资';
      case ReportGroup.retirement:
        return '退休';
    }
  }

  String _accountTypeLabel(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return '现金';
      case AccountType.bankSaving:
        return '储蓄户口';
      case AccountType.eWallet:
        return '电子钱包';
      case AccountType.creditCard:
        return '信用卡';
      case AccountType.moneyMarketFund:
        return '货币基金';
      case AccountType.pension:
        return '养老金';
      case AccountType.stock:
        return '股票';
      case AccountType.crypto:
        return '加密货币';
      case AccountType.trading:
        return '交易户口';
      case AccountType.fund:
        return '基金';
      case AccountType.loan:
        return '贷款';
      case AccountType.other:
        return '其他';
    }
  }
}

class _AccountEditorRow extends StatelessWidget {
  const _AccountEditorRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: financePaletteOf(context).border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child:
                  Icon(icon, color: financePaletteOf(context).seed, size: 21),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(label)),
            SizedBox(width: 178, child: child),
          ],
        ),
      );
}

class _InlineTextEditor extends StatelessWidget {
  const _InlineTextEditor({
    required this.controller,
    this.fieldKey,
    this.isAmount = false,
    this.readOnly = false,
    this.validator,
    this.hintText,
    this.prefixText,
    this.suffixText,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final bool isAmount;
  final bool readOnly;
  final FormFieldValidator<String>? validator;
  final String? hintText;
  final String? prefixText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hintText,
      prefixText: prefixText,
      suffixText: suffixText,
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
    if (isAmount) {
      return FinanceAmountField(
        fieldKey: fieldKey,
        controller: controller,
        readOnly: readOnly,
        validator: validator,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: decoration,
      );
    }
    return TextFormField(
      key: fieldKey,
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      onChanged: onChanged,
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: decoration,
    );
  }
}

class _LoanPaymentPreview extends StatelessWidget {
  const _LoanPaymentPreview({
    required this.schedule,
    required this.currency,
  });

  final LoanAmortizationSchedule? schedule;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final value = schedule;
    return CompassCard(
      padding: const EdgeInsets.all(14),
      child: value == null
          ? Text(
              '填写完整条件后显示月供预览',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Row(
              children: [
                Expanded(
                  child: _LoanPreviewMetric(
                    label: '首期月供',
                    value: formatMoney(
                      value.regularPayment,
                      currency: currency,
                    ),
                  ),
                ),
                Expanded(
                  child: _LoanPreviewMetric(
                    label: '总利息',
                    value: formatMoney(
                      value.totalInterest,
                      currency: currency,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LoanPreviewMetric extends StatelessWidget {
  const _LoanPreviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: compassTabularFigures,
                  ),
            ),
          ),
        ],
      );
}
