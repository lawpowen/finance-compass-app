import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/loan_amortization.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';
import 'account_form_dialog.dart';

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
      ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;

  Account get _account => _repository.accounts.firstWhere(
        (item) => item.id == widget.account.id,
        orElse: () => widget.account,
      );

  @override
  void initState() {
    super.initState();
    _historicalCutoff = widget.cutoffDate;
    _initialPromptScheduled =
        widget.promptForPlannedGeneration && widget.cutoffDate == null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_historicalCutoff != null) return;
      final account = _account;
      if (!account.hasCompleteLoanProfile) return;
      final schedule = _scheduleFor(account);
      await _upgradeLegacyPlannedTransactions(account, schedule);
      if (widget.promptForPlannedGeneration && mounted) {
        await _offerPlannedGeneration(account, schedule);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final isHistorical = _historicalCutoff != null;
    final cutoffDate =
        _historicalCutoff ?? _repository.currentMonthCutoffDate();
    if (account.accountType != AccountType.loan ||
        !account.hasCompleteLoanProfile) {
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
                    children: [
                      const Icon(Icons.calculate_outlined, size: 48),
                      const SizedBox(height: 12),
                      const Text('设置金额、利率和年限后，系统会生成完整还款计划。'),
                      const SizedBox(height: 18),
                      if (!isHistorical)
                        CompassPrimaryButton(
                          label: '设置贷款条件',
                          onPressed: () => _editAccount(account),
                        )
                      else
                        const Text('历史统计状态不可修改贷款条件。'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final schedule = _scheduleFor(account);
    final paidNumbers = _paidInstallmentNumbers(
      account.id,
      cutoffDate: isHistorical ? cutoffDate : null,
    );
    final plannedNumbers = _plannedInstallmentNumbers(account.id);
    final missingPlannedCount = schedule.installments
        .where(
          (item) =>
              !paidNumbers.contains(item.number) &&
              !plannedNumbers.contains(item.number),
        )
        .length;
    final coveredPlannedCount =
        schedule.installments.length - missingPlannedCount;
    final nextInstallment =
        schedule.installments.cast<LoanInstallment?>().firstWhere(
              (item) => item != null && !paidNumbers.contains(item.number),
              orElse: () => null,
            );
    final outstanding =
        _repository.accountBalanceAt(account.id, cutoffDate).abs();

    return Scaffold(
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: compassPagePadding.copyWith(bottom: 36),
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
                    Text(isHistorical ? '截至当月剩余贷款' : '当前剩余贷款',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(outstanding, currency: account.currency),
                      key: const Key('loan-outstanding-balance'),
                      style: Theme.of(context).textTheme.headlineMedium,
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
                              schedule.totalInterest,
                              currency: account.currency,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '剩余还款',
                            value: formatMoney(
                              schedule.totalPayment,
                              currency: account.currency,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${_methodLabel(account.loanRepaymentMethod!)} · '
                      '${schedule.installments.length} 期待记录'
                      '${schedule.installments.length == account.loanTermMonths ? '' : ' · 原合同 ${account.loanTermMonths} 期'} · '
                      '年利率 ${account.loanAnnualInterestRate!.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (isHistorical)
                const CompassCard(
                  child: Row(
                    children: [
                      Icon(Icons.lock_clock_outlined,
                          color: FinanceColors.compassOrange),
                      SizedBox(width: 10),
                      Expanded(child: Text('历史统计为只读状态，不能记录或生成还款交易。')),
                    ],
                  ),
                )
              else if (nextInstallment != null)
                CompassPrimaryButton(
                  key: const Key('record-loan-installment'),
                  label: '记录第 ${nextInstallment.number} 期还款',
                  icon: Icons.payments_outlined,
                  onPressed: () => _recordInstallment(account, nextInstallment),
                )
              else
                const CompassCard(
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: FinanceColors.compassTeal),
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
                  onPressed: missingPlannedCount == 0
                      ? null
                      : () => _generatePlannedTransactions(account, schedule),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '待记录还款计划',
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
                  isPaid: paidNumbers.contains(item.number),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Set<int> _paidInstallmentNumbers(
    String accountId, {
    DateTime? cutoffDate,
  }) {
    final result = <int>{};
    final expression = RegExp(r'^贷款(?:月供|本金) #(\d+)$');
    for (final transaction in _repository.transactions) {
      if (cutoffDate != null &&
          transaction.transactionDate.isAfter(cutoffDate)) {
        continue;
      }
      if (!transaction.affectsBalance ||
          transaction.type != TransactionType.transfer ||
          transaction.toAccountId != accountId) {
        continue;
      }
      final match = expression.firstMatch(transaction.description ?? '');
      final number = match == null ? null : int.tryParse(match.group(1)!);
      if (number != null) result.add(number);
    }
    return result;
  }

  Future<void> _returnToCurrent() async {
    setState(() => _historicalCutoff = null);
    final account = _account;
    if (!account.hasCompleteLoanProfile) return;
    await _upgradeLegacyPlannedTransactions(account, _scheduleFor(account));
  }

  Set<int> _plannedInstallmentNumbers(String accountId) {
    final result = <int>{};
    final expression = RegExp(r'^贷款(?:月供|本金) #(\d+)$');
    for (final transaction in _repository.transactions) {
      if (transaction.status != TransactionStatus.planned ||
          transaction.type != TransactionType.transfer ||
          transaction.toAccountId != accountId) {
        continue;
      }
      final match = expression.firstMatch(transaction.description ?? '');
      final number = match == null ? null : int.tryParse(match.group(1)!);
      if (number != null) result.add(number);
    }
    return result;
  }

  LoanAmortizationSchedule _scheduleFor(Account account) =>
      calculateLoanAmortization(
        principal: account.loanPrincipal!,
        annualInterestRatePercent: account.loanAnnualInterestRate!,
        termMonths: account.loanTermMonths!,
        startDate: account.loanTrackingStartDate ?? account.loanStartDate!,
        paymentDay: account.loanPaymentDay!,
        method: account.loanRepaymentMethod!,
        quotedMonthlyPayment: account.loanQuotedMonthlyPayment,
        openingPrincipal: account.initialBalance.abs(),
      );

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

  Future<Account?> _choosePaymentAccount(Account loan) async {
    final sources = _repository.accounts
        .where(
          (item) =>
              item.id != loan.id &&
              item.reportGroup == ReportGroup.cash &&
              item.currency == loan.currency,
        )
        .toList();
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先建立一个 ${loan.currency} 资金账户。')),
      );
      return null;
    }
    return showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择还款账户', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...sources.map(
              (item) => ListTile(
                title: Text(item.name),
                subtitle: Text(item.currency),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePlannedTransactions(
    Account loan,
    LoanAmortizationSchedule schedule,
  ) async {
    final source = await _choosePaymentAccount(loan);
    if (!mounted || source == null) return;
    final paid = _paidInstallmentNumbers(loan.id);
    final planned = _plannedInstallmentNumbers(loan.id);
    final pending = schedule.installments
        .where((item) =>
            !paid.contains(item.number) && !planned.contains(item.number))
        .toList();
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
    final transactions = <FinanceTransaction>[];
    for (final installment in pending) {
      transactions.add(
        FinanceTransaction(
          id: '${buildId('txn_loan_payment_plan')}_${installment.number}',
          type: TransactionType.transfer,
          accountId: source.id,
          toAccountId: loan.id,
          amount: installment.payment,
          toAmount: installment.principal,
          currency: source.currency,
          toCurrency: loan.currency,
          transactionDate: installment.dueDate,
          status: TransactionStatus.planned,
          description: '贷款月供 #${installment.number}',
        ),
      );
    }
    await ref
        .read(transactionMutationsProvider.notifier)
        .addTransactions(transactions);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已生成 ${pending.length} 期预计还款交易。')),
    );
  }

  Future<void> _editAccount(Account account) async {
    final updated = await showDialog<Account>(
      context: context,
      builder: (_) => AccountFormDialog(initialAccount: account),
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
    final sources = _repository.accounts
        .where(
          (item) =>
              item.id != loan.id &&
              item.reportGroup == ReportGroup.cash &&
              item.currency == loan.currency,
        )
        .toList();
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先建立一个 ${loan.currency} 资金账户。')),
      );
      return;
    }
    final source = await showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择还款账户', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...sources.map(
              (item) => ListTile(
                title: Text(item.name),
                subtitle: Text(item.currency),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
            ),
          ],
        ),
      ),
    );
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

    final now = DateTime.now();
    final transactions = <FinanceTransaction>[
      FinanceTransaction(
        id: buildId('txn_loan_payment'),
        type: TransactionType.transfer,
        accountId: source.id,
        toAccountId: loan.id,
        amount: installment.payment,
        toAmount: installment.principal,
        currency: source.currency,
        toCurrency: loan.currency,
        transactionDate: now,
        description: '贷款月供 #${installment.number}',
      ),
    ];
    final plannedIds = _repository.transactions
        .where(
          (item) =>
              item.status == TransactionStatus.planned &&
              item.accountId == source.id &&
              _sameDay(item.transactionDate, installment.dueDate) &&
              ((item.type == TransactionType.transfer &&
                      item.toAccountId == loan.id &&
                      (item.description == '贷款月供 #${installment.number}' ||
                          item.description == '贷款本金 #${installment.number}')) ||
                  (item.type == TransactionType.expense &&
                      item.description == '贷款利息 #${installment.number}')),
        )
        .map((item) => item.id)
        .toList();
    if (plannedIds.isNotEmpty) {
      await ref
          .read(transactionMutationsProvider.notifier)
          .deleteTransactions(plannedIds);
    }
    await ref
        .read(transactionMutationsProvider.notifier)
        .addTransactions(transactions);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('第 ${installment.number} 期还款已记录')),
    );
  }

  Future<void> _upgradeLegacyPlannedTransactions(
    Account loan,
    LoanAmortizationSchedule schedule,
  ) async {
    final legacyTransfers = _repository.transactions.where(
      (item) =>
          item.status == TransactionStatus.planned &&
          item.type == TransactionType.transfer &&
          item.toAccountId == loan.id &&
          RegExp(r'^贷款本金 #\d+$').hasMatch(item.description ?? ''),
    );
    final replacements = <FinanceTransaction>[];
    final deleteIds = <String>[];
    for (final transfer in legacyTransfers) {
      final number = int.tryParse(
        RegExp(r'^贷款本金 #(\d+)$')
                .firstMatch(transfer.description ?? '')
                ?.group(1) ??
            '',
      );
      if (number == null) continue;
      final installment =
          schedule.installments.cast<LoanInstallment?>().firstWhere(
                (item) => item?.number == number,
                orElse: () => null,
              );
      if (installment == null) continue;
      deleteIds.add(transfer.id);
      deleteIds.addAll(
        _repository.transactions
            .where(
              (item) =>
                  item.status == TransactionStatus.planned &&
                  item.accountId == transfer.accountId &&
                  item.type == TransactionType.expense &&
                  item.description == '贷款利息 #$number' &&
                  _sameDay(item.transactionDate, transfer.transactionDate),
            )
            .map((item) => item.id),
      );
      replacements.add(
        FinanceTransaction(
          id: '${buildId('txn_loan_payment_plan_upgrade')}_$number',
          type: TransactionType.transfer,
          accountId: transfer.accountId,
          toAccountId: loan.id,
          amount: installment.payment,
          toAmount: installment.principal,
          currency: transfer.currency,
          toCurrency: loan.currency,
          recordDate: transfer.recordDate,
          transactionDate: transfer.transactionDate,
          status: TransactionStatus.planned,
          description: '贷款月供 #$number',
        ),
      );
    }
    if (deleteIds.isEmpty) return;
    await ref
        .read(transactionMutationsProvider.notifier)
        .deleteTransactions(deleteIds.toSet().toList());
    await ref
        .read(transactionMutationsProvider.notifier)
        .addTransactions(replacements);
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
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
          color: FinanceColors.compassOrange.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              color: FinanceColors.compassOrange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '历史统计 · 截至 ${cutoffDate.year}年${cutoffDate.month}月末',
              ),
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
            child: Text(value, style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
      );
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({
    required this.installment,
    required this.currency,
    required this.isPaid,
  });

  final LoanInstallment installment;
  final String currency;
  final bool isPaid;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('loan-installment-${installment.number}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: FinanceColors.compassBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
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
                    '${_date(installment.dueDate)} · '
                    '${isPaid ? '已记录' : '预计'}',
                    style: TextStyle(
                      color: isPaid
                          ? FinanceColors.compassTeal
                          : FinanceColors.compassMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '本金 ${formatMoney(installment.principal, currency: currency)} · '
                    '利息 ${formatMoney(installment.interest, currency: currency)}',
                    style: Theme.of(context).textTheme.bodySmall,
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
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '余 ${formatMoney(installment.remainingPrincipal, currency: currency)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      );
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
