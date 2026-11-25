import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared/category_icons.dart';

import '../shared/finance_amount_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/credit_card_billing.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_theme.dart';
import '../shared/card_posting_date_field.dart';
import '../shared/compass_ui.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';
import 'account_form_dialog.dart';
import 'repayment_account_picker.dart';
import 'unavailable_account_page.dart';

class CreditCardDetailScreen extends ConsumerStatefulWidget {
  const CreditCardDetailScreen({
    super.key,
    required this.account,
    required this.repository,
    this.cutoffDate,
  });

  final Account account;
  final FinanceRepository repository;
  final DateTime? cutoffDate;

  @override
  ConsumerState<CreditCardDetailScreen> createState() =>
      _CreditCardDetailScreenState();
}

class _CreditCardDetailScreenState
    extends ConsumerState<CreditCardDetailScreen> {
  int selectedStatement = 0;
  DateTime? selectedHistoricalStatementDate;
  DateTime? _historicalCutoff;

  @override
  void initState() {
    super.initState();
    _historicalCutoff = widget.cutoffDate;
  }

  @override
  Widget build(BuildContext context) {
    final liveRepository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final liveAccount = liveRepository.accounts.where((a) => a.id == widget.account.id).firstOrNull;
    if (!identical(liveRepository.database, widget.repository.database) ||
        liveAccount == null || liveAccount.accountType != AccountType.creditCard) {
      return const UnavailableAccountPage();
    }
    final isHistoricalCutoff = _historicalCutoff != null;
    final now = _historicalCutoff ?? DateTime.now();
    final scopedTransactions = isHistoricalCutoff
        ? liveRepository.transactions
            .where(
              (item) => !item.transactionDate.isAfter(now),
            )
            .toList()
        : liveRepository.transactions;
    final statementDay = liveAccount.statementDay ?? 12;
    final paymentDay = liveAccount.paymentDueDay ?? 28;
    final currentPeriod = calculateCreditCardBillingPeriod(
      statementDay: statementDay,
      paymentDueDay: paymentDay,
      now: now,
    );
    final summary = liveRepository.creditCardBillingSummary(
      liveAccount.id,
      cutoffDate: isHistoricalCutoff ? now : null,
      now: now,
    );
    final limit = liveAccount.creditLimit;
    final usageAmount = liveRepository.creditCardOutstandingBalance(
      liveAccount.id,
      cutoffDate: isHistoricalCutoff ? now : null,
    );
    final usage = limit != null && limit.isFinite && limit > 0
        ? (usageAmount / limit).clamp(0, 1).toDouble()
        : null;
    final unpaidPeriod =
        summary.openStatements.firstOrNull?.period ?? currentPeriod;
    final isSelectedStatement = selectedHistoricalStatementDate != null;
    final period = isSelectedStatement
        ? calculateCreditCardBillingPeriodForStatement(
            statementDay: statementDay,
            paymentDueDay: paymentDay,
            statementDate: selectedHistoricalStatementDate!,
          )
        : unpaidPeriod;
    final isFutureStatement = isSelectedStatement &&
        period.statementDate.isAfter(currentPeriod.statementDate);
    final billedPurchases = _presentedPurchases(
      liveRepository,
      liveAccount,
      period,
      unbilled: false,
      cutoffDate: isHistoricalCutoff ? now : null,
    );
    final unbilledPurchases = _presentedPurchases(
      liveRepository,
      liveAccount,
      currentPeriod,
      unbilled: true,
      cutoffDate: isHistoricalCutoff ? now : null,
    );
    final purchases = isSelectedStatement || selectedStatement == 0
        ? billedPurchases
        : unbilledPurchases;
    final displayState = resolveCreditCardDisplayState(
      summary: summary,
      hasBilledActivity: hasCreditCardBilledActivity(
        account: liveAccount,
        transactions: scopedTransactions,
        now: now,
      ),
      now: now,
      committedOutstanding: usageAmount,
    );
    final palette = financePaletteOf(context);
    final display = isSelectedStatement
        ? _selectedStatementDisplay(
            period,
            calculateCreditCardOriginalStatementAmount(
              accountId: liveAccount.id,
              transactions: scopedTransactions,
              period: period,
              statementAmountOverride:
                  liveRepository.creditCardStatementAmountOverride(
                liveAccount.id,
                period.statementDate,
              ),
            ),
            palette,
            isFuture: isFutureStatement,
            isCurrent: period.statementDate == currentPeriod.statementDate,
          )
        : _creditCardDisplayCopy(
            displayState,
            summary,
            now,
            palette,
            currentDebt: usageAmount,
          );
    final sidePadding =
        math.max(20.0, (MediaQuery.sizeOf(context).width - 840) / 2);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: compassScrollPadding(
              context,
              EdgeInsets.fromLTRB(sidePadding, 12, sidePadding, 28),
            ),
            children: [
              Row(
                children: [
                  const CompassBackButton(),
                  const SizedBox(width: 14),
                  const CompassIconBadge(
                    icon: Icons.credit_card_rounded,
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      liveAccount.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isHistoricalCutoff)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        if (value == 'settings') {
                          _editAccount(context, liveAccount);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'settings', child: Text('账户设置')),
                      ],
                    ),
                ],
              ),
              if (isHistoricalCutoff) ...[
                const SizedBox(height: 14),
                _HistoricalCreditCardBanner(
                  cutoffDate: now,
                  onReturnCurrent: () => setState(() {
                    _historicalCutoff = null;
                    selectedHistoricalStatementDate = null;
                    selectedStatement = 0;
                  }),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(display.amountLabel,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              compassMoney(display.amount,
                                  currency: liveAccount.currency),
                              style: TextStyle(
                                color: display.color,
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                fontFeatures: compassTabularFigures,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StatusPill(
                          label: display.statusLabel,
                          color: display.color,
                        ),
                        if (!isSelectedStatement &&
                            summary.openStatements.length > 1)
                          Text(
                            '其余已出账待还 ${compassMoney(summary.openStatements.skip(1).fold<double>(0, (sum, bill) => sum + bill.amount), currency: liveAccount.currency)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Column(
                      children: [
                        CompassPrimaryButton(
                          key: const Key('record-credit-card-repayment'),
                          label: display.paymentActionLabel,
                          height: 42,
                          onPressed: liveAccount.isActive && display.canRepay && !isHistoricalCutoff
                              ? () => _addRepayment(
                                    context,
                                    liveRepository,
                                    liveAccount,
                                    // A cleared cycle may still carry debt
                                    // billed in later cycles; suggest it.
                                    display.amount > 0.005
                                        ? display.amount
                                        : usageAmount,
                                  )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          key: const Key('credit-card-statement-picker'),
                          onPressed: () => _selectStatementPeriod(
                            context,
                            liveRepository,
                            liveAccount,
                            currentPeriod,
                            unpaidPeriod,
                            now,
                            scopedTransactions,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            foregroundColor: financePaletteOf(context).seed,
                          ),
                          child: const Text('查看账单'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              compassHairline,
              const SizedBox(height: 22),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: CompassHelpHeading(
                  title: Text('账单周期时间线',
                      style: Theme.of(context).textTheme.titleMedium),
                  label: '账单周期',
                  message: '消费、转出与退款按发生日归入账单；还款优先偿还最早的未清账期。',
                ),
              ),
              const SizedBox(height: 10),
              _BillingTimeline(
                now: now,
                period: period,
                dueStatusLabel: display.dueStatusLabel,
                dueNeedsAttention: display.dueNeedsAttention,
                showToday: !isSelectedStatement,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const CompassIconBadge(
                    icon: Icons.bar_chart_rounded,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    usage == null ? '额度使用 —' : '额度使用 ${(usage * 100).round()}%',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${compassMoney(usageAmount, currency: liveAccount.currency)} / '
                        '${usage == null ? '未设置额度' : compassMoney(limit!, currency: liveAccount.currency)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFeatures: compassTabularFigures,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: usage ?? 0,
                minHeight: 6,
                borderRadius: BorderRadius.circular(8),
                color: financePaletteOf(context).seed,
                backgroundColor: financePaletteOf(context).border,
              ),
              const SizedBox(height: 18),
              compassHairline,
              if (isSelectedStatement)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${period.billingMonthDate.year}年${period.billingMonthDate.month}月${isFutureStatement ? '已确定' : period.statementDate == currentPeriod.statementDate ? '本期' : '历史'}账单',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        selectedHistoricalStatementDate = null;
                        selectedStatement = 0;
                      }),
                      child: const Text('返回本期'),
                    ),
                  ],
                )
              else
                CompassSegmentedControl(
                  labels: [
                    unpaidPeriod.statementDate
                            .isBefore(currentPeriod.statementDate)
                        ? '最早未还账单'
                        : '本期账单',
                    '未出账'
                  ],
                  selectedIndex: selectedStatement,
                  onChanged: (value) =>
                      setState(() => selectedStatement = value),
                ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      isSelectedStatement || selectedStatement == 0
                          ? '账单周期 ${_shortDate(period.cycleStartDate)}—${_shortDate(period.statementDate)} · 共 ${purchases.length} 笔'
                          : '未出账周期 ${_shortDate(currentPeriod.statementDate.add(const Duration(days: 1)))}—${_shortDate(currentPeriod.nextStatementDate)} · 共 ${purchases.length} 笔',
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: isHistoricalCutoff
                        ? const Text('历史状态只读')
                        : TextButton(
                            onPressed: () => _editAccount(context, liveAccount),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('查看账期规则'),
                                Icon(Icons.chevron_right_rounded, size: 18),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
              if (purchases.isNotEmpty)
                ...purchases.take(4).map(
                      (item) => Column(
                        children: [
                          _PurchaseRow(
                            item: item,
                            onTap: isHistoricalCutoff
                                ? null
                                : () => _editTransaction(
                                      context,
                                      liveRepository,
                                      item.transaction,
                                    ),
                          ),
                          compassHairline,
                        ],
                      ),
                    )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      selectedStatement == 0 ? '本账期没有信用卡明细' : '当前没有未出账明细',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              TextButton(
                onPressed: purchases.isEmpty
                    ? null
                    : () => _showAllPurchases(
                          context,
                          liveRepository,
                          purchases,
                          isSelectedStatement
                              ? '${period.billingMonthDate.year}年${period.billingMonthDate.month}月${isFutureStatement ? '已确定' : period.statementDate == currentPeriod.statementDate ? '本期' : '历史'}账单明细'
                              : selectedStatement == 0
                                  ? '本期账单明细'
                                  : '未出账明细',
                          editable: !isHistoricalCutoff,
                        ),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                child: Row(
                  children: [
                    Text('查看全部 ${purchases.length} 笔'),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectStatementPeriod(
    BuildContext context,
    FinanceRepository repository,
    Account account,
    CreditCardBillingPeriod currentPeriod,
    CreditCardBillingPeriod unpaidPeriod,
    DateTime now,
    List<FinanceTransaction> scopedTransactions,
  ) async {
    if (!account.hasCompleteCreditCardProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置结算日和还款日，才能查看账单月份。')),
      );
      return;
    }
    final periods = availableCreditCardBillingPeriods(
      account: account,
      transactions: scopedTransactions,
      now: now,
    );
    final selected = await showModalBottomSheet<CreditCardBillingPeriod>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择账单月份',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              compassHairline,
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: periods.length,
                  separatorBuilder: (_, __) => compassHairline,
                  itemBuilder: (_, index) {
                    final item = periods[index];
                    final isCurrent =
                        item.statementDate == currentPeriod.statementDate;
                    final isFuture =
                        item.statementDate.isAfter(currentPeriod.statementDate);
                    final isSelected = item.statementDate ==
                        (selectedHistoricalStatementDate ??
                            unpaidPeriod.statementDate);
                    final amount = calculateCreditCardOriginalStatementAmount(
                      accountId: account.id,
                      transactions: scopedTransactions,
                      period: item,
                      statementAmountOverride:
                          repository.creditCardStatementAmountOverride(
                        account.id,
                        item.statementDate,
                      ),
                    );
                    return ListTile(
                      key: Key(
                        'credit-card-statement-${item.statementDate.year}-${item.statementDate.month}',
                      ),
                      onTap: () => Navigator.pop(sheetContext, item),
                      leading: const CompassIconBadge(
                        icon: Icons.receipt_long_outlined,
                        size: 38,
                        outlined: true,
                      ),
                      title: Text(
                        '${item.billingMonthDate.year}年${item.billingMonthDate.month}月账单${isFuture ? ' · 已确定' : isCurrent ? ' · 本期' : ''}',
                      ),
                      subtitle: Text(
                        '${_shortDate(item.cycleStartDate)}—${_shortDate(item.statementDate)} · 还款日 ${_shortDate(item.dueDate)}',
                      ),
                      trailing: SizedBox(
                        width: 132,
                        child: Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  compassMoney(
                                    amount,
                                    currency: account.currency,
                                  ),
                                  style: TextStyle(
                                    color: amount > 0
                                        ? financePaletteOf(context).expense
                                        : financePaletteOf(context).textMuted,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.chevron_right_rounded,
                              color: isSelected
                                  ? financePaletteOf(context).seed
                                  : financePaletteOf(context).textMuted,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      // The picker opens the original statement even when that statement
      // also supplies the live oldest unpaid balance.
      selectedHistoricalStatementDate = selected.statementDate;
      selectedStatement = 0;
    });
  }

  Future<void> _editAccount(BuildContext context, Account current) async {
    final live = ref.read(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final updated = await showDialog<Account>(
      context: context,
      builder: (_) => AccountFormDialog.edit(current, live),
    );
    if (updated != null) {
      await ref.read(accountMutationsProvider.notifier).updateAccount(updated);
    }
  }

  Future<void> _showAllPurchases(
    BuildContext context,
    FinanceRepository repository,
    List<_PresentedPurchase> purchases,
    String title, {
    required bool editable,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...purchases.map(
                (item) => _PurchaseRow(
                  item: item,
                  onTap: editable
                      ? () {
                          Navigator.pop(sheetContext);
                          _editTransaction(
                              context, repository, item.transaction);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addRepayment(
    BuildContext context,
    FinanceRepository repo,
    Account card,
    double suggestedAmount,
  ) async {
    final source = await pickRepaymentAccount(context, repo, card);
    if (!context.mounted || source == null) return;

    final payment = await showDialog<
        ({double amount, DateTime date, DateTime? postingDate})>(
      context: context,
      builder: (_) => _CreditCardRepaymentDialog(
        card: card,
        source: source,
        suggestedAmount: suggestedAmount,
      ),
    );
    if (!context.mounted || payment == null) return;

    try {
      await ref.read(financeRepositoryProvider.notifier).mutate((current) {
        if (!identical(current.database, repo.database)) {
          throw const FormatException('账本已切换，请重新选择还款账户。');
        }
        return current.recordCreditCardRepayment(
          card: card,
          source: source,
          amount: payment.amount,
          paymentDate: payment.date,
          cardPostingDate: payment.postingDate,
        );
      });
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已从 ${source.name} 记录信用卡还款')),
    );
  }

  Future<void> _editTransaction(
    BuildContext context,
    FinanceRepository repository,
    FinanceTransaction transaction,
  ) async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionComposerPage(
          repository: repository,
          draft: transaction,
          editExisting: true,
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
    if (result.transactions.length != 1) return;
    await mutations.updateTransaction(result.transactions.single);
  }
}

class _CreditCardRepaymentDialog extends StatefulWidget {
  const _CreditCardRepaymentDialog({
    required this.card,
    required this.source,
    required this.suggestedAmount,
  });

  final Account card;
  final Account source;
  final double suggestedAmount;

  @override
  State<_CreditCardRepaymentDialog> createState() =>
      _CreditCardRepaymentDialogState();
}

class _CreditCardRepaymentDialogState
    extends State<_CreditCardRepaymentDialog> {
  late final amountController = TextEditingController(
    text: widget.suggestedAmount.toStringAsFixed(2),
  );
  DateTime date = DateUtils.dateOnly(DateTime.now());
  DateTime? postingDate;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      date = DateUtils.dateOnly(picked);
      if (postingDate != null && date.isAfter(postingDate!)) postingDate = null;
    });
  }

  void _confirm() {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || !amount.isFinite || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入大于 0 的还款金额。')),
      );
      return;
    }
    Navigator.pop(context, (amount: amount, date: date, postingDate: postingDate));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('记录信用卡还款'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('从 ${widget.source.name} 转账至 ${widget.card.name}'),
            const SizedBox(height: 14),
            FinanceAmountField(
              key: const Key('credit-card-repayment-amount'),
              controller: amountController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '还款金额',
                prefixText: '${widget.card.currency} ',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('credit-card-repayment-date'),
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('还款日期 ${date.year}年${_shortDate(date)}'),
            ),
            if (widget.source.accountType == AccountType.creditCard)
              CardPostingDateField(
                source: widget.source,
                transactionDate: date,
                value: postingDate,
                repayment: true,
                onChanged: (day) => setState(() => postingDate = day),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            key: const Key('credit-card-repayment-confirm'),
            onPressed: _confirm,
            child: const Text('确认记录'),
          ),
        ],
      );
}

class _HistoricalCreditCardBanner extends StatelessWidget {
  const _HistoricalCreditCardBanner({
    required this.cutoffDate,
    required this.onReturnCurrent,
  });

  final DateTime cutoffDate;
  final VoidCallback onReturnCurrent;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('credit-card-historical-banner'),
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
                '历史统计 · 截至 ${cutoffDate.year}年${cutoffDate.month}月末',
              ),
            ),
            const CompassHelpButton(
              title: '信用卡历史统计',
              message: '月末账单和消费记录为只读。切换到当前后可调整账期、编辑交易和记录还款。',
            ),
            TextButton(
              key: const Key('credit-card-return-current'),
              onPressed: onReturnCurrent,
              child: const Text('切换到当前'),
            ),
          ],
        ),
      );
}

class _BillingTimeline extends StatelessWidget {
  const _BillingTimeline({
    required this.now,
    required this.period,
    required this.dueStatusLabel,
    required this.dueNeedsAttention,
    this.showToday = true,
  });

  final DateTime now;
  final CreditCardBillingPeriod period;
  final String dueStatusLabel;
  final bool dueNeedsAttention;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(now);
    final dueDay = DateUtils.dateOnly(period.dueDate);
    final labelsByDay = <DateTime, List<String>>{};
    for (final (date, label) in [
      (period.cycleStartDate, '周期开始'),
      (period.statementDate, '已结算'),
      (dueDay, '还款日'),
      (period.nextStatementDate, '下期结算'),
      if (showToday) (today, '今天'),
    ]) {
      (labelsByDay[DateUtils.dateOnly(date)] ??= []).add(label);
    }
    final nodes = labelsByDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      key: const Key('credit-card-billing-timeline'),
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: List.generate(nodes.length, (index) {
              final day = nodes[index].key;
              final isDueDate = day == dueDay;
              final isOrange = isDueDate && dueNeedsAttention;
              final isToday = showToday && day == today;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: day.isAfter(today)
                            ? financePaletteOf(context).border
                            : financePaletteOf(context).seed,
                      ),
                    ),
                    Container(
                      width: isToday ? 16 : 12,
                      height: isToday ? 16 : 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: day.isAfter(today)
                            ? Colors.transparent
                            : financePaletteOf(context).seed,
                        border: Border.all(
                          color: isOrange
                              ? financePaletteOf(context).expense
                              : financePaletteOf(context).seed,
                          width: 2,
                        ),
                        boxShadow: isToday
                            ? [
                                BoxShadow(
                                  color: financePaletteOf(context)
                                      .seed
                                      .withValues(alpha: .35),
                                  blurRadius: 12,
                                  spreadRadius: 5,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: nodes
              .map(
                (item) => Expanded(
                  child: Column(
                    children: [
                      Text(
                        _shortDate(item.key),
                        style: TextStyle(
                          color: item.key == dueDay
                              ? financePaletteOf(context).expense
                              : showToday && item.key == today
                                  ? financePaletteOf(context).seed
                                  : null,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.value.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      if (item.key == dueDay)
                        Text(
                          dueStatusLabel,
                          style: TextStyle(
                            color: dueNeedsAttention
                                ? financePaletteOf(context).expense
                                : financePaletteOf(context).seed,
                            fontSize: 10,
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

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.item, required this.onTap});

  final _PresentedPurchase item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CompassIconBadge(icon: item.icon, outlined: true, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.date, style: Theme.of(context).textTheme.bodySmall),
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                Text(item.category,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                compassMoney(item.amount, currency: item.transaction.currency),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFeatures: compassTabularFigures,
                    ),
              ),
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
          ),
        ),
      );
}

class _PresentedPurchase {
  const _PresentedPurchase({
    required this.transaction,
    required this.date,
    required this.title,
    required this.category,
    required this.amount,
    required this.icon,
  });

  final FinanceTransaction transaction;
  final String date;
  final String title;
  final String category;
  final double amount;
  final IconData icon;
}

List<_PresentedPurchase> _presentedPurchases(
  FinanceRepository repository,
  Account account,
  CreditCardBillingPeriod period, {
  required bool unbilled,
  DateTime? cutoffDate,
}) {
  final matches = repository.transactions.where((item) {
    if (item.accountId != account.id ||
        !item.affectsBalance ||
        (cutoffDate != null && item.transactionDate.isAfter(cutoffDate))) {
      return false;
    }
    final day = creditCardSourceBillingDate(item, account.id);
    return unbilled ? period.containsUnbilled(day) : period.containsBilled(day);
  }).toList()
    ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  return matches.map(
    (item) {
      final isTransfer = item.type == TransactionType.transfer;
      final destinationName = !isTransfer || item.toAccountId == null
          ? '其他账户'
          : repository.accountName(item.toAccountId!);
      final charge = creditCardSourceCharge(item, account.id);
      final billingDay = creditCardSourceBillingDate(item, account.id);
      final occurred = _shortDate(item.transactionDate);
      final direction = switch (item.type) {
        TransactionType.income => '信用卡收入',
        TransactionType.adjustment => '信用卡调整',
        TransactionType.expense => charge < 0 ? '消费退款' : '信用卡消费',
        TransactionType.transfer => '转账至 $destinationName',
      };
      return _PresentedPurchase(
        transaction: item,
        date: DateUtils.isSameDay(item.transactionDate, billingDay)
            ? occurred
            : '$occurred · 入账 ${_shortDate(billingDay)}',
        title: item.merchant ?? item.description ?? direction,
        category: isTransfer
            ? '信用卡转出 · $destinationName'
            : item.categoryId == null
                ? direction
                : repository.categoryName(item.categoryId!),
        amount: charge,
        icon: isTransfer
            ? Icons.swap_horiz_rounded
            : categoryIcon(repository.categoryHierarchy.byId[item.categoryId]),
      );
    },
  ).toList();
}

String _shortDate(DateTime value) => '${value.month}月${value.day}日';

String _daysUntilLabel(DateTime now, DateTime date) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = target.difference(today).inDays;
  if (days == 0) return '今天';
  return days > 0 ? '还有 $days 天' : '已过 ${days.abs()} 天';
}

class _CreditCardDisplayCopy {
  const _CreditCardDisplayCopy({
    required this.amountLabel,
    required this.amount,
    required this.statusLabel,
    required this.dueStatusLabel,
    required this.paymentActionLabel,
    required this.color,
    required this.dueNeedsAttention,
    required this.canRepay,
  });

  final String amountLabel;
  final double amount;
  final String statusLabel;
  final String dueStatusLabel;
  final String paymentActionLabel;
  final Color color;
  final bool dueNeedsAttention;
  final bool canRepay;
}

_CreditCardDisplayCopy _selectedStatementDisplay(
  CreditCardBillingPeriod period,
  double amount,
  FinanceThemePalette palette, {
  required bool isFuture,
  required bool isCurrent,
}) {
  return _CreditCardDisplayCopy(
    amountLabel:
        '${period.billingMonthDate.year}年${period.billingMonthDate.month}月${isFuture ? '已确定账单' : '账单'}',
    amount: amount,
    statusLabel: isFuture ? '已确定' : (isCurrent ? '本期账单' : '历史账单'),
    dueStatusLabel: '还款日 ${_shortDate(period.dueDate)}',
    paymentActionLabel: isFuture ? '已确定' : '历史账单',
    color: amount > 0 ? palette.expense : palette.income,
    dueNeedsAttention: false,
    canRepay: false,
  );
}

_CreditCardDisplayCopy _creditCardDisplayCopy(
  CreditCardDisplayState state,
  CreditCardBillingSummary summary,
  DateTime now,
  FinanceThemePalette palette, {
  required double currentDebt,
}) {
  switch (state) {
    case CreditCardDisplayState.profileIncomplete:
      return _CreditCardDisplayCopy(
        amountLabel: '当前欠款（估算）',
        amount: currentDebt,
        statusLabel: '请设置账期',
        dueStatusLabel: '账期待设置',
        paymentActionLabel: '记录还款',
        color: palette.expense,
        dueNeedsAttention: true,
        canRepay: currentDebt > 0.005,
      );
    case CreditCardDisplayState.overdue:
      return _CreditCardDisplayCopy(
        amountLabel: '逾期应还',
        amount: summary.billedBalance,
        statusLabel: '逾期未还',
        dueStatusLabel: _daysUntilLabel(now, summary.dueDate),
        paymentActionLabel: '记录还款',
        color: palette.expense,
        dueNeedsAttention: true,
        canRepay: true,
      );
    case CreditCardDisplayState.dueToday:
      return _CreditCardDisplayCopy(
        amountLabel: '今日应还',
        amount: summary.billedBalance,
        statusLabel: '今日到期',
        dueStatusLabel: '今天到期',
        paymentActionLabel: '记录还款',
        color: palette.expense,
        dueNeedsAttention: true,
        canRepay: true,
      );
    case CreditCardDisplayState.paymentDue:
      return _CreditCardDisplayCopy(
        amountLabel: '本期应还',
        amount: summary.billedBalance,
        statusLabel: '待还款',
        dueStatusLabel: _daysUntilLabel(now, summary.dueDate),
        paymentActionLabel: '记录还款',
        color: palette.expense,
        dueNeedsAttention: true,
        canRepay: true,
      );
    case CreditCardDisplayState.paidThisCycle:
      return _CreditCardDisplayCopy(
        amountLabel: summary.unbilledBalance > 0 ? '下期已使用额度' : '本期账单',
        amount: summary.unbilledBalance,
        statusLabel: '本期已还清',
        dueStatusLabel: '本期已还清',
        paymentActionLabel: currentDebt > 0.005 ? '提前还款' : '无需还款',
        color: palette.income,
        dueNeedsAttention: false,
        canRepay: currentDebt > 0.005,
      );
    case CreditCardDisplayState.unbilledOnly:
      // Committed debt can sit beyond the next cycle; show it rather than 0.
      final hasNextCycleUsage = summary.unbilledBalance > 0.005;
      return _CreditCardDisplayCopy(
        amountLabel: hasNextCycleUsage ? '下期已使用额度' : '当前欠款',
        amount: hasNextCycleUsage ? summary.unbilledBalance : currentDebt,
        statusLabel: '尚未出账',
        dueStatusLabel: '本期无需还款',
        paymentActionLabel: '提前还款',
        color: palette.income,
        dueNeedsAttention: false,
        canRepay: true,
      );
    case CreditCardDisplayState.noBalance:
      return _CreditCardDisplayCopy(
        amountLabel: '当前欠款',
        amount: 0,
        statusLabel: '暂无欠款',
        dueStatusLabel: '本期无需还款',
        paymentActionLabel: '无需还款',
        color: palette.income,
        dueNeedsAttention: false,
        canRepay: false,
      );
  }
}
