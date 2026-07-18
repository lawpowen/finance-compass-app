import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/models/credit_card_billing.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';
import 'account_detail_screen.dart';
import 'account_form_dialog.dart';
import 'credit_card_detail_screen.dart';

class AccountsV2Screen extends ConsumerStatefulWidget {
  const AccountsV2Screen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<AccountsV2Screen> createState() => _AccountsV2ScreenState();
}

class _AccountsV2ScreenState extends ConsumerState<AccountsV2Screen> {
  int selectedGroup = 1;

  FinanceRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cash = repository.totalAssetsByGroup(ReportGroup.cash);
    final investment = repository.totalAssetsByGroup(ReportGroup.investment);
    final retirement = repository.totalAssetsByGroup(ReportGroup.retirement);
    final totalAssets = cash + investment + retirement;
    final creditAccounts = repository.accounts
        .where((account) => account.accountType == AccountType.creditCard)
        .toList();
    final loanAccounts = repository.accounts
        .where((account) => account.accountType == AccountType.loan)
        .toList();
    final creditLiability = creditAccounts.fold<double>(0, (sum, account) {
      return sum +
          repository.convertToBase(
            repository.creditCardCommittedOutstandingBalance(account.id),
            account.currency,
          );
    });
    final loanLiability = loanAccounts.fold<double>(
      0,
      (sum, account) =>
          sum +
          repository
              .accountBalanceAt(account.id, repository.currentMonthCutoffDate())
              .abs(),
    );
    final liabilities = creditLiability + loanLiability;
    final netAssets = totalAssets - liabilities;
    final visibleAccounts = _accountsForGroup(selectedGroup);

