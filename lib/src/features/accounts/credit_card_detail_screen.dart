import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/credit_card_billing.dart';
import '../../core/models/transaction.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/mutations/transaction_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';
import '../transactions/transaction_composer_page.dart';
import '../transactions/transaction_form_dialog.dart';
import 'account_form_dialog.dart';

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
    final liveAccount = liveRepository.accounts.firstWhere(
      (item) => item.id == widget.account.id,
      orElse: () => widget.account,
    );
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
    final summary = calculateCreditCardBilling(
      account: liveAccount,
      transactions: scopedTransactions,
      now: now,
      balanceAtCutoff: liveRepository.accountBalanceAt(
        liveAccount.id,
        now,
      ),
    );
    final limit = liveAccount.creditLimit ?? 10000;
    final usageAmount = isHistoricalCutoff
        ? liveRepository.accountBalanceAt(liveAccount.id, now).abs()
        : liveRepository.creditCardCommittedOutstandingBalance(liveAccount.id);
    final usage = (usageAmount / limit).clamp(0, 1).toDouble();
    final isSelectedStatement = selectedHistoricalStatementDate != null;
    final period = isSelectedStatement
        ? calculateCreditCardBillingPeriodForStatement(
            statementDay: statementDay,
            paymentDueDay: paymentDay,
            statementDate: selectedHistoricalStatementDate!,
          )
        : currentPeriod;
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
      period,
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
    );
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
            isFuture: isFutureStatement,
          )
        : _creditCardDisplayCopy(displayState, summary, now);

    return Scaffold(
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
                  const CompassIconBadge(
                    icon: Icons.credit_card_rounded,
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${liveAccount.name}  ···· ${_cardSuffix(liveAccount)}',
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
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StatusPill(
                          label: display.statusLabel,
                          color: display.color,
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
                          onPressed: display.canRepay && !isHistoricalCutoff
                              ? () => _addRepayment(
                                    context,
                                    liveRepository,
                                    liveAccount,
                                    display.amount,
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
                            now,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            foregroundColor: FinanceColors.compassTeal,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text('账单周期时间线',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(width: 7),
                        const Icon(Icons.info_outline_rounded, size: 17),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '消费与信用卡转出会按交易日期自动归入对应账单',
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
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
                    '额度使用 ${(usage * 100).round()}%',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${compassMoney(usageAmount)} / ${compassMoney(limit)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: usage,
                minHeight: 6,
                borderRadius: BorderRadius.circular(8),
                color: FinanceColors.compassTeal,
                backgroundColor: FinanceColors.compassBorder,
              ),
              const SizedBox(height: 18),
              compassHairline,
              if (isSelectedStatement)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${period.billingMonthDate.year}年${period.billingMonthDate.month}月${isFutureStatement ? '已确定' : '历史'}账单',
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
                  labels: const ['本期账单', '未出账'],
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
                          : '未出账周期 ${_shortDate(period.statementDate.add(const Duration(days: 1)))}—${_shortDate(period.nextStatementDate)} · 共 ${purchases.length} 笔',
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
                      selectedStatement == 0 ? '本账期没有信用卡消费或转出' : '当前没有未出账消费或转出',
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
                              ? '${period.billingMonthDate.year}年${period.billingMonthDate.month}月${isFutureStatement ? '已确定' : '历史'}账单明细'
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
    DateTime now,
  ) async {
    if (!account.hasCompleteCreditCardProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置结算日和还款日，才能查看账单月份。')),
      );
      return;
    }
    final periods = availableCreditCardBillingPeriods(
      account: account,
      transactions: repository.transactions,
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
                    final isSelected = isCurrent
                        ? selectedHistoricalStatementDate == null
                        : selectedHistoricalStatementDate == item.statementDate;
                    final amount = calculateCreditCardOriginalStatementAmount(
                      accountId: account.id,
                      transactions: repository.transactions,
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
                                        ? FinanceColors.compassOrange
                                        : FinanceColors.compassMuted,
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
                                  ? FinanceColors.compassTeal
                                  : FinanceColors.compassMuted,
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
      selectedHistoricalStatementDate =
          selected.statementDate == currentPeriod.statementDate
              ? null
              : selected.statementDate;
      selectedStatement = 0;
    });
  }

  Future<void> _editAccount(BuildContext context, Account current) async {
    final updated = await showDialog<Account>(
      context: context,
      builder: (_) => AccountFormDialog(initialAccount: current),
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
    final sources = repo.accounts
        .where(
          (item) =>
              item.id != card.id &&
              item.reportGroup == ReportGroup.cash &&
              item.currency == card.currency,
        )
        .toList();
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先建立一个 ${card.currency} 资金账户。')),
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
                key: Key('credit-card-repayment-source-${item.id}'),
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
    if (!context.mounted || source == null) return;

    final amountController = TextEditingController(
      text: suggestedAmount.toStringAsFixed(2),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('记录信用卡还款'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('从 ${source.name} 转账至 ${card.name}'),
            const SizedBox(height: 14),
            TextField(
              key: const Key('credit-card-repayment-amount'),
              controller: amountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '还款金额',
                prefixText: '${card.currency} ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('credit-card-repayment-confirm'),
            onPressed: () {
              final value = double.tryParse(amountController.text.trim());
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('请输入大于 0 的还款金额。')),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('确认记录'),
          ),
        ],
      ),
    );
    if (!context.mounted || amount == null) return;

    final now = DateTime.now();
    await ref.read(transactionMutationsProvider.notifier).addTransaction(
          FinanceTransaction(
            id: buildId('txn_card_payment'),
            type: TransactionType.transfer,
            accountId: source.id,
            toAccountId: card.id,
            amount: amount,
            currency: source.currency,
            toCurrency: card.currency,
            recordDate: now,
            transactionDate: now,
            description: '信用卡还款',
          ),
        );
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
    final labels = <(DateTime, String, bool)>[
      (period.cycleStartDate, '周期开始', false),
      (period.statementDate, '已结算', false),
      if (showToday) (now, '今天', false),
      (period.dueDate, '还款日', true),
      (period.nextStatementDate, '下期结算', false),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return Column(
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: List.generate(labels.length, (index) {
              final isDueDate = labels[index].$3;
              final isOrange = isDueDate && dueNeedsAttention;
              final isToday = labels[index].$2 == '今天';
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: labels[index].$1.isAfter(now)
                            ? FinanceColors.compassBorder
                            : FinanceColors.compassTeal,
                      ),
                    ),
                    Container(
                      width: isToday ? 16 : 12,
                      height: isToday ? 16 : 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: labels[index].$1.isAfter(now)
                            ? Colors.transparent
                            : FinanceColors.compassTeal,
                        border: Border.all(
                          color: isOrange
                              ? FinanceColors.compassOrange
                              : FinanceColors.compassTeal,
                          width: 2,
                        ),
                        boxShadow: isToday
                            ? [
                                BoxShadow(
                                  color: FinanceColors.compassTeal
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
          children: labels
              .map(
                (item) => Expanded(
                  child: Column(
                    children: [
                      Text(
                        _shortDate(item.$1),
                        style: TextStyle(
                          color: item.$3
                              ? FinanceColors.compassOrange
                              : item.$2 == '今天'
                                  ? FinanceColors.compassTeal
                                  : null,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      if (item.$3)
                        Text(
                          dueStatusLabel,
                          style: TextStyle(
                            color: dueNeedsAttention
                                ? FinanceColors.compassOrange
                                : FinanceColors.compassTeal,
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
                compassMoney(item.amount),
                style: Theme.of(context).textTheme.titleSmall,
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
  final matches = repository.transactions
      .where((item) =>
          item.accountId == account.id &&
          (cutoffDate == null || !item.transactionDate.isAfter(cutoffDate)) &&
          (item.type == TransactionType.expense ||
              item.type == TransactionType.transfer) &&
          item.affectsBalance &&
          (unbilled
              ? period.containsUnbilled(item.transactionDate)
              : period.containsBilled(item.transactionDate)))
      .toList()
    ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  return matches.map(
    (item) {
      final isTransfer = item.type == TransactionType.transfer;
      final destinationName = item.toAccountId == null
          ? '其他账户'
          : repository.accountName(item.toAccountId!);
      return _PresentedPurchase(
        transaction: item,
        date: '${item.transactionDate.month}月${item.transactionDate.day}日',
        title: isTransfer
            ? (item.description ?? '转账至 $destinationName')
            : item.merchant ?? item.description ?? '信用卡消费',
        category: isTransfer
            ? '信用卡转出 · $destinationName'
            : item.categoryId == null
                ? '消费'
                : repository.categoryName(item.categoryId!),
        amount: item.amount,
        icon: isTransfer
            ? Icons.swap_horiz_rounded
            : _purchaseIcon(item.categoryId),
      );
    },
  ).toList();
}

String _cardSuffix(Account account) {
  final digits =
      RegExp(r'\d').allMatches(account.note ?? '').map((m) => m[0]).join();
  return digits.length >= 4 ? digits.substring(digits.length - 4) : '1234';
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
  double amount, {
  required bool isFuture,
}) {
  return _CreditCardDisplayCopy(
    amountLabel:
        '${period.billingMonthDate.year}年${period.billingMonthDate.month}月${isFuture ? '已确定账单' : '账单'}',
    amount: amount,
    statusLabel: isFuture ? '已确定' : '历史账单',
    dueStatusLabel: '还款日 ${_shortDate(period.dueDate)}',
    paymentActionLabel: isFuture ? '已确定' : '历史账单',
    color: amount > 0 ? FinanceColors.compassOrange : FinanceColors.compassTeal,
    dueNeedsAttention: false,
    canRepay: false,
  );
}

_CreditCardDisplayCopy _creditCardDisplayCopy(
  CreditCardDisplayState state,
  CreditCardBillingSummary summary,
  DateTime now,
) {
  switch (state) {
    case CreditCardDisplayState.profileIncomplete:
      return _CreditCardDisplayCopy(
        amountLabel: '当前欠款（估算）',
        amount: summary.outstandingBalance,
        statusLabel: '请设置账期',
        dueStatusLabel: '账期待设置',
        paymentActionLabel: '记录还款',
        color: FinanceColors.compassOrange,
        dueNeedsAttention: true,
        canRepay: summary.outstandingBalance > 0.005,
      );
    case CreditCardDisplayState.overdue:
      return _CreditCardDisplayCopy(
        amountLabel: '逾期应还',
        amount: summary.billedBalance,
        statusLabel: '逾期未还',
        dueStatusLabel: _daysUntilLabel(now, summary.dueDate),
        paymentActionLabel: '记录还款',
        color: FinanceColors.compassOrange,
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
        color: FinanceColors.compassOrange,
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
        color: FinanceColors.compassOrange,
        dueNeedsAttention: true,
        canRepay: true,
      );
    case CreditCardDisplayState.paidThisCycle:
      return _CreditCardDisplayCopy(
        amountLabel: summary.unbilledBalance > 0 ? '下期已使用额度' : '本期账单',
        amount: summary.unbilledBalance,
        statusLabel: '本期已还清',
        dueStatusLabel: '本期已还清',
        paymentActionLabel: summary.unbilledBalance > 0 ? '提前还款' : '无需还款',
        color: FinanceColors.compassTeal,
        dueNeedsAttention: false,
        canRepay: summary.outstandingBalance > 0.005,
      );
    case CreditCardDisplayState.unbilledOnly:
      return _CreditCardDisplayCopy(
        amountLabel: '下期已使用额度',
        amount: summary.unbilledBalance,
        statusLabel: '尚未出账',
        dueStatusLabel: '本期无需还款',
        paymentActionLabel: '提前还款',
        color: FinanceColors.compassTeal,
        dueNeedsAttention: false,
        canRepay: true,
      );
    case CreditCardDisplayState.noBalance:
      return const _CreditCardDisplayCopy(
        amountLabel: '当前欠款',
        amount: 0,
        statusLabel: '暂无欠款',
        dueStatusLabel: '本期无需还款',
        paymentActionLabel: '无需还款',
        color: FinanceColors.compassTeal,
        dueNeedsAttention: false,
        canRepay: false,
      );
  }
}

IconData _purchaseIcon(String? categoryId) {
  if (categoryId?.contains('food') ?? false) return Icons.restaurant_outlined;
  if (categoryId?.contains('transport') ?? false) {
    return Icons.local_gas_station_outlined;
  }
  return Icons.shopping_bag_outlined;
}
