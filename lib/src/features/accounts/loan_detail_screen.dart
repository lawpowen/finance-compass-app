import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/loan_amortization.dart';
import '../../core/models/loan_settlement.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../shared/compass_ui.dart';
import 'account_form_dialog.dart';
import 'repayment_account_picker.dart';
import 'unavailable_account_page.dart';

class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.account,
    required this.repository,
    this.promptForPlannedGeneration = false,
    this.cutoffDate,
  });

  final Account account;
  final FinanceRepository repository;
  final bool promptForPlannedGeneration;
  final DateTime? cutoffDate;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  bool _initialPromptScheduled = false;
  DateTime? _historicalCutoff;

  FinanceRepository get _repository =>
      ref.read(financeRepositoryProvider).valueOrNull ?? widget.repository;

  Account? _findAccount(FinanceRepository ledger) => identical(ledger.database, widget.repository.database)
      ? ledger.accounts.where((a) => a.id == widget.account.id && a.accountType == AccountType.loan).firstOrNull
      : null;

  @override
  void initState() {
    super.initState();
    _historicalCutoff = widget.cutoffDate;
    _initialPromptScheduled =
        widget.promptForPlannedGeneration && widget.cutoffDate == null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_historicalCutoff != null) return;
      final account = _findAccount(_repository);
    if (account == null) return;
      final schedule = _tryScheduleFor(account);
      if (schedule == null || !account.isActive) return;
      await _upgradeLegacyPlannedTransactions(account);
      if (widget.promptForPlannedGeneration && mounted) {
        await _offerPlannedGeneration(account, schedule);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final account = _findAccount(ledger);
    if (account == null) return const UnavailableAccountPage();
    final isHistorical = _historicalCutoff != null;
    final today = DateTime.now();
    final cutoffDate = _historicalCutoff ??
        DateTime(today.year, today.month, today.day, 23, 59, 59, 999, 999);
    final schedule = account.accountType == AccountType.loan
        ? _tryScheduleFor(account)
        : null;
    if (account.accountType != AccountType.loan || schedule == null) {
      final hasFields = account.hasCompleteLoanProfile;
      return Scaffold(
        body: CompassBackground(
          child: SafeArea(
            child: ListView(
              padding: compassPagePadding,
              children: [
                CompassPageHeader(
                  title: account.name,
                  subtitle: '贷款条件待设置',
                  leading: CompassBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 24),
                CompassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CompassHelpHeading(
                        title: Text('还款计划',
                            style: Theme.of(context).textTheme.titleMedium),
                        label: '贷款条件',
                        message: hasFields
                            ? '贷款合同参数不完整或无效，请编辑修正后再查看还款计划。'
                            : isHistorical
                                ? '设置金额、利率和年限后，系统会生成还款计划。历史统计状态不可修改贷款条件。'
                                : '设置金额、利率和年限后，系统会生成还款计划。',
                      ),
                      const SizedBox(height: 8),
                      if (!isHistorical)
                        CompassPrimaryButton(
                          label: hasFields ? '修正贷款条件' : '设置贷款条件',
                          onPressed: () => _editAccount(account),
                        )
                      else
                        const Text('历史状态只读'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final allocations = LoanSettlement.forLoan(
        loanId: account.id,
        currency: account.currency,
        transactions: _repository.transactions,
        cutoff: cutoffDate,
        includeRecords: isHistorical);
    final residuals = {
      for (final item in schedule.installments)
        item.number: allocations.remaining(item)
    };
    final unpaid = residuals.values.where((item) => item.payment > 0).toList();
    final booked = isHistorical
        ? allocations
        : LoanSettlement.forLoan(
            loanId: account.id,
            currency: account.currency,
            transactions: ledger.transactions,
            includeRecords: true,
          );
    final available = isHistorical
        ? residuals
        : {
            for (final item in schedule.installments)
              item.number: installmentAvailableToRecord(item, allocations, booked),
          };
    final awaitingPosting =
        unpaid.where((item) => available[item.number]!.payment == 0).length;
    final remainingInterest = unpaid.fold<int>(
            0, (cents, item) => cents + (item.interest * 100).round()) /
        100;
    final remainingPayment = unpaid.fold<int>(
            0, (cents, item) => cents + (item.payment * 100).round()) /
        100;
    final missingPlannedCount = isHistorical
        ? 0
        : unplannedLoanInstallments(
                loanId: account.id,
                currency: account.currency,
                transactions: _repository.transactions,
                schedule: schedule)
            .length;
    final coveredPlannedCount =
        schedule.installments.length - missingPlannedCount;
    final nextDue = schedule.installments
        .where((item) => residuals[item.number]!.payment > 0)
        .firstOrNull;
    final nextInstallment = isHistorical || nextDue == null
        ? null
        : available[nextDue.number];
    final balance = _repository.accountBalanceAt(account.id, cutoffDate);
    final outstanding = (-balance).clamp(0.0, double.infinity).toDouble();

    final sidePadding =
        math.max(20.0, (MediaQuery.sizeOf(context).width - 840) / 2);

    return Scaffold(
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: compassScrollPadding(
              context,
              EdgeInsets.fromLTRB(sidePadding, 16, sidePadding, 36),
            ),
            children: [
              CompassPageHeader(
                title: account.name,
                subtitle:
                    '${account.institution ?? '贷款账户'} · ${account.currency}',
                leading: CompassBackButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: isHistorical
                    ? const []
                    : [
                        IconButton(
                          tooltip: '编辑贷款',
                          onPressed: () => _editAccount(account),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
              ),
              if (isHistorical) ...[
                const SizedBox(height: 12),
                _HistoricalLoanBanner(
                  cutoffDate: cutoffDate,
                  onReturnCurrent: _returnToCurrent,
                ),
              ],
              const SizedBox(height: 18),
              CompassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (moneyDisplayParts(balance).sign > 0)
                      Text(
                          '贷款溢还 ${formatMoney(balance, currency: account.currency)}'),
                    Text(isHistorical ? '截至当月剩余贷款' : '当前剩余贷款',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(outstanding, currency: account.currency),
                      key: const Key('loan-outstanding-balance'),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: compassTabularFigures,
                              ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: _paymentLabel(account.loanRepaymentMethod!),
                            value: formatMoney(
                              schedule.regularPayment,
                              currency: account.currency,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '剩余利息',
                            value: formatMoney(
                              remainingInterest,
                              currency: account.currency,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '剩余还款',
                            value: formatMoney(
                              remainingPayment,
                              currency: account.currency,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${_methodLabel(account.loanRepaymentMethod!)} · '
                      '${unpaid.length} 期未付清'
                      '${awaitingPosting > 0 ? '（其中 $awaitingPosting 期已确认待入账）' : ''}'
                      '${schedule.installments.length == account.loanTermMonths ? '' : ' · 原合同 ${account.loanTermMonths} 期'} · '
                      '年利率 ${account.loanAnnualInterestRate!}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!isHistorical) const SizedBox(height: 14),
              if (!isHistorical && nextInstallment != null)
                CompassPrimaryButton(
                  key: const Key('record-loan-installment'),
                  label: nextInstallment.payment > 0
                      ? '记录第 ${nextInstallment.number} 期还款'
                      : '第 ${nextInstallment.number} 期已有未来实还记录',
                  icon: Icons.payments_outlined,
                  onPressed: account.isActive && nextInstallment.payment > 0
                      ? () => _recordInstallment(account, nextInstallment)
                      : null,
                )
              else if (!isHistorical)
                CompassCard(
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: financePaletteOf(context).seed),
                      SizedBox(width: 10),
                      Text('全部计划期数均已记录'),
                    ],
                  ),
                ),
              if (!isHistorical) ...[
                const SizedBox(height: 10),
                CompassPrimaryButton(
                  key: const Key('generate-loan-planned-transactions'),
                  label: missingPlannedCount == 0
                      ? '预计交易已补齐'
                      : coveredPlannedCount == 0
                          ? '生成 $missingPlannedCount 期预计交易'
                          : '补齐 $missingPlannedCount 期预计交易',
                  icon: Icons.event_repeat_outlined,
                  outlined: true,
                  onPressed: !account.isActive || missingPlannedCount == 0
                      ? null
                      : () => _generatePlannedTransactions(account, schedule),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '还款计划与流水',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text('${schedule.installments.length} 期'),
                ],
              ),
              const SizedBox(height: 10),
              ...schedule.installments.map(
                (item) => _InstallmentRow(
                  installment: item,
                  currency: account.currency,
                  remaining: residuals[item.number]!,
                  available: available[item.number]!,
                  records: booked.recordsFor(item.number),
                  accountName: ledger.accountName,
                  cutoff: cutoffDate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _returnToCurrent() async {
    setState(() => _historicalCutoff = null);
    final account = _findAccount(_repository);
    if (account == null || !account.isActive) return;
    final schedule = _tryScheduleFor(account);
    if (schedule == null) return;
    await _upgradeLegacyPlannedTransactions(account);
  }

  LoanAmortizationSchedule? _tryScheduleFor(Account account) =>
      tryCalculateLoanScheduleForAccount(account);

  Future<void> _offerPlannedGeneration(
    Account loan,
    LoanAmortizationSchedule schedule,
  ) async {
    if (!_initialPromptScheduled || !mounted) return;
    _initialPromptScheduled = false;
    final shouldGenerate = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('生成预计还款交易？'),
            content: Text(
              '可选择还款账户，并把 ${schedule.installments.length} 期完整月供写入未来交易。现金账户按月供扣款，贷款余额只减少其中的本金；以前已经偿还的期数不会生成。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('暂不生成'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('选择账户并生成'),
              ),
            ],
          ),
        ) ??
        false;
    if (shouldGenerate && mounted) {
      await _generatePlannedTransactions(loan, schedule);
    }
  }

  Future<Account?> _choosePaymentAccount(Account loan) =>
      pickRepaymentAccount(context, _repository, loan);

  Future<void> _generatePlannedTransactions(
    Account loan,
    LoanAmortizationSchedule schedule,
  ) async {
    final source = await _choosePaymentAccount(loan);
    if (!mounted || source == null) return;
    final pending = unplannedLoanInstallments(
        loanId: loan.id,
        currency: loan.currency,
        transactions: _repository.transactions,
        schedule: schedule);
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全部待还期数已经有预计交易。')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('生成全部预计交易'),
            content: Text(
              '将从 ${source.name} 生成 ${pending.length} 期预计还款，共 ${formatMoney(pending.fold<double>(0, (sum, item) => sum + item.payment), currency: loan.currency)}。预计交易不会立即改变账户余额。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('生成'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final count = await ref
        .read(transactionMutationsProvider.notifier)
        .generateLoanInstallmentPlans(
            loanId: loan.id, payerId: source.id, confirmed: pending);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(count > 0 ? '已生成 $count 期预计还款交易。' : '还款计划已更新，请重新查看。')),
    );
  }

  Future<void> _editAccount(Account account) async {
    final live = ref.read(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final updated = await showDialog<Account>(
      context: context,
      builder: (_) => AccountFormDialog.edit(account, live),
    );
    if (!mounted || updated == null) return;
    await ref.read(accountMutationsProvider.notifier).updateAccount(updated);
    if (mounted && updated.accountType != AccountType.loan) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _recordInstallment(
    Account loan,
    LoanInstallment installment,
  ) async {
    final source = await _choosePaymentAccount(loan);
    if (!mounted || source == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('记录第 ${installment.number} 期还款'),
            content: Text(
              '从 ${source.name} 支付 '
              '${formatMoney(installment.payment, currency: loan.currency)}\n'
              '本金 ${formatMoney(installment.principal, currency: loan.currency)} · '
              '利息 ${formatMoney(installment.interest, currency: loan.currency)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认记录'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;

    final recorded = await ref
        .read(transactionMutationsProvider.notifier)
        .recordLoanInstallment(
            loanId: loan.id, payerId: source.id, confirmed: installment);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(recorded
              ? '第 ${installment.number} 期还款已记录'
              : '本期剩余款项已更新，请重新确认。')),
    );
  }

  Future<void> _upgradeLegacyPlannedTransactions(Account loan) async {
    if (_repository.transactions.any((tx) =>
        tx.legacyLoanId == loan.id &&
        tx.legacyLoanPartNumber != null &&
        tx.status == TransactionStatus.planned)) {
      await ref
          .read(transactionMutationsProvider.notifier)
          .consolidateLegacyLoanPlans(loan.id);
    }
  }
}

class _HistoricalLoanBanner extends StatelessWidget {
  const _HistoricalLoanBanner({
    required this.cutoffDate,
    required this.onReturnCurrent,
  });

  final DateTime cutoffDate;
  final VoidCallback onReturnCurrent;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('loan-historical-banner'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: financePaletteOf(context).expense.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.history_rounded,
              color: financePaletteOf(context).expense,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '历史统计 · 截至 ${cutoffDate.year}年${cutoffDate.month}月末 · 只读',
              ),
            ),
            const CompassHelpButton(
              title: '贷款历史统计',
              message: '历史统计为只读状态，不能记录或生成还款交易。切换到当前后可继续处理。',
            ),
            TextButton(
              key: const Key('loan-return-current'),
              onPressed: onReturnCurrent,
              child: const Text('切换到当前'),
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

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
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFeatures: compassTabularFigures,
                  ),
            ),
          ),
        ],
      );
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({
    required this.installment,
    required this.currency,
    required this.remaining,
    required this.available,
    required this.records,
    required this.accountName,
    required this.cutoff,
  });

  final LoanInstallment installment;
  final String currency;
  final LoanInstallment remaining;
  final LoanInstallment available;
  final List<LoanPaymentRecord> records;
  final String Function(String) accountName;
  final DateTime cutoff;
  bool get isPaid => remaining.payment == 0;
  bool get isPartial => !isPaid && remaining.payment != installment.payment;
  int get pendingCents =>
      (remaining.payment * 100).round() - (available.payment * 100).round();

  String get statusLabel {
    if (isPaid) return '已记录';
    if (available.payment == 0) return isPartial ? '部分已还，余款待入账' : '已确认，待入账';
    if (isPartial) return '部分还款';
    return pendingCents > 0 ? '部分已确认，待入账' : '预计';
  }

  @override
  Widget build(BuildContext context) => Container(
        key: Key('loan-installment-${installment.number}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: financePaletteOf(context).border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _contractSummary(context),
            if (records.isNotEmpty) ...[
              const Divider(),
              Text('还款流水', style: Theme.of(context).textTheme.labelMedium),
              for (final record in records)
                _LoanPaymentLine(
                  key: Key('loan-payment-${record.transaction.id}'),
                  record: record,
                  payer: accountName(record.transaction.accountId),
                  currency: currency,
                  pending: record.transaction.transactionDate.isAfter(cutoff),
                ),
            ],
          ],
        ),
      );

  Widget _contractSummary(BuildContext context) => Row(
          children: [
            SizedBox(
              width: 36,
              child: Text('#${installment.number}'),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_date(installment.dueDate)} · $statusLabel',
                    style: TextStyle(
                      color: isPaid
                          ? financePaletteOf(context).income
                          : financePaletteOf(context).textMuted,
                      fontWeight: isPaid ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (isPartial)
                    Text(
                        '待付 ${formatMoney(remaining.payment, currency: currency)}'),
                  if (pendingCents > 0 && available.payment > 0)
                    Text('其中待入账 ${formatMoney(pendingCents / 100, currency: currency)}'),
                  const SizedBox(height: 3),
                  Text(
                    '本金 ${formatMoney(installment.principal, currency: currency)} · '
                    '利息 ${formatMoney(installment.interest, currency: currency)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFeatures: compassTabularFigures,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(installment.payment, currency: currency),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontFeatures: compassTabularFigures,
                      ),
                ),
                Text(
                  '余 ${formatMoney(installment.remainingPrincipal, currency: currency)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFeatures: compassTabularFigures,
                      ),
                ),
              ],
            ),
          ],
      );
}

class _LoanPaymentLine extends StatelessWidget {
  const _LoanPaymentLine({
    super.key,
    required this.record,
    required this.payer,
    required this.currency,
    required this.pending,
  });

  final LoanPaymentRecord record;
  final String payer;
  final String currency;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final tx = record.transaction;
    final status = tx.amount.isNegative
        ? (pending ? '冲正待入账' : '已冲正')
        : (pending ? '待入账' : '已还款');
    final principalLabel = tx.amount.isNegative ? '冲正本金' : pending ? '待入账本金' : '实还本金';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_date(tx.transactionDate.toLocal())} · $payer · '
            '$status ${formatMoney(tx.amount, currency: tx.currency)}',
          ),
          Text(
            '$principalLabel ${formatMoney(record.principalCents / 100, currency: currency)} · '
            '利息 ${formatMoney(record.interestCents / 100, currency: currency)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _methodLabel(LoanRepaymentMethod method) => switch (method) {
      LoanRepaymentMethod.equalInstallment => '等额本息',
      LoanRepaymentMethod.equalPrincipal => '等额本金',
      LoanRepaymentMethod.flatRate => '平息贷款',
    };

String _paymentLabel(LoanRepaymentMethod method) =>
    method == LoanRepaymentMethod.equalPrincipal ? '首期月供' : '每月月供';