    return ListView(
      padding: compassPagePadding.copyWith(bottom: 30),
      children: [
        CompassPageHeader(
          title: '账户',
          actions: [
            CompassIconBadge(
              icon: Icons.person_rounded,
              size: 38,
              color: FinanceColors.compassTeal,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              height: 40,
              child: OutlinedButton(
                onPressed: () => _editAccount(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  side: const BorderSide(color: FinanceColors.compassMuted),
                  foregroundColor: FinanceColors.compassMuted,
                ),
                child: const Icon(Icons.add_rounded, size: 26),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('净资产', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        Text(
          compassMoney(netAssets),
          style: const TextStyle(
            color: FinanceColors.compassTeal,
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AmountSummary(label: '总资产', value: totalAssets),
            ),
            Container(
              width: 1,
              height: 86,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              color: FinanceColors.compassBorder,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AmountSummary(label: '负债', value: liabilities),
                  const SizedBox(height: 12),
                  _BreakdownLine(label: '信用卡', value: creditLiability),
                  const SizedBox(height: 5),
                  _BreakdownLine(label: '贷款', value: loanLiability),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const CompassSectionTitle('资产分布'),
        const SizedBox(height: 9),
        CompassDistributionBar(
          values: [cash, investment, retirement],
          colors: const [
            FinanceColors.compassTeal,
            Color(0xFF5F9464),
            Color(0xFF7B5BA4),
          ],
          height: 10,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _AllocationMetric(
                label: '现金',
                value: cash,
                total: totalAssets,
                color: FinanceColors.compassTeal,
              ),
            ),
            _VerticalDivider(),
            Expanded(
              child: _AllocationMetric(
                label: '投资',
                value: investment,
                total: totalAssets,
                color: const Color(0xFF6AA064),
              ),
            ),
            _VerticalDivider(),
            Expanded(
              child: _AllocationMetric(
                label: '退休',
                value: retirement,
                total: totalAssets,
                color: const Color(0xFF8A63B4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_month_outlined, size: 18),
            const SizedBox(width: 8),
            Text(
              '统计截止 · ${now.year}年${now.month}月',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
        const SizedBox(height: 14),
        _AccountGroupSelector(
          selectedIndex: selectedGroup,
          onChanged: (index) => setState(() => selectedGroup = index),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              _groupLabel(selectedGroup),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            if (selectedGroup == 1)
              Text(
                '负债总额  ${compassMoney(creditLiability)}',
                style: const TextStyle(
                  color: FinanceColors.compassOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (visibleAccounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 34),
            child: Center(
              child: Text(
                '此分类还没有账户',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          ...visibleAccounts.map(
            (account) => _AccountRow(
              account: account,
              repository: repository,
              onTap: () => _openAccount(context, account),
            ),
          ),
        if (selectedGroup == 1) ...[
          compassHairline,
          CompassSettingsRow(
            icon: Icons.calendar_month_outlined,
            title: '管理信用卡账期',
            subtitle: '查看与管理所有信用卡结算日与还款日',
            onTap: () => _manageCreditCards(context),
          ),
        ],
      ],
    );
  }

  List<Account> _accountsForGroup(int index) => switch (index) {
        0 => repository.accountsByGroup(ReportGroup.cash),
        1 => repository.accounts
            .where((item) => item.accountType == AccountType.creditCard)
            .toList(),
        2 => repository.accounts
            .where((item) => item.accountType == AccountType.loan)
            .toList(),
        3 => repository.accountsByGroup(ReportGroup.investment),
        _ => repository.accountsByGroup(ReportGroup.retirement),
      };

  Future<void> _editAccount(BuildContext context) async {
    final account = await showDialog<Account>(
      context: context,
      builder: (_) => const AccountFormDialog(),
    );
    if (account != null) {
      await ref.read(accountMutationsProvider.notifier).addAccount(account);
    }
  }

  void _openAccount(BuildContext context, Account account) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => account.accountType == AccountType.creditCard
            ? CreditCardDetailScreen(account: account, repository: repository)
            : AccountDetailScreen(account: account, repository: repository),
      ),
    );
  }

  Future<void> _manageCreditCards(BuildContext context) async {
    final cards = repository.accounts
        .where((item) => item.accountType == AccountType.creditCard)
        .toList();
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有信用卡账户。')),
      );
      return;
    }
    final selected = await showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择信用卡', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...cards.map(
              (card) => ListTile(
                title: Text(card.name),
                subtitle: Text(
                    '结算日 ${card.statementDay ?? '-'} · 还款日 ${card.paymentDueDay ?? '-'}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, card),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      _openAccount(context, selected);
    }
  }
}

class _AmountSummary extends StatelessWidget {
  const _AmountSummary({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              compassMoney(value),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(compassMoney(value, decimals: 0),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _AllocationMetric extends StatelessWidget {
  const _AllocationMetric({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final double value;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            '${total == 0 ? 0 : (value / total * 100).round()}%',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(label),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              compassMoney(value),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 48,
        color: FinanceColors.compassBorder,
      );
}

class _AccountGroupSelector extends StatelessWidget {
  const _AccountGroupSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['现金', '信用', '贷款', '投资', '退休'];
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border.all(color: FinanceColors.compassBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? FinanceColors.compassTeal.withValues(alpha: .65)
                      : Colors.transparent,
                  border: index == 0
                      ? null
                      : const Border(
                          left: BorderSide(color: FinanceColors.compassBorder),
                        ),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected ? Colors.white : FinanceColors.compassText,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.repository,
    required this.onTap,
  });

  final Account account;
  final FinanceRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final billing = account.accountType == AccountType.creditCard
        ? calculateCreditCardBilling(
            account: account,
            transactions: repository.transactions,
            balanceAtCutoff: repository.accountBalanceAt(
              account.id,
              now,
            ),
          )
        : null;
    final cardDisplay = billing == null
        ? null
        : _accountCardDisplay(
            resolveCreditCardDisplayState(
              summary: billing,
              hasBilledActivity: hasCreditCardBilledActivity(
                account: account,
                transactions: repository.transactions,
                now: now,
              ),
              now: now,
            ),
            billing,
          );
    final amount = billing == null
        ? repository
            .accountBalanceAt(
              account.id,
              repository.currentMonthCutoffDate(),
            )
            .abs()
        : repository.creditCardCommittedOutstandingBalance(account.id);
    final subtitle = billing == null
        ? [account.institution, account.currency]
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .join(' · ')
        : billing.isEstimated
            ? '账期日期待设置 · 当前为估算提醒'
            : '结算日 ${account.statementDay}日 · 还款日 ${account.paymentDueDay}日';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            CompassIconBadge(
              icon: _accountIcon(account.accountType),
              color: account.accountType == AccountType.creditCard
                  ? FinanceColors.compassTeal
                  : FinanceColors.compassTeal,
              size: 48,
              outlined: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${account.name}${account.accountType == AccountType.creditCard ? ' · ${_cardSuffix(account)}' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  if (billing != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cardDisplay!.color.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cardDisplay.statusLabel,
                        style: TextStyle(
                          color: cardDisplay.color,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (billing != null)
                  Text(
                    '当前欠款',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 4),
                Text(
                  compassMoney(amount),
                  style: TextStyle(
                    color: cardDisplay != null
                        ? cardDisplay.color
                        : FinanceColors.compassText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 25),
          ],
        ),
      ),
    );
  }
}

class _AccountCardDisplay {
  const _AccountCardDisplay({
    required this.amountLabel,
    required this.amount,
    required this.statusLabel,
    required this.color,
  });

  final String amountLabel;
  final double amount;
  final String statusLabel;
  final Color color;
}

_AccountCardDisplay _accountCardDisplay(
  CreditCardDisplayState state,
  CreditCardBillingSummary summary,
) {
  switch (state) {
    case CreditCardDisplayState.overdue:
      return _AccountCardDisplay(
        amountLabel: '逾期账单',
        amount: summary.billedBalance,
        statusLabel: '逾期未还',
        color: FinanceColors.compassOrange,
      );
    case CreditCardDisplayState.dueToday:
      return _AccountCardDisplay(
        amountLabel: '今日应还',
        amount: summary.billedBalance,
        statusLabel: '今日到期',
        color: FinanceColors.compassOrange,
      );
    case CreditCardDisplayState.paymentDue:
      return _AccountCardDisplay(
        amountLabel: '本期账单',
        amount: summary.billedBalance,
        statusLabel: '待还款',
        color: FinanceColors.compassOrange,
      );
    case CreditCardDisplayState.paidThisCycle:
      return _AccountCardDisplay(
        amountLabel: summary.unbilledBalance > 0 ? '下期已使用' : '本期账单',
        amount: summary.unbilledBalance,
        statusLabel: '本期已还清',
        color: FinanceColors.compassTeal,
      );
    case CreditCardDisplayState.unbilledOnly:
      return _AccountCardDisplay(
        amountLabel: '下期已使用',
        amount: summary.unbilledBalance,
        statusLabel: '尚未出账',
        color: FinanceColors.compassTeal,
      );
    case CreditCardDisplayState.noBalance:
      return const _AccountCardDisplay(
        amountLabel: '当前欠款',
        amount: 0,
        statusLabel: '暂无欠款',
        color: FinanceColors.compassTeal,
      );
    case CreditCardDisplayState.profileIncomplete:
      return _AccountCardDisplay(
        amountLabel: '当前欠款（估算）',
        amount: summary.outstandingBalance,
        statusLabel: '账期待设置',
        color: FinanceColors.compassOrange,
      );
  }
}

String _groupLabel(int index) => switch (index) {
      0 => '现金账户',
      1 => '信用卡',
      2 => '贷款',
      3 => '投资账户',
      _ => '退休账户',
    };

IconData _accountIcon(AccountType type) => switch (type) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.bankSaving => Icons.account_balance_outlined,
      AccountType.eWallet => Icons.wallet_outlined,
      AccountType.creditCard => Icons.credit_card_rounded,
      AccountType.moneyMarketFund || AccountType.fund => Icons.savings_outlined,
      AccountType.pension => Icons.beach_access_outlined,
      AccountType.stock ||
      AccountType.trading =>
        Icons.candlestick_chart_outlined,
      AccountType.crypto => Icons.currency_bitcoin,
      AccountType.loan => Icons.request_quote_outlined,
      AccountType.other => Icons.account_balance_wallet_outlined,
    };

String _cardSuffix(Account account) {
  final digits =
      RegExp(r'\d').allMatches(account.note ?? '').map((m) => m[0]).join();
  return digits.length >= 4 ? digits.substring(digits.length - 4) : '1234';
}
