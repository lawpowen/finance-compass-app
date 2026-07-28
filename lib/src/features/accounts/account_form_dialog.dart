import 'package:flutter/material.dart';

import '../../core/models/account.dart';
import '../../core/models/loan_amortization.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';

class AccountFormDialog extends StatefulWidget {
  const AccountFormDialog({
    super.key,
    this.initialAccount,
  });

  final Account? initialAccount;

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

  bool get isEdit => widget.initialAccount != null;

  @override
  void initState() {
    super.initState();
    final account = widget.initialAccount;
    nameController = TextEditingController(text: account?.name ?? '');
    institutionController =
        TextEditingController(text: account?.institution ?? '');
    currency = normalizeCurrency(account?.currency ?? 'MYR');
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
      text: (account?.loanAnnualInterestRate ?? 0).toStringAsFixed(2),
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
    reportGroup = account?.reportGroup ?? ReportGroup.cash;
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
                            isCreditCard ? '···· 1234 · $currency' : currency,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '启用中',
                            style: TextStyle(color: FinanceColors.compassTeal),
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
                      items: supportedCurrencies
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => currency = value);
                      },
                    ),
                  ),
                ),
                if (!isCreditCard) ...[
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
                        onChanged: (value) => setState(() {
                          if (value == null) return;
                          accountType = value;
                          reportGroup = _defaultReportGroupForType(value);
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
                        items: ReportGroup.values
                            .map(
                              (group) => DropdownMenuItem(
                                value: group,
                                child: Text(_groupLabel(group)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
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
                  const CompassSectionLabel('额度与余额'),
                  _AccountEditorRow(
                    icon: Icons.credit_card_rounded,
                    label: '信用额度',
                    child: _InlineTextEditor(
                      controller: creditLimitController,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _positiveNumberRequired,
                    ),
                  ),
                  _AccountEditorRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '当前欠款',
                    child: _InlineTextEditor(
                      controller: currentBalanceController,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _numberRequired,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'ⓘ  消费按交易日期自动归入对应账单',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const CompassSectionLabel('当前账期'),
                  const _AccountCyclePreview(),
                  const SizedBox(height: 12),
                  const _AccountEditorRow(
                    icon: Icons.image_outlined,
                    label: '账户图标',
                    child: Text('通用图标'),
                  ),
                  Text(
                    '银行图标将在未来版本提供',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else if (isLoan) ...[
                  const SizedBox(height: 16),
                  const CompassSectionLabel('贷款条件'),
                  _AccountEditorRow(
                    icon: Icons.request_quote_outlined,
                    label: '贷款金额',
                    child: _InlineTextEditor(
                      controller: loanPrincipalController,
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
                  const SizedBox(height: 8),
                  Text(
                    '中途开始记账时，填写截至开始日的剩余贷款；以前已还的期数不会生成交易。首期从开始日的下一个月计算。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const CompassSectionLabel('余额'),
                  _AccountEditorRow(
                    icon: Icons.savings_outlined,
                    label: '初始余额',
                    child: _InlineTextEditor(
                      controller: initialBalanceController,
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
                      controller: currentBalanceController,
                      prefixText: '$currency ',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _numberRequired,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                CompassPrimaryButton(label: '保存更改', onPressed: _submit),
                if (isEdit) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '停用账户',
                      style: TextStyle(color: FinanceColors.compassOrange),
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

  void _submit() {
    if (!formKey.currentState!.validate()) {
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
    final balance = isLoan
        ? -openingLoanBalance!
        : double.parse(initialBalanceController.text.trim());
    final currentBalance = isLoan
        ? -openingLoanBalance! + previousLoanPrincipalReduction
        : double.parse(currentBalanceController.text.trim());
    final quotedPayment = _optionalDouble(loanQuotedPaymentController.text);
    Navigator.of(context).pop(
      Account(
        id: widget.initialAccount?.id ?? buildId('acc'),
        name: nameController.text.trim(),
        accountType: accountType,
        reportGroup: reportGroup,
        currency: currency,
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
  String? _numberRequired(String? value) =>
      double.tryParse(value ?? '') == null ? '请输入数字' : null;

  String? _positiveNumberRequired(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed <= 0 ? '请输入大于 0 的金额' : null;
  }

  String? _dayRequired(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 1 || parsed > 31 ? '请输入 1–31' : null;
  }

  String? _nonNegativeNumberRequired(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? '请输入不小于 0 的数字' : null;
  }

  String? _optionalPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value);
    return parsed == null || parsed <= 0 ? '请输入大于 0 的金额' : null;
  }

  String? _loanTermRequired(String? value) {
    final months = _loanTermMonths(value);
    return months == null || months < 1 || months > 1200
        ? '请输入 1 个月至 100 年'
        : null;
  }

  int? _loanTermMonths(String? value) {
    final years = double.tryParse(value?.trim() ?? '');
    if (years == null || years <= 0) return null;
    final rawMonths = years * 12;
    final months = rawMonths.round();
    return (rawMonths - months).abs() <= .001 ? months : null;
  }

  double? _optionalDouble(String value) =>
      value.trim().isEmpty ? null : double.tryParse(value.trim());

  LoanAmortizationSchedule? _previewLoanSchedule() {
    final principal = double.tryParse(loanPrincipalController.text.trim());
    final rate = double.tryParse(loanInterestRateController.text.trim());
    final months = _loanTermMonths(loanTermYearsController.text);
    final paymentDay = int.tryParse(loanPaymentDayController.text.trim());
    if (principal == null ||
        principal <= 0 ||
        rate == null ||
        rate < 0 ||
        months == null ||
        paymentDay == null ||
        paymentDay < 1 ||
        paymentDay > 31) {
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
        quotedMonthlyPayment:
            loanRepaymentMethod != LoanRepaymentMethod.equalPrincipal
                ? _optionalDouble(loanQuotedPaymentController.text)
                : null,
        openingPrincipal:
            _optionalDouble(loanOpeningBalanceController.text) ?? principal,
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _pickLoanStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: loanStartDate,
      firstDate: DateTime(1950),
      lastDate: DateTime(2200),
    );
    if (selected != null) setState(() => loanStartDate = selected);
  }

  Future<void> _pickLoanTrackingStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: loanTrackingStartDate,
      firstDate: loanStartDate,
      lastDate: DateTime(2200),
    );
    if (selected != null) setState(() => loanTrackingStartDate = selected);
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

  ReportGroup _defaultReportGroupForType(AccountType type) {
    switch (type) {
      case AccountType.cash:
      case AccountType.bankSaving:
      case AccountType.eWallet:
        return ReportGroup.cash;
      case AccountType.creditCard:
      case AccountType.loan:
        return ReportGroup.credit;
      case AccountType.pension:
        return ReportGroup.retirement;
      case AccountType.moneyMarketFund:
      case AccountType.stock:
      case AccountType.crypto:
      case AccountType.trading:
      case AccountType.fund:
      case AccountType.other:
        return ReportGroup.investment;
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
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Icon(icon, color: FinanceColors.compassTeal, size: 21),
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
    this.validator,
    this.hintText,
    this.prefixText,
    this.suffixText,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final FormFieldValidator<String>? validator;
  final String? hintText;
  final String? prefixText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        key: fieldKey,
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
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
        ),
      );
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
            child: Text(value, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      );
}

class _AccountCyclePreview extends StatelessWidget {
  const _AccountCyclePreview();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('6月13日', '开始', false),
      ('7月12日', '已结算', false),
      ('7月28日', '还款', true),
      ('8月12日', '下期结算', false),
    ];
    return Column(
      children: [
        Row(
          children: List.generate(items.length, (index) {
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < 2
                          ? FinanceColors.compassTeal
                          : Colors.transparent,
                      border: Border.all(
                        width: 2,
                        color: items[index].$3
                            ? FinanceColors.compassOrange
                            : FinanceColors.compassTeal,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index < 2
                          ? FinanceColors.compassTeal
                          : index == 2
                              ? FinanceColors.compassOrange
                              : FinanceColors.compassBorder,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: items
              .map(
                (item) => Expanded(
                  child: Column(
                    children: [
                      Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: 11,
                          color: item.$3
                              ? FinanceColors.compassOrange
                              : FinanceColors.compassMuted,
                        ),
                      ),
                      Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 10,
                          color: item.$3
                              ? FinanceColors.compassOrange
                              : FinanceColors.compassMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
