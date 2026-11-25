import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/account.dart';
import '../../core/providers/repository_provider.dart';

Future<Account?> pickRepaymentAccount(
  BuildContext context,
  FinanceRepository ledger,
  Account debt,
) async {
  if (!debt.isActive) return null;
  final isCard = debt.accountType == AccountType.creditCard;
  final emptyMessage = isCard
      ? '请先建立或启用一个 ${debt.currency} 现金账户或其他同币种信用卡。'
      : '请先建立或启用一个 ${debt.currency} 现金账户用于偿还贷款。';
  if (ledger.repaymentSources(debt.id).isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(emptyMessage)),
    );
    return null;
  }
  // A modal on the outer navigator must keep the session of the originating tab.
  final scope = ProviderScope.containerOf(context, listen: false);
  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => UncontrolledProviderScope(
      container: scope,
      child: Consumer(builder: (context, ref, _) {
        final latest =
            ref.watch(financeRepositoryProvider).valueOrNull ?? ledger;
        final sources = identical(ledger.database, latest.database)
            ? latest.repaymentSources(debt.id)
            : const <Account>[];
        return SafeArea(
            child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择还款账户', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (sources.isEmpty) Text(emptyMessage),
            for (final payer in sources)
              ListTile(
                key: ValueKey(
                    '${isCard ? 'credit-card' : 'loan'}-repayment-source-${payer.id}'),
                title: Text(payer.name),
                subtitle: Text(
                    '${payer.accountType == AccountType.creditCard ? '信用卡' : '现金账户'} · ${payer.currency}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, payer),
              ),
          ],
        ));
      }),
    ),
  );
}
