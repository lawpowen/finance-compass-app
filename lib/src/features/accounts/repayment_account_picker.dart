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
  if (ledger.repaymentSources(debt.id).isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('请先建立或启用一个 ${debt.currency} 资金账户。')),
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
            if (sources.isEmpty) const Text('当前没有可用的还款账户。'),
            for (final payer in sources)
              ListTile(
                key: ValueKey(
                    '${debt.accountType == AccountType.creditCard ? 'credit-card' : 'loan'}-repayment-source-${payer.id}'),
                title: Text(payer.name),
                subtitle: Text(payer.currency),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, payer),
              ),
          ],
        ));
      }),
    ),
  );
}
